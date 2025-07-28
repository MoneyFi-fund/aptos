module moneyfi::vault {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string;
    use std::option;
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp::now_seconds;

    use moneyfi::access_control;
    use moneyfi::wallet_account::{Self, WalletAccount};
    use moneyfi::storage;
    use moneyfi::strategy;

    // -- Constants
    const LP_TOKEN_NAME: vector<u8> = b"MoneyFi LP";
    const LP_TOKEN_SYMBOL: vector<u8> = b"MoneyFiLP";
    const LP_TOKEN_DECIMALS: u8 = 9;
    const FUNDING_ACCOUNT_SEED: vector<u8> = b"FUNDING_ACCOUNT";

    // -- Errors
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_DEPOSIT_NOT_ALLOWED: u64 = 2;
    const E_WITHDRAW_NOT_ALLOWED: u64 = 3;

    // -- Structs
    struct Config has key {
        enable_deposit: bool,
        enable_withdraw: bool,
        system_fee_percent: u64, // 100 => 1%
        referral_percents: vector<u64>, // 100 => 1%
        supported_assets: OrderedMap<address, AssetConfig>
    }

    struct AssetConfig has store, copy, drop {
        enabled: bool,
        min_deposit: u64,
        max_deposit: u64,
        min_withdraw: u64,
        max_withdraw: u64,
        lp_exchange_rate: u64
    }

    struct LPToken has key {
        token: Object<Metadata>,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        extend_ref: ExtendRef
    }

    struct FundingAccount has key {
        extend_ref: ExtendRef,
        assets: OrderedMap<address, FundingAsset>
    }

    struct FundingAsset has store, copy, drop {
        // total current amount of all accounts
        total_amount: u128,
        // total lp supply
        total_lp_amount: u128,
        total_distributed_amount: u128,
        // accumulated fee
        total_fee_amount: u64,
        // withdrawable fee
        pending_fee_amount: u64,
        // account_address => amount
        pending_referral_fees: OrderedMap<address, u64>
    }

    //  -- events

    #[event]
    struct DepositedEvent has drop, store {
        sender: address,
        wallet_account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64,
        timestamp: u64
    }

    #[event]
    struct WithdrawnEvent has drop, store {
        sender: address,
        wallet_account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64,
        timestamp: u64
    }

    //-- Events
    #[event]
    struct UpsertAssetSupportedEvent has drop, store {
        asset_addr: address,
        min_deposit: u64,
        max_deposit: u64,
        min_withdraw: u64,
        max_withdraw: u64,
        lp_exchange_rate: u64,
        timestamp: u64
    }

    #[event]
    struct ConfigureEvent has drop, store {
        enable_deposit: bool,
        enable_withdraw: bool,
        system_fee_percent: u64,
        referral_percents: vector<u64>,
        timestamp: u64
    }

    #[event]
    struct DepositToStrategyEvent has drop, store {
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        strategy: u8,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct WithdrawFromStrategyEvent has drop, store {
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        strategy: u8,
        amount: u64,
        interest_amount: u64,
        system_fee: u64,
        timestamp: u64
    }

    #[event]
    struct SwapAssetsEvent has drop, store {
        account: Object<WalletAccount>,
        strategy: u8,
        from_asset: Object<Metadata>,
        to_asset: Object<Metadata>,
        amount_in: u64,
        amount_out: u64,
        lp_amount_in: u64,
        lp_amount_out: u64,
        timestamp: u64
    }

    #[event]
    struct WithdrawFeeEvent has drop, store {
        asset: Object<Metadata>,
        amount: u64,
        timestamp: u64
    }

    // -- init
    fun init_module(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(
            !exists<Config>(addr),
            error::already_exists(E_ALREADY_INITIALIZED)
        );

        init_funding_account();

        move_to(
            sender,
            Config {
                enable_deposit: true,
                enable_withdraw: true,
                system_fee_percent: 2000, // 20%
                referral_percents: vector[2500],
                supported_assets: ordered_map::new()
            }
        );

        init_lp_token(sender);
    }

    // -- Entries
    public entry fun configure(
        sender: &signer,
        enable_deposit: bool,
        enable_withdraw: bool,
        system_fee_percent: u64,
        referral_percents: vector<u64>
    ) acquires Config {
        assert!(system_fee_percent <= 10000);
        // TODO: validate referrals_percents

        access_control::must_be_admin(sender);
        let config = borrow_global_mut<Config>(@moneyfi);

        config.enable_deposit = enable_deposit;
        config.enable_withdraw = enable_withdraw;
        config.system_fee_percent = system_fee_percent;
        config.referral_percents = referral_percents;

        event::emit(
            ConfigureEvent {
                enable_deposit,
                enable_withdraw,
                system_fee_percent,
                referral_percents,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun upsert_supported_asset(
        sender: &signer,
        asset: Object<Metadata>,
        enabled: bool,
        min_deposit: u64,
        max_deposit: u64,
        min_withdraw: u64,
        max_withdraw: u64,
        lp_exchange_rate: u64
    ) acquires Config {
        access_control::must_be_service_account(sender);
        let config = borrow_global_mut<Config>(@moneyfi);

        config.upsert_asset(
            asset,
            AssetConfig {
                enabled,
                min_deposit,
                max_deposit,
                min_withdraw,
                max_withdraw,
                lp_exchange_rate
            }
        );
        event::emit(
            UpsertAssetSupportedEvent {
                asset_addr: object::object_address<Metadata>(&asset),
                min_deposit,
                max_deposit,
                min_withdraw,
                max_withdraw,
                lp_exchange_rate,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun deposit(
        sender: &signer, asset: Object<Metadata>, amount: u64
    ) acquires Config, LPToken, FundingAccount {
        let config = borrow_global<Config>(@moneyfi);
        assert!(
            config.can_deposit(asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );

        let wallet_addr = signer::address_of(sender);
        let account = wallet_account::get_wallet_account_by_address(wallet_addr);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data = funding_account.get_funding_asset(asset);

        let asset_config = config.get_asset_config(asset);
        let lp_amount = asset_config.calc_mint_lp_amount(amount);
        let account_addr = object::object_address(&account);

        primary_fungible_store::transfer(sender, asset, account_addr, amount);
        wallet_account::deposit(account, asset, amount, lp_amount);
        mint_lp(wallet_addr, lp_amount);

        asset_data.total_lp_amount = asset_data.total_lp_amount + (lp_amount as u128);
        asset_data.total_amount = asset_data.total_amount + (amount as u128);
        funding_account.set_funding_asset(asset, asset_data);

        event::emit(
            DepositedEvent {
                sender: wallet_addr,
                wallet_account: account,
                asset,
                amount,
                lp_amount,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun withdraw(
        sender: &signer, asset: Object<Metadata>, amount: u64
    ) acquires Config, LPToken, FundingAccount {
        let wallet_addr = signer::address_of(sender);
        let account = wallet_account::get_wallet_account_by_address(wallet_addr);
        let account_addr = object::object_address(&account);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data = funding_account.get_funding_asset(asset);

        // transfer pending referral fee to wallet account first
        let pending_referral_fee = asset_data.get_pending_referral_fee(account);
        if (pending_referral_fee > 0) {
            let account_signer = funding_account.get_funding_account_signer();
            primary_fungible_store::transfer(
                &account_signer,
                asset,
                account_addr,
                pending_referral_fee
            );
            ordered_map::remove(&mut asset_data.pending_referral_fees, &account_addr);
        };

        let balance = primary_fungible_store::balance(account_addr, asset);
        if (amount > balance) {
            amount = balance;
        };

        let config = borrow_global<Config>(@moneyfi);
        assert!(
            config.can_withdraw(asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );

        let account_signer = wallet_account::get_wallet_account_signer(account);

        primary_fungible_store::transfer(&account_signer, asset, wallet_addr, amount);
        let lp_amount = wallet_account::withdraw(account, asset, amount);
        burn_lp(wallet_addr, lp_amount);

        assert!(asset_data.total_lp_amount >= (lp_amount as u128));
        assert!(asset_data.total_amount >= (amount as u128));

        asset_data.total_lp_amount = asset_data.total_lp_amount - (lp_amount as u128);
        asset_data.total_amount = asset_data.total_amount - (amount as u128);
        funding_account.set_funding_asset(asset, asset_data);

        event::emit(
            WithdrawnEvent {
                sender: wallet_addr,
                wallet_account: account,
                asset,
                amount,
                lp_amount,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun withdraw_fee(
        sender: &signer,
        to: address,
        asset: Object<Metadata>,
        amount: u64
    ) acquires FundingAccount {
        access_control::must_be_admin(sender);
        withdraw_fee_single_asset(asset, amount, to);

        event::emit(WithdrawFeeEvent { asset, amount, timestamp: now_seconds() })
    }

    public entry fun withdraw_all_fee(sender: &signer, to: address) acquires FundingAccount {
        access_control::must_be_admin(sender);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global<FundingAccount>(funding_account_addr);

        let (asset_addrs, asset_datas) = ordered_map::to_vec_pair(funding_account.assets);
        let len = vector::length(&asset_addrs);
        let i = 0;
        while (i < len) {
            let asset_addr = *vector::borrow(&asset_addrs, i);
            let asset_data = *vector::borrow(&asset_datas, i);
            let asset_obj = object::address_to_object<Metadata>(asset_addr);
            let fee_amount = asset_data.pending_fee_amount;
            if (fee_amount > 0) {
                withdraw_fee_single_asset(asset_obj, fee_amount, to);

                event::emit(
                    WithdrawFeeEvent {
                        asset: asset_obj,
                        amount: fee_amount,
                        timestamp: now_seconds()
                    }
                )
            };
            i = i + 1;
        };
    }

    public entry fun deposit_to_strategy(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<u8>
    ) {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let amount = strategy::deposit(strategy_id, account, asset, amount, extra_data);
        wallet_account::distributed_fund(account, asset, amount);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data = funding_account.get_funding_asset(asset);

        asset_data.total_distributed_amount =
            asset_data.total_distributed_amount + (amount as u128);
        funding_account.set_funding_asset(asset, asset_data);

        event::emit(
            DepositToStrategyEvent {
                account,
                asset,
                strategy: strategy_id,
                amount,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun withdraw_from_strategy(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        asset: Object<Metadata>,
        amount: u64,
        gas_fee: u64,
        extra_data: vector<u8>
    ) acquires Config, FundingAccount {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let config = borrow_global<Config>(@moneyfi);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data = funding_account.get_funding_asset(asset);

        let (deposited_amount, withdrawn_amount, fee) =
            strategy::withdraw(strategy_id, account, asset, amount, extra_data);
        assert!(fee <= withdrawn_amount);
        assert!(asset_data.total_distributed_amount >= (deposited_amount as u128));

        let collected_amount = withdrawn_amount - fee;
        let interest_amount = 0;
        let loss_amount = 0;
        if (deposited_amount > collected_amount) {
            loss_amount = deposited_amount - collected_amount;
        } else {
            interest_amount = collected_amount - deposited_amount;
        };
        interest_amount =
            if (interest_amount > gas_fee) {
                interest_amount - gas_fee
            } else { 0 };

        asset_data.total_distributed_amount =
            asset_data.total_distributed_amount - (deposited_amount as u128);
        asset_data.total_amount = asset_data.total_amount + (interest_amount as u128);
        asset_data.total_amount =
            if (asset_data.total_amount > (loss_amount as u128)) {
                asset_data.total_amount - (loss_amount as u128)
            } else { 0 };

        let system_fee = config.calc_system_fee(interest_amount);
        let total_fee = fee + system_fee + gas_fee;
        if (total_fee > 0) {
            let account_signer = wallet_account::get_wallet_account_signer(account);
            primary_fungible_store::transfer(
                &account_signer,
                asset,
                funding_account_addr,
                total_fee
            );
        };

        collected_amount = collected_amount - system_fee;
        if (system_fee > 0) {
            collected_amount = collected_amount - gas_fee;

            let (remaining_fee, referral_fees) =
                config.calc_referral_shares(account, system_fee);
            asset_data.total_fee_amount = asset_data.total_fee_amount + remaining_fee;
            asset_data.pending_fee_amount = asset_data.pending_fee_amount
                + remaining_fee;
            asset_data.add_referral_fees(referral_fees);
        };

        funding_account.set_funding_asset(asset, asset_data);

        wallet_account::collected_fund(
            account,
            asset,
            deposited_amount,
            collected_amount,
            interest_amount,
            system_fee
        );

        event::emit(
            WithdrawFromStrategyEvent {
                account,
                asset,
                strategy: strategy_id,
                amount: collected_amount,
                interest_amount,
                system_fee,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun update_tick(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        extra_data: vector<u8>
    ) {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        strategy::update_tick(strategy_id, account, extra_data);
    }

    public entry fun swap_assets(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        from_asset: Object<Metadata>,
        to_asset: Object<Metadata>,
        from_amount: u64,
        to_amount: u64,
        extra_data: vector<u8>
    ) acquires FundingAccount, Config, LPToken {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let account_addr = object::object_address(&account);
        let config = borrow_global<Config>(@moneyfi);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data_0 = funding_account.get_funding_asset(from_asset);
        let asset_data_1 = funding_account.get_funding_asset(to_asset);
        let asset_config_1 = config.get_asset_config(to_asset);

        let (amount_in, amount_out) =
            strategy::swap(
                strategy_id,
                account,
                from_asset,
                to_asset,
                from_amount,
                to_amount,
                extra_data
            );
        assert!(asset_data_0.total_amount >= (amount_in as u128));

        let lp_amount_1 = asset_config_1.calc_mint_lp_amount(amount_out);
        let lp_amount_0 =
            wallet_account::swap(
                account,
                from_asset,
                to_asset,
                amount_in,
                amount_out,
                lp_amount_1
            );

        asset_data_0.total_amount = asset_data_0.total_amount - (amount_in as u128);
        asset_data_1.total_amount = asset_data_1.total_amount + (amount_out as u128);

        if (lp_amount_0 > lp_amount_1) {
            let burn_amount = lp_amount_0 - lp_amount_1;
            burn_lp(account_addr, burn_amount);
            asset_data_0.total_lp_amount =
                asset_data_0.total_lp_amount - (burn_amount as u128);
        } else if (lp_amount_0 < lp_amount_1) {
            let mint_amount = lp_amount_1 - lp_amount_0;
            mint_lp(account_addr, mint_amount);
            asset_data_1.total_lp_amount =
                asset_data_1.total_lp_amount + (mint_amount as u128);
        };

        funding_account.set_funding_asset(from_asset, asset_data_0);
        funding_account.set_funding_asset(to_asset, asset_data_1);

        event::emit(
            SwapAssetsEvent {
                account,
                strategy: strategy_id,
                from_asset,
                to_asset,
                amount_in,
                amount_out,
                lp_amount_in: lp_amount_0,
                lp_amount_out: lp_amount_1,
                timestamp: now_seconds()
            }
        );
    }

    // -- Views
    #[view]
    public fun get_total_assets(): (vector<address>, vector<u128>) acquires FundingAccount {
        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global<FundingAccount>(funding_account_addr);
        let (keys, values) = ordered_map::to_vec_pair(funding_account.assets);
        let amount_values = vector::map_ref(&values, |v| v.total_amount);

        (keys, amount_values)
    }

    #[view]
    public fun get_supported_assets(): vector<address> acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        ordered_map::keys(&config.supported_assets)
    }

    // -- Public

    public fun get_lp_token(): Object<Metadata> acquires LPToken {
        let lptoken = borrow_global<LPToken>(@moneyfi);

        lptoken.token
    }

    public fun get_funding_account_address(): address {
        storage::get_child_object_address(FUNDING_ACCOUNT_SEED)
    }

    // -- Private

    fun init_funding_account(): Object<FundingAccount> {
        let account_addr = storage::get_child_object_address(FUNDING_ACCOUNT_SEED);
        assert!(!exists<FundingAccount>(account_addr));

        let extend_ref =
            storage::create_child_object_with_phantom_owner(FUNDING_ACCOUNT_SEED);
        let account_addr = object::address_from_extend_ref(&extend_ref);

        let account_signer = object::generate_signer_for_extending(&extend_ref);
        move_to(
            &account_signer, FundingAccount { extend_ref, assets: ordered_map::new() }
        );

        object::address_to_object<FundingAccount>(account_addr)
    }

    fun init_lp_token(sender: &signer) {
        let constructor_ref = &object::create_sticky_object(@moneyfi);
        let lp_address = object::address_from_constructor_ref(constructor_ref);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            string::utf8(LP_TOKEN_NAME),
            string::utf8(LP_TOKEN_SYMBOL),
            LP_TOKEN_DECIMALS,
            string::utf8(b""),
            string::utf8(b"")
        );
        fungible_asset::set_untransferable(constructor_ref);

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let extend_ref = object::generate_extend_ref(constructor_ref);

        move_to(
            sender,
            LPToken {
                token: object::address_to_object(lp_address),
                mint_ref,
                transfer_ref,
                burn_ref,
                extend_ref
            }
        );
    }

    fun upsert_asset(
        self: &mut Config, asset: Object<Metadata>, config: AssetConfig
    ) {
        let addr = object::object_address(&asset);
        ordered_map::upsert(&mut self.supported_assets, addr, config);
    }

    fun get_asset_config(self: &Config, asset: Object<Metadata>): AssetConfig {
        let addr = object::object_address(&asset);
        *ordered_map::borrow(&self.supported_assets, &addr)
    }

    fun can_deposit(self: &Config, asset: Object<Metadata>, amount: u64): bool {
        if (amount == 0) return false;
        if (!self.enable_deposit) return false;

        let addr = object::object_address(&asset);
        if (ordered_map::contains(&self.supported_assets, &addr)) {
            let config = ordered_map::borrow(&self.supported_assets, &addr);

            return config.enabled
                && (config.max_deposit == 0
                    || config.max_deposit >= amount)
                && (config.min_deposit == 0
                    || config.min_deposit <= amount);
        };

        false
    }

    fun can_withdraw(
        self: &Config, asset: Object<Metadata>, amount: u64
    ): bool {
        if (amount == 0) return false;
        if (!self.enable_withdraw) return false;

        let addr = object::object_address(&asset);
        if (ordered_map::contains(&self.supported_assets, &addr)) {
            let config = ordered_map::borrow(&self.supported_assets, &addr);

            return config.enabled
                && (config.max_withdraw == 0
                    || config.max_withdraw >= amount)
                && (config.min_withdraw == 0
                    || config.min_withdraw <= amount);
        };

        false
    }

    fun mint_lp(recipient: address, amount: u64) acquires LPToken {
        let lptoken = borrow_global<LPToken>(@moneyfi);

        let store =
            primary_fungible_store::ensure_primary_store_exists(
                recipient, lptoken.token
            );
        primary_fungible_store::set_frozen_flag(&lptoken.transfer_ref, recipient, true);
        let lp = fungible_asset::mint(&lptoken.mint_ref, amount);
        fungible_asset::deposit_with_ref(&lptoken.transfer_ref, store, lp);
    }

    fun burn_lp(owner: address, amount: u64) acquires LPToken {
        let lptoken = borrow_global<LPToken>(@moneyfi);
        primary_fungible_store::set_frozen_flag(&lptoken.transfer_ref, owner, false);
        primary_fungible_store::burn(&lptoken.burn_ref, owner, amount);
    }

    fun calc_mint_lp_amount(self: &AssetConfig, token_amount: u64): u64 {
        self.lp_exchange_rate * token_amount
    }

    fun calc_system_fee(self: &Config, interest_amount: u64): u64 {
        interest_amount * self.system_fee_percent / 10_000
    }

    /// return (remaining_fee, share_fees)
    fun calc_referral_shares(
        self: &Config, account: Object<WalletAccount>, total_fee: u64
    ): (u64, OrderedMap<address, u64>) {
        let share_fees = ordered_map::new();
        let remaining_fee = total_fee;

        let len = vector::length(&self.referral_percents);
        let referrers = wallet_account::get_referrer_addresses(account, len as u8);
        len = vector::length(&referrers);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&referrers, i);
            let percent = *vector::borrow(&self.referral_percents, i);
            let fee = total_fee * percent / 10_000;
            assert!(remaining_fee > fee);
            remaining_fee = remaining_fee - fee;
            ordered_map::upsert(&mut share_fees, addr, fee);

            i = i + 1;
        };

        (remaining_fee, share_fees)
    }

    fun add_referral_fees(
        self: &FundingAsset, data: OrderedMap<address, u64>
    ) {
        let pending_referral_fees = self.pending_referral_fees;
        ordered_map::for_each(
            data,
            |k, v| {
                let current =
                    if (ordered_map::contains(&self.pending_referral_fees, &k)) {
                        *ordered_map::borrow(&self.pending_referral_fees, &k)
                    } else { 0 };
                v = v + current;
                ordered_map::upsert(&mut pending_referral_fees, k, v);
            }
        );
    }

    fun get_pending_referral_fee(
        self: &FundingAsset, account: Object<WalletAccount>
    ): u64 {
        let addr = object::object_address(&account);
        if (ordered_map::contains(&self.pending_referral_fees, &addr)) {
            *ordered_map::borrow(&self.pending_referral_fees, &addr)
        } else { 0 }
    }

    fun get_funding_asset(
        self: &FundingAccount, asset: Object<Metadata>
    ): FundingAsset {
        let addr = object::object_address(&asset);
        if (ordered_map::contains(&self.assets, &addr)) {
            *ordered_map::borrow(&self.assets, &addr)
        } else {
            FundingAsset {
                total_amount: 0,
                total_lp_amount: 0,
                total_distributed_amount: 0,
                total_fee_amount: 0,
                pending_fee_amount: 0,
                pending_referral_fees: ordered_map::new()
            }
        }
    }

    fun set_funding_asset(
        self: &mut FundingAccount, asset: Object<Metadata>, data: FundingAsset
    ) {
        let addr = object::object_address(&asset);
        ordered_map::upsert(&mut self.assets, addr, data);
    }

    fun withdraw_fee_single_asset(
        asset: Object<Metadata>, amount: u64, to: address
    ) acquires FundingAccount {
        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);

        let asset_data = funding_account.get_funding_asset(asset);
        assert!(asset_data.pending_fee_amount >= amount);

        let account_signer = funding_account.get_funding_account_signer();
        primary_fungible_store::transfer(&account_signer, asset, to, amount);

        asset_data.pending_fee_amount = asset_data.pending_fee_amount - amount;
        funding_account.set_funding_asset(asset, asset_data);
    }

    fun get_funding_account_signer(self: &FundingAccount): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    // -- test only

    #[test_only]
    public fun init_module_for_testing(sender: &signer) {
        init_module(sender)
    }

    #[test_only]
    public fun mint_lp_for_testing(recipient: address, amount: u64) acquires LPToken {
        mint_lp(recipient, amount);
    }
}

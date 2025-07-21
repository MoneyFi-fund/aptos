module moneyfi::vault {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string;
    use std::option;
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        Metadata,
        MintRef,
        TransferRef,
        BurnRef
    };
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp::now_seconds;

    use moneyfi::access_control;
    use moneyfi::wallet_account;
    use moneyfi::storage;

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

    struct FundingAsset has store {
        amount: u64,
        lp_amount: u64,
        total_fee_amount: u64,
        pending_fee_amount: u64
    }

    //  -- events

    #[event]
    struct DepositedEvent has drop, store {
        sender: address,
        wallet_account: Object<wallet_account::WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64,
        timestamp: u64
    }

    #[event]
    struct WithdrawnEvent has drop, store {
        sender: address,
        wallet_account: Object<wallet_account::WalletAccount>,
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
        timestamp: u64
    }

    // -- init
    fun init_module(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(
            !exists<Config>(addr),
            error::already_exists(E_ALREADY_INITIALIZED)
        );

        let funding_account = init_funding_account();

        move_to(
            sender,
            Config {
                enable_deposit: true,
                enable_withdraw: true,
                system_fee_percent: 2500, // 25%
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
        system_fee_percent: u64
    ) acquires Config {
        assert!(system_fee_percent <= 10000);

        access_control::must_be_admin(sender);
        let config = borrow_global_mut<Config>(@moneyfi);

        config.enable_deposit = enable_deposit;
        config.enable_withdraw = enable_withdraw;
        config.system_fee_percent = system_fee_percent;

        event::emit(
            ConfigureEvent {
                enable_deposit,
                enable_withdraw,
                system_fee_percent,
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
        let wallet_id = wallet_account::get_wallet_id_by_address(wallet_addr);

        let asset_config = config.get_asset_config(asset);
        let lp_amount = asset_config.calc_lp_amount(amount);
        let account_addr = object::object_address(&account);

        primary_fungible_store::transfer(sender, asset, account_addr, amount);
        wallet_account::deposit(account, asset, amount, lp_amount);
        mint_lp(wallet_addr, lp_amount);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data = funding_account.get_funding_asset(asset);
        asset_data.lp_amount += lp_amount;
        asset_data.amount += amount;
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

        let balance = primary_fungible_store::balance(account_addr, asset);
        if (amount > balance) {
            amount = balance;
        };

        let config = borrow_global<Config>(@moneyfi);
        assert!(
            config.can_withdraw(asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );

        let wallet_id = wallet_account::get_wallet_id_by_address(wallet_addr);

        let asset_config = config.get_asset_config(asset);
        let lp_amount = asset_config.calc_lp_amount(amount);
        let account_signer = wallet_account::get_wallet_account_signer(account);

        primary_fungible_store::transfer(&account_signer, asset, wallet_addr, amount);
        wallet_account::withdraw(account, asset, amount, lp_amount);
        burn_lp(wallet_addr, lp_amount);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let asset_data = funding_account.get_funding_asset(asset);
        assert!(asset_data.lp_amount >= lp_amount);
        assert!(asset_data.amount >= amount);

        asset_data.lp_amount -= lp_amount;
        asset_data.amount -= amount;
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

        // TODO: emit event
    }

    public entry fun withdraw_all_fee(sender: &signer, to: address) acquires FundingAccount {
        access_control::must_be_admin(sender);

        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);

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
            };
            i = i + 1;
        };

        // TODO: emit event
    }

    // -- Views
    #[view]
    public fun get_total_assets(): (vector<address>, vector<u64>) acquires FundingAccount {
        let funding_account_addr = get_funding_account_address();
        let funding_account = borrow_global_mut<FundingAccount>(funding_account_addr);
        let (keys, values) = ordered_map::to_vec_pair(funding_account.assets);
        let amount_values = vector::map_ref(&values, |v| v.amount);

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

    fun calc_lp_amount(self: &AssetConfig, token_amount: u64): u64 {
        self.lp_exchange_rate * token_amount
    }

    fun get_funding_asset(
        self: &FundingAccount, asset: Object<Metadata>
    ): FundingAsset {
        let addr = object::object_address(&asset);
        if (ordered_map::contains(&self.assets, &addr)) {
            *ordered_map::borrow(&self.assets, &addr)
        } else {
            FundingAsset {
                amount: 0,
                lp_amount: 0,
                total_fee_amount: 0,
                pending_fee_amount: 0
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

        asset_data.pending_fee_amount -= amount;
        funding_account.set_funding_asset(asset, asset_data);
    }

    fun get_funding_account_signer(self: &FundingAccount): signer acquires FundingAccount {
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

module moneyfi::vault {
    use std::signer;
    use std::error;
    use std::vector;
    use std::string;
    use std::option;
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
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
    const VAULT_SEED: vector<u8> = b"vault::VAULT";

    // -- Errors
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_DEPOSIT_NOT_ALLOWED: u64 = 2;
    const E_WITHDRAW_NOT_ALLOWED: u64 = 3;
    const E_ASSET_NOT_SUPPORTED: u64 = 4;
    const E_DEPRECATED: u64 = 5;

    // -- Structs
    struct Config has key {
        enable_deposit: bool,
        enable_withdraw: bool,
        system_fee_percent: u64, // 100 => 1%
        fee_recipient: address,
        // [level_1, level_2, level_3, ...]
        referral_percents: vector<u64>, // 100 => 1%,
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

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Vault has key {
        extend_ref: ExtendRef,
        assets: OrderedMap<address, VaultAsset>
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct StrategyRegistry has key {
        // type => deposit address
        strategies: OrderedMap<TypeInfo, address>
    }

    struct VaultAsset has store {
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
        fee_recipient: address,
        timestamp: u64
    }

    // Deprecated by DepositedToStrategyEvent
    #[event]
    struct DepositToStrategyEvent has drop, store {
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        strategy: u8,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct DepositedToStrategyEvent has drop, store {
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        strategy: TypeInfo,
        amount: u64,
        timestamp: u64
    }

    // Deprecated by WithdrawnFromStrategyEvent
    #[event]
    struct WithdrawFromStrategyEvent has drop, store {
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        strategy: u8,
        amount: u64,
        interest_amount: u64,
        system_fee: u64,
        timestamp: u64
    }

    #[event]
    struct WithdrawnFromStrategyEvent has drop, store {
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        strategy: TypeInfo,
        amount: u64,
        interest_amount: u64,
        system_fee: u64,
        timestamp: u64
    }

    #[event]
    struct RebalanceEvent has drop, store {
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        strategy: u8,
        amount: u64,
        interest_amount: u64,
        system_fee: u64,
        timestamp: u64
    }

    #[event]
    struct RebalanceStrategyEvent has drop, store {
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        strategy: TypeInfo,
        amount: u64,
        interest_amount: u64,
        system_fee: u64,
        timestamp: u64
    }

    #[event]
    struct SwapAssetsEvent has drop, store {
        wallet_id: vector<u8>,
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
        recipient: address,
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

        init_vault();

        let admin_addr =
            if (object::is_object(addr)) {
                object::root_owner(object::address_to_object<ObjectCore>(addr))
            } else { addr };

        move_to(
            sender,
            Config {
                enable_deposit: true,
                enable_withdraw: true,
                system_fee_percent: 2000, // 20%
                fee_recipient: admin_addr,
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
        referral_percents: vector<u64>,
        fee_recipient: address
    ) acquires Config {
        assert!(system_fee_percent <= 10_000);
        wallet_account::validate_referral_percents(referral_percents);

        access_control::must_be_admin(sender);
        // must be fee manager to change fee_recipient, system_fee_percent
        access_control::must_be_fee_manager(sender);
        let config = borrow_global_mut<Config>(@moneyfi);

        config.enable_deposit = enable_deposit;
        config.enable_withdraw = enable_withdraw;
        config.system_fee_percent = system_fee_percent;
        config.referral_percents = referral_percents;
        config.fee_recipient = fee_recipient;

        event::emit(
            ConfigureEvent {
                enable_deposit,
                enable_withdraw,
                system_fee_percent,
                referral_percents,
                fee_recipient,
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

        if (max_deposit > 0) {
            assert!(min_deposit <= max_deposit);
        };
        if (max_withdraw > 0) {
            assert!(min_withdraw <= max_withdraw);
        };

        config.upsert_asset(
            &asset,
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
    ) acquires Config, LPToken, Vault {
        let config = borrow_global<Config>(@moneyfi);
        assert!(
            config.can_deposit(&asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );

        let wallet_addr = signer::address_of(sender);
        let account = wallet_account::get_wallet_account_by_address(wallet_addr);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_data = vault.get_vault_asset_mut(&asset);

        let asset_config = config.get_asset_config(&asset);
        let lp_amount = asset_config.calc_mint_lp_amount(amount);
        let account_addr = object::object_address(&account);

        primary_fungible_store::transfer(sender, asset, account_addr, amount);
        wallet_account::deposit(&account, &asset, amount, lp_amount);
        mint_lp(wallet_addr, lp_amount);

        asset_data.total_lp_amount = asset_data.total_lp_amount + (lp_amount as u128);
        asset_data.total_amount = asset_data.total_amount + (amount as u128);

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
    ) acquires Config, LPToken, Vault {
        let wallet_addr = signer::address_of(sender);
        let account = wallet_account::get_wallet_account_by_address(wallet_addr);
        let account_addr = object::object_address(&account);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let account_signer = vault.get_vault_signer();
        let asset_data = vault.get_vault_asset_mut(&asset);

        // transfer pending referral fee to wallet account first
        let pending_referral_fee = asset_data.get_pending_referral_fee(&account);
        if (pending_referral_fee > 0) {
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
            config.can_withdraw(&asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );

        let account_signer = wallet_account::get_wallet_account_signer(&account);

        primary_fungible_store::transfer(&account_signer, asset, wallet_addr, amount);
        let lp_amount = wallet_account::withdraw(&account, &asset, amount);
        burn_lp(wallet_addr, lp_amount);

        assert!(asset_data.total_lp_amount >= (lp_amount as u128));
        assert!(asset_data.total_amount >= (amount as u128));

        asset_data.total_lp_amount = asset_data.total_lp_amount - (lp_amount as u128);
        asset_data.total_amount = asset_data.total_amount - (amount as u128);

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
        sender: &signer, asset: Object<Metadata>, amount: u64
    ) acquires Config, Vault {
        access_control::must_be_fee_manager(sender);

        let config = borrow_global<Config>(@moneyfi);
        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let account_signer = vault.get_vault_signer();

        let asset_data = vault.get_vault_asset_mut(&asset);
        assert!(asset_data.pending_fee_amount >= amount);

        primary_fungible_store::transfer(
            &account_signer,
            asset,
            config.fee_recipient,
            amount
        );
        asset_data.pending_fee_amount = asset_data.pending_fee_amount - amount;

        event::emit(
            WithdrawFeeEvent {
                asset,
                amount,
                recipient: config.fee_recipient,
                timestamp: now_seconds()
            }
        )
    }

    public entry fun withdraw_all_fee(sender: &signer) acquires Vault, Config {
        access_control::must_be_fee_manager(sender);

        let config = borrow_global<Config>(@moneyfi);
        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let account_signer = vault.get_vault_signer();

        ordered_map::for_each_mut(
            &mut vault.assets,
            |asset_addr, asset_data| {
                let asset_obj = object::address_to_object<Metadata>(*asset_addr);
                let fee_amount = asset_data.pending_fee_amount;

                if (fee_amount > 0) {
                    primary_fungible_store::transfer(
                        &account_signer,
                        asset_obj,
                        config.fee_recipient,
                        fee_amount
                    );
                    asset_data.pending_fee_amount =
                        asset_data.pending_fee_amount - fee_amount;

                    event::emit(
                        WithdrawFeeEvent {
                            asset: asset_obj,
                            recipient: config.fee_recipient,
                            amount: fee_amount,
                            timestamp: now_seconds()
                        }
                    )
                }
            }
        );
    }

    /// Deprecated by deposit_to_strategy_vault
    public entry fun deposit_to_strategy(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<vector<u8>>
    ) acquires Vault {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let amount = strategy::deposit(
            strategy_id,
            &account,
            &asset,
            amount,
            extra_data
        );
        wallet_account::distributed_fund(&account, &asset, amount);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_data = vault.get_vault_asset_mut(&asset);

        asset_data.total_distributed_amount =
            asset_data.total_distributed_amount + (amount as u128);

        event::emit(
            DepositToStrategyEvent {
                wallet_id,
                asset,
                strategy: strategy_id,
                amount,
                timestamp: now_seconds()
            }
        );
    }

    /// Deprecated by withdrawn_from_strategy
    public entry fun withdraw_from_strategy(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        asset: Object<Metadata>,
        amount: u64,
        gas_fee: u64,
        extra_data: vector<vector<u8>>
    ) acquires Config, Vault {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let config = borrow_global<Config>(@moneyfi);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_data = vault.get_vault_asset_mut(&asset);

        let (deposited_amount, withdrawn_amount, fee) =
            strategy::withdraw(
                strategy_id,
                &account,
                &asset,
                amount,
                extra_data
            );
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

        let system_fee = config.calc_system_fee(&account, interest_amount);
        let total_fee = fee + system_fee + gas_fee;
        if (total_fee > 0) {
            let account_signer = wallet_account::get_wallet_account_signer(&account);
            primary_fungible_store::transfer(
                &account_signer, asset, vault_addr, total_fee
            );
        };

        collected_amount = collected_amount - system_fee;
        if (system_fee > 0) {
            collected_amount = collected_amount - gas_fee;

            let (remaining_fee, referral_fees) =
                config.calc_referral_shares(&account, system_fee);
            asset_data.total_fee_amount = asset_data.total_fee_amount + remaining_fee;
            asset_data.pending_fee_amount = asset_data.pending_fee_amount
                + remaining_fee;
            asset_data.add_referral_fees(&referral_fees);
        };

        wallet_account::collected_fund(
            &account,
            &asset,
            deposited_amount,
            collected_amount,
            interest_amount,
            system_fee
        );

        event::emit(
            WithdrawFromStrategyEvent {
                wallet_id,
                asset,
                strategy: strategy_id,
                amount: collected_amount,
                interest_amount,
                system_fee,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun rebalance(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        asset: Object<Metadata>,
        amount: u64,
        gas_fee: u64,
        extra_data: vector<vector<u8>>
    ) acquires Config, Vault {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let config = borrow_global<Config>(@moneyfi);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_data = vault.get_vault_asset_mut(&asset);

        let (deposited_amount, withdrawn_amount, fee) =
            strategy::withdraw(
                strategy_id,
                &account,
                &asset,
                amount,
                extra_data
            );
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

        let system_fee = config.calc_system_fee(&account, interest_amount);
        let total_fee = fee + system_fee + gas_fee;
        if (total_fee > 0) {
            let account_signer = wallet_account::get_wallet_account_signer(&account);
            primary_fungible_store::transfer(
                &account_signer, asset, vault_addr, total_fee
            );
        };

        collected_amount = collected_amount - system_fee;
        if (system_fee > 0) {
            collected_amount = collected_amount - gas_fee;

            let (remaining_fee, referral_fees) =
                config.calc_referral_shares(&account, system_fee);
            asset_data.total_fee_amount = asset_data.total_fee_amount + remaining_fee;
            asset_data.pending_fee_amount = asset_data.pending_fee_amount
                + remaining_fee;
            asset_data.add_referral_fees(&referral_fees);
        };

        wallet_account::collected_fund(
            &account,
            &asset,
            deposited_amount,
            collected_amount,
            interest_amount,
            system_fee
        );

        event::emit(
            RebalanceEvent {
                wallet_id,
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
        _sender: &signer,
        _wallet_id: vector<u8>,
        _strategy_id: u8,
        _extra_data: vector<vector<u8>>
    ) {
        // Deprecated, function retained for upgrade compatibility
        abort(E_DEPRECATED);

        // access_control::must_be_service_account(sender);
        // let account = wallet_account::get_wallet_account(wallet_id);
        // strategy::update_tick(strategy_id, &account, extra_data);
    }

    public entry fun swap_assets(
        sender: &signer,
        wallet_id: vector<u8>,
        strategy_id: u8,
        from_asset: Object<Metadata>,
        to_asset: Object<Metadata>,
        from_amount: u64,
        to_amount: u64,
        extra_data: vector<vector<u8>>
    ) acquires Vault, Config, LPToken {
        access_control::must_be_service_account(sender);
        let account = wallet_account::get_wallet_account(wallet_id);
        let account_addr = wallet_account::get_owner_address(wallet_id);
        let config = borrow_global<Config>(@moneyfi);

        config.ensure_asset_is_supported(&from_asset);
        config.ensure_asset_is_supported(&to_asset);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_config_1 = config.get_asset_config(&to_asset);

        let (amount_in, amount_out) =
            strategy::swap(
                strategy_id,
                &account,
                &from_asset,
                &to_asset,
                from_amount,
                to_amount,
                extra_data
            );

        let lp_amount_1 = asset_config_1.calc_mint_lp_amount(amount_out);
        let lp_amount_0 =
            wallet_account::swap(
                &account,
                &from_asset,
                &to_asset,
                amount_in,
                amount_out,
                lp_amount_1
            );

        if (lp_amount_0 > lp_amount_1) {
            let burn_lp_amount_0 = lp_amount_0 - lp_amount_1;
            burn_lp(account_addr, burn_lp_amount_0);

        } else if (lp_amount_0 < lp_amount_1) {
            let mint_lp_amount_1 = lp_amount_1 - lp_amount_0;
            mint_lp(account_addr, mint_lp_amount_1);
        };

        vault.decrease_asset_amount(&from_asset, amount_in as u128, lp_amount_0 as u128);
        vault.increase_asset_amount(&to_asset, amount_out as u128, lp_amount_1 as u128);

        event::emit(
            SwapAssetsEvent {
                wallet_id,
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

    public entry fun register_strategy<T>(
        sender: &signer, deposit_addr: address
    ) acquires Vault, StrategyRegistry {
        let sender_addr = signer::address_of(sender);
        if (object::is_object(sender_addr)) {
            let owner =
                object::root_owner(object::address_to_object<ObjectCore>(sender_addr));
            assert!(access_control::is_admin(owner));
        } else {
            access_control::must_be_admin(sender);
        };

        let vault_addr = get_vault_address();
        let vault = borrow_global<Vault>(vault_addr);

        if (!exists<StrategyRegistry>(vault_addr)) {
            move_to(
                &vault.get_vault_signer(),
                StrategyRegistry { strategies: ordered_map::new() }
            );
        };

        let registry = borrow_global_mut<StrategyRegistry>(vault_addr);
        let vault_type = type_info::type_of<T>();
        assert!(!registry.strategies.contains(&vault_type));

        registry.strategies.add(vault_type, deposit_addr);
    }

    // -- Views
    #[view]
    public fun get_assets(): (vector<address>, vector<u128>) acquires Vault {
        let vault_addr = get_vault_address();
        let vault = borrow_global<Vault>(vault_addr);

        let keys = vector[];
        let values = vector[];
        ordered_map::for_each_ref(
            &vault.assets,
            |k, v| {
                vector::push_back(&mut keys, *k);
                vector::push_back(&mut values, v.total_amount);
            }
        );

        (keys, values)
    }

    #[view]
    public fun get_asset(asset: Object<Metadata>): (u128, u128, u128) acquires Vault {
        let vault_addr = get_vault_address();
        let vault = borrow_global<Vault>(vault_addr);
        let asset_addr = object::object_address(&asset);
        assert!(ordered_map::contains(&vault.assets, &asset_addr));

        let asset_dat = ordered_map::borrow(&vault.assets, &asset_addr);

        (
            asset_dat.total_amount,
            asset_dat.total_lp_amount,
            asset_dat.total_distributed_amount
        )
    }

    #[view]
    public fun get_fee(asset: Object<Metadata>): (u64, u64) acquires Vault {
        let vault_addr = get_vault_address();
        let vault = borrow_global<Vault>(vault_addr);
        let asset_addr = object::object_address(&asset);
        assert!(ordered_map::contains(&vault.assets, &asset_addr));

        let asset_dat = ordered_map::borrow(&vault.assets, &asset_addr);

        (asset_dat.total_fee_amount, asset_dat.pending_fee_amount)
    }

    #[view]
    public fun get_supported_assets(): vector<address> acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        ordered_map::keys(&config.supported_assets)
    }

    #[view]
    public fun get_strategy_registry(): OrderedMap<TypeInfo, address> acquires StrategyRegistry {
        let vault_addr = get_vault_address();
        let registry = borrow_global<StrategyRegistry>(vault_addr);

        registry.strategies
    }

    // -- Public

    public fun get_lp_token(): Object<Metadata> acquires LPToken {
        let lptoken = borrow_global<LPToken>(@moneyfi);

        lptoken.token
    }

    public fun deposit_to_strategy_vault<T>(
        sender: &signer,
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        amount: u64
    ) acquires Vault, StrategyRegistry {
        let account = &wallet_account::get_wallet_account(wallet_id);
        let account_signer = &wallet_account::get_wallet_account_signer(account);
        let strategy_addr = get_strategy_address<T>();
        assert!(signer::address_of(sender) == strategy_addr);

        primary_fungible_store::transfer(account_signer, asset, strategy_addr, amount);
        wallet_account::distributed_fund(account, &asset, amount);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_data = vault.get_vault_asset_mut(&asset);

        asset_data.total_distributed_amount =
            asset_data.total_distributed_amount + (amount as u128);

        event::emit(
            DepositedToStrategyEvent {
                wallet_id,
                asset,
                strategy: type_info::type_of<T>(),
                amount,
                timestamp: now_seconds()
            }
        );
    }

    public fun withdrawn_from_strategy<T>(
        sender: &signer,
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        deposited_amount: u64,
        withdrawn_amount: u64,
        withdraw_fee: u64,
        gas_fee: u64
    ) acquires Config, Vault, StrategyRegistry {
        let strategy_addr = get_strategy_address<T>();
        assert!(signer::address_of(sender) == strategy_addr);

        let account = wallet_account::get_wallet_account(wallet_id);
        let config = borrow_global<Config>(@moneyfi);

        let vault_addr = get_vault_address();
        let vault = borrow_global_mut<Vault>(vault_addr);
        let asset_data = vault.get_vault_asset_mut(&asset);

        assert!(withdraw_fee <= withdrawn_amount);
        assert!(asset_data.total_distributed_amount >= (deposited_amount as u128));

        let collected_amount = withdrawn_amount - withdraw_fee;
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

        let system_fee = config.calc_system_fee(&account, interest_amount);
        let total_fee = withdraw_fee + system_fee + gas_fee;
        if (total_fee > 0) {
            let account_signer = wallet_account::get_wallet_account_signer(&account);
            primary_fungible_store::transfer(
                &account_signer, asset, vault_addr, total_fee
            );
        };

        collected_amount = collected_amount - system_fee;
        if (system_fee > 0) {
            collected_amount = collected_amount - gas_fee;

            let (remaining_fee, referral_fees) =
                config.calc_referral_shares(&account, system_fee);
            asset_data.total_fee_amount = asset_data.total_fee_amount + remaining_fee;
            asset_data.pending_fee_amount = asset_data.pending_fee_amount
                + remaining_fee;
            asset_data.add_referral_fees(&referral_fees);
        };

        wallet_account::collected_fund(
            &account,
            &asset,
            deposited_amount,
            collected_amount,
            interest_amount,
            system_fee
        );

        event::emit(
            WithdrawnFromStrategyEvent {
                wallet_id,
                asset,
                strategy: type_info::type_of<T>(),
                amount: collected_amount,
                interest_amount,
                system_fee,
                timestamp: now_seconds()
            }
        );
    }

    public fun get_strategy_address<T>(): address acquires StrategyRegistry {
        let vault_addr = get_vault_address();
        let registry = borrow_global<StrategyRegistry>(vault_addr);
        let vault_type = type_info::type_of<T>();
        assert!(registry.strategies.contains(&vault_type));

        *registry.strategies.borrow(&vault_type)
    }

    // -- Private

    fun get_vault_address(): address {
        storage::get_child_object_address(VAULT_SEED)
    }

    fun init_vault() {
        let account_addr = storage::get_child_object_address(VAULT_SEED);
        assert!(!exists<Vault>(account_addr));

        let extend_ref = storage::create_child_object_with_phantom_owner(VAULT_SEED);

        let account_signer = object::generate_signer_for_extending(&extend_ref);
        move_to(&account_signer, Vault { extend_ref, assets: ordered_map::new() });
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
        self: &mut Config, asset: &Object<Metadata>, config: AssetConfig
    ) {
        let addr = object::object_address(asset);
        ordered_map::upsert(&mut self.supported_assets, addr, config);
    }

    fun get_asset_config(self: &Config, asset: &Object<Metadata>): AssetConfig {
        let addr = object::object_address(asset);
        *ordered_map::borrow(&self.supported_assets, &addr)
    }

    fun can_deposit(
        self: &Config, asset: &Object<Metadata>, amount: u64
    ): bool {
        if (amount == 0) return false;
        if (!self.enable_deposit) return false;

        let addr = object::object_address(asset);
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
        self: &Config, asset: &Object<Metadata>, amount: u64
    ): bool {
        if (amount == 0) return false;
        if (!self.enable_withdraw) return false;

        let addr = object::object_address(asset);
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

    fun calc_system_fee(
        self: &Config, account: &Object<WalletAccount>, interest_amount: u64
    ): u64 {
        let percent = self.system_fee_percent;
        let (system_fee_percent, _) = wallet_account::get_fee_config(account);
        if (option::is_some(&system_fee_percent)) {
            percent = *option::borrow(&system_fee_percent);
        };

        interest_amount * percent / 10_000
    }

    /// return (remaining_fee, share_fees)
    fun calc_referral_shares(
        self: &Config, account: &Object<WalletAccount>, total_fee: u64
    ): (u64, OrderedMap<address, u64>) {
        let share_fees = ordered_map::new();
        let remaining_fee = total_fee;

        let percents = self.referral_percents;
        let (_, referral_percents) = wallet_account::get_fee_config(account);
        if (!vector::is_empty(&referral_percents)) {
            percents = referral_percents;
        };

        let len = vector::length(&percents);
        let referrers = wallet_account::get_referrer_addresses(account, len as u8);
        len = vector::length(&referrers);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&referrers, i);
            let percent = *vector::borrow(&percents, i);
            let fee = total_fee * percent / 10_000;
            assert!(remaining_fee > fee);
            remaining_fee = remaining_fee - fee;
            ordered_map::upsert(&mut share_fees, addr, fee);

            i = i + 1;
        };

        (remaining_fee, share_fees)
    }

    fun add_referral_fees(
        self: &VaultAsset, data: &OrderedMap<address, u64>
    ) {
        let pending_referral_fees = self.pending_referral_fees;
        ordered_map::for_each_ref(
            data,
            |k, v| {
                let current =
                    if (ordered_map::contains(&self.pending_referral_fees, k)) {
                        *ordered_map::borrow(&self.pending_referral_fees, k)
                    } else { 0 };
                let v = *v + current;
                ordered_map::upsert(&mut pending_referral_fees, *k, v);
            }
        );
    }

    fun get_pending_referral_fee(
        self: &VaultAsset, account: &Object<WalletAccount>
    ): u64 {
        let addr = object::object_address(account);
        if (ordered_map::contains(&self.pending_referral_fees, &addr)) {
            *ordered_map::borrow(&self.pending_referral_fees, &addr)
        } else { 0 }
    }

    fun get_vault_asset_mut(self: &mut Vault, asset: &Object<Metadata>): &mut VaultAsset {
        let addr = object::object_address(asset);
        if (!ordered_map::contains(&self.assets, &addr)) {
            ordered_map::add(
                &mut self.assets,
                addr,
                VaultAsset {
                    total_amount: 0,
                    total_lp_amount: 0,
                    total_distributed_amount: 0,
                    total_fee_amount: 0,
                    pending_fee_amount: 0,
                    pending_referral_fees: ordered_map::new()
                }
            );
        };

        ordered_map::borrow_mut(&mut self.assets, &addr)
    }

    fun increase_asset_amount(
        self: &mut Vault,
        asset: &Object<Metadata>,
        amount: u128,
        lp_amount: u128
    ) {
        let asset_data = self.get_vault_asset_mut(asset);
        asset_data.total_amount = asset_data.total_amount + amount;
        asset_data.total_lp_amount = asset_data.total_lp_amount + lp_amount;
    }

    fun decrease_asset_amount(
        self: &mut Vault,
        asset: &Object<Metadata>,
        amount: u128,
        lp_amount: u128
    ) {
        let asset_data = self.get_vault_asset_mut(asset);
        assert!(asset_data.total_amount >= amount);
        assert!(asset_data.total_lp_amount >= lp_amount);

        asset_data.total_amount = asset_data.total_amount - amount;
        asset_data.total_lp_amount = asset_data.total_lp_amount - lp_amount;
    }

    fun get_vault_signer(self: &Vault): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    fun ensure_asset_is_supported(
        self: &Config, asset: &Object<Metadata>
    ) {
        let addr = object::object_address(asset);
        assert!(
            ordered_map::contains(&self.supported_assets, &addr),
            error::permission_denied(E_ASSET_NOT_SUPPORTED)
        );

        let config = ordered_map::borrow(&self.supported_assets, &addr);
        assert!(config.enabled, error::permission_denied(E_ASSET_NOT_SUPPORTED));
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

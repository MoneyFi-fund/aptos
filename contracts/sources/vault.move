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

    // -- Constants
    const LP_TOKEN_NAME: vector<u8> = b"MoneyFi USD";
    const LP_TOKEN_SYMBOL: vector<u8> = b"MUSD";
    const LP_TOKEN_DECIMALS: u8 = 18;

    // -- Errors
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_DEPOSIT_NOT_ALLOWED: u64 = 2;
    const E_WITHDRAW_NOT_ALLOWED: u64 = 3;
    const E_ASSET_NOT_SUPPORTED: u64 = 4;

    // -- Structs
    struct Config has key {
        enable_deposit: bool,
        enable_withdraw: bool,
        supported_assets: OrderedMap<address, AssetConfig>
    }

    struct AssetConfig has store, drop {
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
    struct RemoveAssetSupportedEvent has drop, store {
        asset_addr: address,
        timestamp: u64
    }

    // -- init
    fun init_module(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(
            !exists<Config>(addr),
            error::already_exists(E_ALREADY_INITIALIZED)
        );

        move_to(
            sender,
            Config {
                enable_deposit: true,
                enable_withdraw: true,
                supported_assets: ordered_map::new()
            }
        );

        init_lp_token(sender);
    }

    // -- Entries

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
        )
        event::emit(UpsertAssetSupportedEvent{
            asset_addr: object::object_address<Metadata>(&asset),
            in_deposit,
            max_deposit,
            min_withdraw,
            max_withdraw,
            lp_exchange_rate,
            timestamp: now_seconds()
        });
    }

    public entry fun remove_supported_asset(
        sender: &signer, token: Object<Metadata>
    ) {
        access_control::must_be_service_account(sender);
        let config = borrow_global_mut<Config>(@moneyfi);
        let asset_addr = object::object_address<Metadata>(&token)
        if(ordered_map::contains(&config.supported_assets, )) {
            ordered_map::remove(&mut config.supported_assets, asset_addr);
            event::emit(RemoveAssetSupportedEvent {
                asset_addr,
                timestamp: now_seconds()
            })
        };
    }

    public entry fun deposit(
        sender: &signer, wallet_id: vector<u8>, asset: Object<Metadata>, amount: u64
    ) acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        assert!(
            can_deposit(config, asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );

        wallet_account::deposit_to_wallet_account(
            sender,
            wallet_id,
            vector::singleton<Object<Metadata>>(asset),
            vector::singleton<u64>(amount),
            0
        );
    }

    public entry fun withdraw(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: Object<Metadata>,
        amounts: u64
    ) acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        assert!(
            can_deposit(config, asset, amount),
            error::permission_denied(E_DEPOSIT_NOT_ALLOWED)
        );
        wallet_account::withdraw_from_wallet_account_by_user(
            sender,
            wallet_id,
            vector::singleton<Object<Metadata>>(asset),
            vector::singleton<u64>(amount)
        );
    }
    

    // -- Views

    // -- Public

    // -- Private

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

    fun can_deposit(self: &Config, asset: Object<Metadata>, amount: u64): bool {
        if (amount == 0) return false;

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

    // -- test only

    #[test_only]
    public fun init_module_for_testing(sender: &signer) {
        init_module(sender)
    }
}
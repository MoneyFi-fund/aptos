module moneyfi::vault {

    use std::bcs;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::option;

    use aptos_std::table::{Self, Table};
    use aptos_std::string_utils;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    // use aptos_framework::event;
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        Metadata,
        MintRef,
        TransferRef,
        BurnRef
    };
    use aptos_framework::primary_fungible_store;

    use moneyfi::access_control;

    // -- Constants
    const WALLET_ACCOUNT_SEED: vector<u8> = b"WALLET_ACCOUNT";
    const LP_TOKEN_NAME: vector<u8> = b"MoneyFi USD";
    const LP_TOKEN_SYMBOL: vector<u8> = b"MUSD";
    const LP_TOKEN_DECIMALS: u8 = 18;

    // -- Errors
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_PAUSED: u64 = 2;
    const E_WALLET_ACCOUNT_EXISTS: u64 = 3;
    const E_WALLET_ACCOUNT_NOT_EXISTS: u64 = 4;

    // -- Structs
    struct Config has key {
        paused: bool,
        data_object: Object<ObjectCore>,
        data_object_extend_ref: ExtendRef
        // ...
    }

    struct LPToken has key {
        token: Object<Metadata>,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        extend_ref: ExtendRef
    }

    struct WalletAccount has key {
        wallet_id: vector<u8>,
        assets: Table<address, u64>,
        distributed_assets: Table<address, u64>
    }

    // -- init
    fun init_module(sender: &signer) {
        initialize(sender);
    }

    // -- Entries

    public entry fun create_wallet_account(
        sender: &signer, wallet_id: vector<u8>
    ) {
        assert!(access_control::is_operator(sender));
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(!object::object_exists<WalletAccount>(addr), E_WALLET_ACCOUNT_EXISTS);

        let config = borrow_global<Config>(@moneyfi);
        let data_object_signer =
            &object::generate_signer_for_extending(&config.data_object_extend_ref);
        let data_object_addr = object::object_address(&config.data_object);

        let constructor_ref =
            object::create_named_object(
                data_object_signer, get_wallet_account_object_seed(wallet_id)
            );

        move_to(
            data_object_signer,
            WalletAccount {
                wallet_id: wallet_id,
                assets: table::new<address, u64>(),
                distributed_assets: table::new<address, u64>()
            }
        );

        // TODO: dispatch event
    }

    public entry fun deposit<T>(
        sender: &signer, wallet_id: vector<u8>, amount: u64
    ) {
        assert!(amount > 0);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(wallet_account_addr));

        // TODO
    }

    // -- Views

    #[view]
    public fun get_wallet_account_object_address(wallet_id: vector<u8>): address {
        object::create_object_address(
            &@moneyfi, get_wallet_account_object_seed(wallet_id)
        )
    }

    #[view]
    public fun get_wallet_account(wallet_id: vector<u8>): WalletAccount acquires WalletAccount {
        let config = borrow_global<Config>(@moneyfi);
        let addr = get_wallet_account_object_address(wallet_id);
        let acc = borrow_global<WalletAccount>(addr);

        *acc
    }

    // -- Public

    // -- Private

    fun initialize(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(!exists<Config>(addr), E_ALREADY_INITIALIZED);

        // init default config
        let constructor_ref = &object::create_sticky_object(@moneyfi);

        move_to(
            sender,
            Config {
                paused: false,
                data_object: object::object_from_constructor_ref(constructor_ref),
                data_object_extend_ref: object::generate_extend_ref(constructor_ref)
            }
        );

        init_lp_token(sender);
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

    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_{}", WALLET_ACCOUNT_SEED, wallet_id))
    }
}

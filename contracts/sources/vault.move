module moneyfi::vault {
    use std::signer;
    use std::string::{Self};
    use std::option::{Self};
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
    use aptos_framework::auth_data::{Self, AbstractionAuthData};

    use moneyfi::access_control;

    // -- Constants
    const LP_TOKEN_NAME: vector<u8> = b"MoneyFi USD";
    const LP_TOKEN_SYMBOL: vector<u8> = b"MUSD";
    const LP_TOKEN_DECIMALS: u8 = 18;

    // -- Errors
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_PAUSED: u64 = 2;

    struct LPToken has key {
        token: Object<Metadata>,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        extend_ref: ExtendRef
    }

    // -- init
    fun init_module(sender: &signer) {
        initialize(sender);
    }

    // -- Entries


    /// Connect user wallet to a WalletAccount


    // -- Views


    // -- Public

    // -- Private

    fun initialize(sender: &signer) {
        let addr = signer::address_of(sender);
        // assert!(!exists<Config>(addr), E_ALREADY_INITIALIZED);

        // // init default config
        // let constructor_ref = &object::create_sticky_object(@moneyfi);

        // move_to(
        //     sender,
        //     Config {
        //         paused: false,
        //         data_object: object::object_from_constructor_ref(constructor_ref),
        //         data_object_extend_ref: object::generate_extend_ref(constructor_ref)
        //     }
        // );

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
}

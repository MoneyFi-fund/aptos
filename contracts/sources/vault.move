module moneyfi::vault {

    use std::bcs;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use aptos_std::table::{Self, Table};
    use aptos_std::string_utils;
    use aptos_framework::account;
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
    use aptos_framework::auth_data::{Self, AbstractionAuthData};

    use moneyfi::access_control;
    use moneyfi::wallet_account;

    // -- Constants
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
        enable_deposit: bool,
        enable_withdraw: bool,
        supported_assets: OrderedMap<address, AssetConfig>
    }

    struct AssetConfig has store {
        enabled: bool,
        min_deposit: u64,
        max_deposit: u64,
        min_withdraw: u64,
        max_withdraw: u64
    }

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

    public entry fun deposit(
        sender: &signer, token_address: address, amount: u64
    ) {
        assert!(amount > 0);
        let wallet_addr = signer::address_of(sender);
        // let account = wallet_account::get_wallet_account(wallet_addr);

        // let metadata = object::address_to_object<Metadata>(token_address);
        // primary_fungible_store::transfer(
        //     sender,
        //     metadata,
        //     object::object_address(&wallet_account.wallet_account),
        //     amount
        // );

        // TODO: mint LP, dispatch event
    }

    // -- Views

    // -- Public

    // -- Private

    fun initialize(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(!exists<Config>(addr), E_ALREADY_INITIALIZED);

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

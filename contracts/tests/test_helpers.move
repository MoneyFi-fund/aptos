module moneyfi::test_helpers {
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object:: {Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::signer;
    use std::option;
    use std::string;


    public fun create_fungible_asset_and_mint(creator: &signer, name: vector<u8>, amount: u64): FungibleAsset {
        let token_metadata = &object::create_named_object(creator, name);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            token_metadata,
            option::none(),
            string::utf8(name),
            string::utf8(name),
            8,
            string::utf8(b""),
            string::utf8(b""),
        );
        let mint_ref = &fungible_asset::generate_mint_ref(token_metadata);
        fungible_asset::mint(mint_ref, amount)
    }

    public fun create_coin_and_mint<CoinType>(creator: &signer, amount: u64): Coin<CoinType> {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            creator,
            string::utf8(b"Test"),
            string::utf8(b"Test"),
            8,
            true,
        );
        let coin = coin::mint<CoinType>(amount, &mint_cap);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_freeze_cap(freeze_cap);
        coin::destroy_mint_cap(mint_cap);
        coin
    }

    public fun create_fungible_token(sender: &signer): Object<Metadata> {
         let constructor_ref = &object::create_sticky_object(@moneyfi);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            string::utf8(b"Test FA for staking"),
            string::utf8(b"TFAS"),
            8,
            string::utf8(b"url"),
            string::utf8(b"url"),
        );

        primary_fungible_store::mint(
            &fungible_asset::generate_mint_ref(constructor_ref),
            signer::address_of(sender),
            10000000
        );  

        object::object_from_constructor_ref<Metadata>(constructor_ref)
    } 

    public fun balance_of_token(account: address, token: Object<Metadata>): u64 {
        primary_fungible_store::balance(account, token) 
    }
}

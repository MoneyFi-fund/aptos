#[test_only]
module moneyfi::test_helpers {
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object:: {Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::signer;
    use std::option;
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::account;

    use moneyfi::access_control;

    public fun setup_for_test(deployer: &signer,fee_to: address ,aptos_framework: &signer): FungibleAsset {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let deployer_addr = signer::address_of(deployer);
        // Simulate module deployment
        account::create_account_for_test(deployer_addr);
        access_control::initialize(deployer);
        access_control::set_fee_to(deployer, fee_to);

       let fa = create_fungible_asset_and_mint(deployer, b"token1", 10000);
       let metadata = fungible_asset::metadata_from_asset(&fa);
       access_control::add_asset_supported(deployer, object::object_address(&metadata));
       fa
    }

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

    public fun balance_of_token(account: address, token: Object<Metadata>): u64 {
        primary_fungible_store::balance(account, token) 
    }
}

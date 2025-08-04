module moneyfi_v2::test_helpers {
    use std::signer;
    use std::option;
    use std::string;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        Metadata,
        MintRef,
        TransferRef
    };

    use moneyfi_v2::access_control;

    public fun create_fake_USDC(sender: &signer): (Object<Metadata>, MintRef, TransferRef) {
        let constructor_ref = &object::create_named_object(sender, b"FAKE_USDC");
        let usdc_addr = object::address_from_constructor_ref(constructor_ref);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            string::utf8(b"USDC"),
            string::utf8(b"USDC"),
            6,
            string::utf8(b""),
            string::utf8(b"")
        );

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

        (object::address_to_object(usdc_addr), mint_ref, transfer_ref)
    }

    public fun create_fake_USDT(sender: &signer): (Object<Metadata>, MintRef, TransferRef) {
        let constructor_ref = &object::create_named_object(sender, b"FAKE_USDT");
        let usdc_addr = object::address_from_constructor_ref(constructor_ref);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            string::utf8(b"USDT"),
            string::utf8(b"USDT"),
            6,
            string::utf8(b""),
            string::utf8(b"")
        );

        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

        (object::address_to_object(usdc_addr), mint_ref, transfer_ref)
    }
}

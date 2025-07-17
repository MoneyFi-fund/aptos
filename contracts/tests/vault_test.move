module moneyfi::vault_test {
    use std::signer;
    use std::debug;
    use aptos_std::table;
    use std::error;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        Metadata,
        MintRef,
        TransferRef
    };

    use moneyfi::wallet_account;
    use moneyfi::vault;
    use moneyfi::storage;
    use moneyfi::access_control;

    struct TokenController has drop {
        token: Object<Metadata>,
        mint_ref: MintRef,
        transfer_ref: TransferRef
    }

    fun setup(deployer: &signer, wallet1: &signer, wallet2: &signer): (Object<Metadata>) {
        // setup clock
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        // setup modules
        storage::init_module_for_testing(deployer);
        access_control::init_module_for_testing(deployer);
        vault::init_module_for_testing(deployer);

        // setup acccounts
        let deployer_addr = signer::address_of(deployer);
        let wallet1_addr = signer::address_of(wallet1);
        let wallet2_addr = signer::address_of(wallet2);
        account::create_account_for_test(deployer_addr);
        account::create_account_for_test(wallet1_addr);
        account::create_account_for_test(wallet2_addr);

        access_control::upsert_account(deployer, deployer_addr, vector[1, 3, 4]);

        // setup asset
        let usdc = create_fake_USDC(deployer);
        vault::upsert_supported_asset(deployer, usdc.token, true, 0, 0, 0, 0, 1000);

        let init_amount = 1_000_000_000; // 1000 USDC
        primary_fungible_store::mint(&usdc.mint_ref, wallet1_addr, init_amount);
        primary_fungible_store::mint(&usdc.mint_ref, wallet2_addr, init_amount);

        usdc.token
    }

    fun create_fake_USDC(sender: &signer): TokenController {
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

        TokenController {
            token: object::address_to_object(usdc_addr),
            mint_ref,
            transfer_ref
        }
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_deposit(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ): (Object<Metadata>, u64) {
        let (usdc) = setup(deployer, wallet1, wallet2);

        let wallet1_addr = signer::address_of(wallet1);
        wallet_account::create_wallet_account_for_testing(wallet1, b"wallet1");

        let acc = wallet_account::get_wallet_account_by_address(wallet1_addr);
        let acc_addr = object::object_address(&acc);

        let balance_before = primary_fungible_store::balance(wallet1_addr, usdc);

        let deposit_amount = 10_000;
        vault::deposit(wallet1, usdc, deposit_amount);

        let balance_after = primary_fungible_store::balance(wallet1_addr, usdc);
        assert!(
            balance_after + deposit_amount == balance_before
        );

        let acc_balance = primary_fungible_store::balance(acc_addr, usdc);
        debug::print(&acc_balance);
        assert!(acc_balance == deposit_amount);

        let lp_token = vault::get_lp_token();
        let lp_balance = primary_fungible_store::balance(wallet1_addr, lp_token);
        assert!(lp_balance == deposit_amount * 1000);

        let wallet2_addr = signer::address_of(wallet2);
        let acc_signer =
            wallet_account::get_wallet_account_signer_for_owner(wallet1, b"wallet1");
        primary_fungible_store::transfer(&acc_signer, usdc, wallet2_addr, 1000);

        let balance = primary_fungible_store::balance(acc_addr, usdc);
        debug::print(&balance);

        assert!(balance + 1000 == acc_balance);

        (usdc, deposit_amount)
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    #[expected_failure]
    fun test_deployer_transfer_wallet_account_asset(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        let (usdc, _) = test_deposit(deployer, wallet1, wallet2);

        let wallet1_addr = signer::address_of(wallet1);
        let acc = wallet_account::get_wallet_account_by_address(wallet1_addr);
        let acc_addr = object::object_address(&acc);

        let wallet2_addr = signer::address_of(wallet2);
        let wallet2_store =
            primary_fungible_store::ensure_primary_store_exists(wallet2_addr, usdc);
        let acc_store =
            primary_fungible_store::ensure_primary_store_exists(acc_addr, usdc);
        fungible_asset::transfer(deployer, acc_store, wallet2_store, 1000);
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    #[expected_failure]
    fun test_lp_should_not_transferable(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        test_deposit(deployer, wallet1, wallet2);

        let wallet1_addr = signer::address_of(wallet1);
        let wallet2_addr = signer::address_of(wallet2);

        vault::mint_lp_for_testing(wallet1_addr, 1000);
        let lptoken = vault::get_lp_token();

        primary_fungible_store::transfer(wallet1, lptoken, wallet2_addr, 100);
        let balance = primary_fungible_store::balance(wallet1_addr, lptoken);
        debug::print(&balance);
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_withdraw(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        let (usdc, deposit_amount) = test_deposit(deployer, wallet1, wallet2);
        let wallet1_addr = signer::address_of(wallet1);
        let acc = wallet_account::get_wallet_account_by_address(wallet1_addr);
        let acc_addr = object::object_address(&acc);

        let balance_before = primary_fungible_store::balance(wallet1_addr, usdc);
        let acc_balance_before = primary_fungible_store::balance(acc_addr, usdc);
        let withdraw_amount = 1000;
        vault::withdraw(wallet1, usdc, withdraw_amount);
        let balance_after = primary_fungible_store::balance(wallet1_addr, usdc);

        assert!(
            balance_before == balance_after - withdraw_amount
        );

        let acc_balance_after = primary_fungible_store::balance(acc_addr, usdc);
        assert!(
            acc_balance_after == acc_balance_before - withdraw_amount
        );

        let lp_token = vault::get_lp_token();
        let lp_balance = primary_fungible_store::balance(wallet1_addr, lp_token);
        assert!(
            lp_balance == (deposit_amount - withdraw_amount) * 1000
        );
    }
}

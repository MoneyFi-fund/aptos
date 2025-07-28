module moneyfi::wallet_account_test {
    use std::signer;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use std::vector;
    use aptos_framework::timestamp::{Self};

    use moneyfi::storage;
    use moneyfi::access_control;
    use moneyfi::test_helpers;
    use moneyfi::wallet_account::{Self, WalletAccount, WalletAccountObject};

    // Test strategy data operations
    struct TestStrategy has store, drop, copy {
        value: u64
    }

    fun setup(deployer: &signer, wallet1: &signer, wallet2: &signer): (Object<Metadata>) {
        // setup clock
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        // setup modules
        storage::init_module_for_testing(deployer);
        access_control::init_module_for_testing(deployer);

        // setup acccounts
        let deployer_addr = signer::address_of(deployer);
        let wallet1_addr = signer::address_of(wallet1);
        let wallet2_addr = signer::address_of(wallet2);
        account::create_account_for_test(deployer_addr);
        account::create_account_for_test(wallet1_addr);
        account::create_account_for_test(wallet2_addr);

        access_control::upsert_account(deployer, deployer_addr, vector[1, 3]);

        // setup asset
        let (token, _, _) = test_helpers::create_fake_USDC(deployer);

        token
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_register(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        setup(deployer, wallet1, wallet2);

        let wallet1_addr = signer::address_of(wallet1);

        // register
        wallet_account::register(wallet1, deployer, b"wallet1", vector[]);
        let account1 = wallet_account::get_wallet_account(b"wallet1");
        let account2 = wallet_account::get_wallet_account_by_address(wallet1_addr);
        assert!(account1 == account2);
    }
}

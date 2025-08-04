module moneyfi_v2::wallet_account_test {
    use std::signer;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use std::vector;
    use aptos_framework::timestamp::{Self};

    use moneyfi_v2::storage;
    use moneyfi_v2::access_control;
    use moneyfi_v2::test_helpers;
    use moneyfi_v2::wallet_account::{Self, WalletAccount, WalletAccountObject};

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

    #[test(deployer = @moneyfi_v2, wallet1 = @0x111, wallet2 = @0x222)]
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

    #[test(
        deployer = @moneyfi_v2, w1 = @0x111, w2 = @0x222, w3 = @0x333
    )]
    fun test_get_referrer_addresses(
        deployer: &signer,
        w1: &signer,
        w2: &signer,
        w3: &signer
    ) {
        storage::init_module_for_testing(deployer);

        let a1 = wallet_account::create_wallet_account_for_test(w1, b"w1", 0, vector[]);
        let referrers = wallet_account::get_referrer_addresses(&a1, 2);
        assert!(referrers == vector[]);

        let a2 = wallet_account::create_wallet_account_for_test(w2, b"w2", 0, b"w1");
        let a3 = wallet_account::create_wallet_account_for_test(w3, b"w3", 0, b"w2");

        let referrers = wallet_account::get_referrer_addresses(&a2, 3);
        assert!(
            referrers
                == vector[wallet_account::get_wallet_account_object_address(b"w1")]
        );

        let referrers = wallet_account::get_referrer_addresses(&a3, 3);
        assert!(
            referrers
                == vector[
                    wallet_account::get_wallet_account_object_address(b"w2"),
                    wallet_account::get_wallet_account_object_address(b"w1")
                ]
        );

        let referrers = wallet_account::get_referrer_addresses(&a3, 1);
        assert!(
            referrers
                == vector[wallet_account::get_wallet_account_object_address(b"w2")]
        );
    }

    #[test(deployer = @moneyfi_v2, w1 = @0x111)]
    fun test_strategy_data(deployer: &signer, w1: &signer) {
        storage::init_module_for_testing(deployer);
        let a1 = wallet_account::create_wallet_account_for_test(w1, b"w1", 0, vector[]);

        wallet_account::set_strategy_data(&a1, TestStrategy { value: 123 });
        let data = wallet_account::get_strategy_data<TestStrategy>(&a1);
        assert!(data.value == 123);

        wallet_account::set_strategy_data(&a1, TestStrategy { value: 456 });
        data = wallet_account::get_strategy_data<TestStrategy>(&a1);
        assert!(data.value == 456);
    }
}

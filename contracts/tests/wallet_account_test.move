module moneyfi::wallet_account_test {
    use std::signer;
    use std::bcs;
    use std::vector;
    use std::debug;

    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
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

    fun deposit(
        depositor:  &signer, 
        asset: Object<Metadata>, 
        amount: u64, 
        lp_amount: u64
    ) {
        let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(depositor));
        wallet_account::deposit(wallet1_account,asset, amount, lp_amount); 
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_register_should_right(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        setup(deployer, wallet1, wallet2);

        let wallet1_addr = signer::address_of(wallet1);

        // register
        wallet_account::register(wallet1, deployer, b"wallet1", vector[]);
        let account1 = wallet_account::get_wallet_account(b"wallet1");
        let account2 = wallet_account::get_wallet_account_by_address(wallet1_addr);
        assert!(account1 == account2);

        wallet_account::has_wallet_account( b"wallet1");
        let wallet_id_actual = wallet_account::get_wallet_id_by_address(signer::address_of(wallet1));
        assert!(wallet_id_actual == b"wallet1");
    }
    
    #[test(
        deployer = @moneyfi, w1 = @0x111, w2 = @0x222, w3 = @0x333
    )]
    fun test_get_referrer_addresses(
        deployer: &signer,
        w1: &signer,
        w2: &signer,
        w3: &signer
    ) {
        storage::init_module_for_testing(deployer);

        let a1 = wallet_account::create_wallet_account_for_test(w1, b"w1", 0, vector[]);
        let referrers = wallet_account::get_referrer_addresses(a1, 2);
        assert!(referrers == vector[]);

        let a2 = wallet_account::create_wallet_account_for_test(w2, b"w2", 0, b"w1");
        let a3 = wallet_account::create_wallet_account_for_test(w3, b"w3", 0, b"w2");

        let referrers = wallet_account::get_referrer_addresses(a2, 3);
        assert!(
            referrers
                == vector[wallet_account::get_wallet_account_object_address(b"w1")]
        );

        let referrers = wallet_account::get_referrer_addresses(a3, 3);
        assert!(
            referrers
                == vector[
                    wallet_account::get_wallet_account_object_address(b"w2"),
                    wallet_account::get_wallet_account_object_address(b"w1")
                ]
        );

        let referrers = wallet_account::get_referrer_addresses(a3, 1);
        assert!(
            referrers
                == vector[wallet_account::get_wallet_account_object_address(b"w2")]
        );
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    #[expected_failure(abort_code = 0x80001, location = moneyfi::wallet_account)]
    fun test_register_should_revert_E_WALLET_ACCOUNT_EXISTS(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        setup(deployer, wallet1, wallet2);

        /// register
        wallet_account::register(wallet1, deployer,  b"wallet1", vector[]);

        // should revert
        wallet_account::register(wallet1, deployer,  b"wallet1", vector[]);
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_deposit_should_right(deployer: &signer, wallet1: &signer, wallet2: &signer) {
        let fake_USDC = setup(deployer, wallet1, wallet2);

        let wallet1_id =  b"wallet1"; 
        wallet_account::register(wallet1, deployer, wallet1_id, vector[]);

        let deposit_amount = 10000; 
        let lp_amount = 10000; 
        deposit(wallet1, fake_USDC, deposit_amount, lp_amount);
        // wal  let_account::deposit(wallet1_account,fake_USDC, deposit_amount, lp_amount); 
        // let ( current_amount, deposited_amount, lp_amount, swap_out_amount, swap_in_amount, distributed_amount, withdrawn_amount, interest_amount, interest_share_amount, rewards ) = wallet_account::get_wallet_account_assets_detail_for_test(
        //     wallet1_id, fake_USDC
        // );

        let ( current_amount, deposited_amount, lp_amount, _, _, _, _, _, _, _ ) = wallet_account::get_wallet_account_assets_detail_for_test(
            wallet1_id, fake_USDC
        );

        assert!(deposited_amount == deposit_amount); 
        assert!(current_amount == deposited_amount); 
        assert!(lp_amount == lp_amount); 
    }

    // Todo: Check fomular of LP value 
    // #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    // fun test_withdraw_should_right(deployer: &signer, wallet1: &signer, wallet2: &signer) {
    //     let fake_USDC = setup(deployer, wallet1, wallet2);
    //     let wallet1_id =  b"wallet1"; 
    //     wallet_account::register(wallet1, deployer, wallet1_id, vector[]);
    //     let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(wallet1));

    //     let deposit_amount = 10000; 
    //     let lp_amount = 10000; 
    //     wallet_account::deposit(wallet1_account,fake_USDC, deposit_amount, lp_amount); 
    
    //     // withdralet 
    //     wallet_account::withdraw(wallet1_account,fake_USDC, deposit_amount); 

    //     let ( current_amount, deposited_amount, lp_amount, swap_out_amount, swap_in_amount, distributed_amount, withdrawn_amount, interest_amount, interest_share_amount, rewards ) = wallet_account::get_wallet_account_assets_detail_for_test(
    //         wallet1_id, fake_USDC
    //     );

    //     assert!(deposited_amount == deposit_amount); 
    //     assert!(current_amount == deposited_amount); 
    //     assert!(lp_amount == lp_amount); 
    // }
    
    // Todo: test function "swap"

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_distributed_fund_should_right(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        let fake_USDC = setup(deployer, wallet1, wallet2);

        let wallet1_id =  b"wallet1"; 
        wallet_account::register(wallet1, deployer, wallet1_id, vector[]);

        let deposit_amount = 20000; 
        let lp_amount = 20000; 
        deposit(wallet1, fake_USDC, deposit_amount, lp_amount);


        let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(wallet1));
        let distributed_amount = 10000;
        wallet_account::distributed_fund(
            wallet1_account, 
            fake_USDC, 
            distributed_amount, // distributed amount
        );


        let ( current_amount, deposited_amount, _, _, _, distributed_amount, _, _, _, _ ) = wallet_account::get_wallet_account_assets_detail_for_test(
            wallet1_id, fake_USDC
        );

        assert!(current_amount == deposit_amount - distributed_amount);
        assert!(distributed_amount == distributed_amount);
        assert!(deposited_amount == deposit_amount);
    }

     #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
     #[expected_failure(abort_code = 0x7, location = moneyfi::wallet_account)]
    fun test_distributed_fund_should_revert_E_INVALID_ARGUMENT(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        let fake_USDC = setup(deployer, wallet1, wallet2);

        let wallet1_id =  b"wallet1"; 
        wallet_account::register(wallet1, deployer, wallet1_id, vector[]);

        let deposit_amount = 20000; 
        let lp_amount = 20000; 
        deposit(wallet1, fake_USDC, deposit_amount, lp_amount);


        let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(wallet1));
        let distributed_amount = deposit_amount + 1;
        wallet_account::distributed_fund(
            wallet1_account, 
            fake_USDC, 
            distributed_amount, // distributed amount
        );
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_collected_fund_should_right(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        let fake_USDC = setup(deployer, wallet1, wallet2);

        let wallet1_id =  b"wallet1"; 
        wallet_account::register(wallet1, deployer, wallet1_id, vector[]);
        let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(wallet1));

        let deposit_amount = 20000; 
        let lp_amount = 20000; 
        deposit(wallet1, fake_USDC, deposit_amount, lp_amount);


        let distributed_amount = 10000;
        wallet_account::distributed_fund(
            wallet1_account, 
            fake_USDC, 
            distributed_amount, // distributed amount
        );

        let collected_amount = 5000; 
        let interest_amount = 1000; 
        let interest_share_amount = 200; 

        wallet_account::collected_fund(
            wallet1_account, 
            fake_USDC, 
            distributed_amount, 
            collected_amount, 
            interest_amount, 
            interest_share_amount
        );

        let (current_amount_res,_, _, _, _, distributed_amount_result, _, interested_amount_res, interested_share_amount_res, _ ) = wallet_account::get_wallet_account_assets_detail_for_test(
            wallet1_id, fake_USDC
        );

        assert!(distributed_amount_result == 0);
        assert!(current_amount_res == deposit_amount - distributed_amount + collected_amount);
        assert!(interested_amount_res == interest_amount);
        assert!(interested_share_amount_res == interest_share_amount);
    }

    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    #[expected_failure(abort_code = 0x7, location = moneyfi::wallet_account)]
    fun test_collected_fund_should_revert_E_INVALID_ARGUMENT(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        let fake_USDC = setup(deployer, wallet1, wallet2);

        let wallet1_id =  b"wallet1"; 
        wallet_account::register(wallet1, deployer, wallet1_id, vector[]);
        let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(wallet1));

        let deposit_amount = 20000; 
        let lp_amount = 20000; 
        deposit(wallet1, fake_USDC, deposit_amount, lp_amount);


        let distributed_amount = 10000;
        wallet_account::distributed_fund(
            wallet1_account, 
            fake_USDC, 
            distributed_amount, // distributed amount
        );

        let collected_amount = 5000; 
        let interest_amount = 1000; 
        let interest_share_amount = 200; 

        wallet_account::collected_fund(
            wallet1_account, 
            fake_USDC, 
            distributed_amount + 1, 
            collected_amount, 
            interest_amount, 
            interest_share_amount
        );
    }


    #[test(deployer = @moneyfi, wallet1 = @0x111, wallet2 = @0x222)]
    fun test_set_strategy_data_should_right(
        deployer: &signer, wallet1: &signer, wallet2: &signer
    ) {
        setup(deployer, wallet1, wallet2);

        let wallet1_id =  b"wallet1"; 
        wallet_account::register(wallet1, deployer, wallet1_id, vector[]);
        let wallet1_account = wallet_account::get_wallet_account_by_address(signer::address_of(wallet1));

        wallet_account::set_strategy_data<TestStrategy>(
                wallet1_account, TestStrategy {
                    value: 1
                }
        );

        wallet_account::exists_strategy_data<TestStrategy>(wallet1_account); 
    }

    
}
      


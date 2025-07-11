#[test_only]
module moneyfi::access_control_test {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use moneyfi::access_control;
    use moneyfi::test_helpers; 
    use std::vector;
    use aptos_framework::timestamp::{Self};

    fun set_up(deployer: &signer, aptos_framework: &signer) {
        let deployer_addr = signer::address_of(deployer);

        // Simulate module deployment
        account::create_account_for_test(deployer_addr);
        access_control::initialize(deployer);

       timestamp::set_time_has_started_for_testing(aptos_framework);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_set_role_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        access_control::must_be_admin(deployer);

        // Deployer assigns roles
        access_control::set_role(deployer, user1_addr, 2);
        access_control::must_be_operator(user1);

        // Update role
        access_control::set_role(deployer, user1_addr, 1);
        access_control::must_be_admin(user1);

        let vector_user_roles = access_control::get_accounts(); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 3)]
    fun test_set_role_should_revert_E_INVALID_ROLE(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
       let user_addr = signer::address_of(user1);

        access_control::set_role(deployer, user_addr, 10);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_set_role_should_E_NOT_AUTHORIZED(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        let user_addr = signer::address_of(user1);

        access_control::set_role(user1, user_addr, 1);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_claim_fees_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        
        let user_addr = signer::address_of(user1);
        let data_object_signer = access_control::get_object_data_signer(); 
        let token_1 = test_helpers::create_fungible_asset_and_mint(deployer, b"TT", 100000);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        
        primary_fungible_store::deposit(signer::address_of(&data_object_signer), token_1); 

        let fee_to = access_control::get_fee_to(); 

        let preFeeToBl = primary_fungible_store::balance(fee_to,fa_metadata);
        access_control::claim_fees(deployer,fa_metadata , 100000); 
        let posFeeToBl = primary_fungible_store::balance(fee_to,fa_metadata);
        assert!(posFeeToBl > preFeeToBl, 100);
    }  

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_claim_fees_should_revert_E_NOT_AUTHORIZED(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
     
        let user_addr = signer::address_of(user1);

        // deposit fa to data object signer 
        let data_object_signer = access_control::get_object_data_signer(); 
        let token_1 = test_helpers::create_fungible_asset_and_mint(deployer, b"TT", 100000);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        
        primary_fungible_store::deposit(signer::address_of(&data_object_signer), token_1); 

        let fee_to = access_control::get_fee_to(); 

        access_control::claim_fees(user1,fa_metadata , 100000); 
    }  

    #[test(deployer = @moneyfi, user1 = @0x2, user3 = @0x3, aptos_framework = @0x1)]
    fun test_set_fee_to_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer, user3: address) {
        set_up(deployer, aptos_framework); 
        
        let user_addr = signer::address_of(user1);

        access_control::set_fee_to(deployer, user3); 
        let pos_fee_to = access_control::get_fee_to(); 

        assert!(pos_fee_to == user3);
    }   

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_set_fee_to_should_revert_E_NOT_AUTHORIZED(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user_addr = signer::address_of(user1);

        access_control::set_fee_to(user1, signer::address_of(user1)); 
    }   

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_revoke_role_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        let user1_addr = signer::address_of(user1);

        access_control::must_be_admin(deployer);

        // Deployer assigns roles
        access_control::set_role(deployer, user1_addr, 2);
        access_control::must_be_operator(user1);
        
        // Revoke operator 
        access_control::revoke_role(deployer, signer::address_of(user1), 2); 
        access_control::must_be_operator(user1);

        // Revoke operator 
        access_control::revoke_role(deployer, signer::address_of(deployer), 1); 
        access_control::must_be_admin(user1);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_revoke_role_should_revert_E_NOT_AUTHORIZED(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        
        let user1_addr = signer::address_of(user1);

        // Revoke operator 
        access_control::revoke_role(user1, signer::address_of(user1), 2); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_revoke_all_roles_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        
        let user1_addr = signer::address_of(user1);

        access_control::set_role(deployer, user1_addr, 1);
        access_control::set_role(deployer, user1_addr, 2);
        access_control::set_role(deployer, user1_addr, 3);

        // Revoke operator 
        access_control::revoke_all_roles(user1, signer::address_of(user1)); 
        access_control::must_be_admin(user1);
        access_control::must_be_delegator(user1);
        access_control::must_be_operator(user1);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_add_asset_supported_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        let stable_coin_metadata = @0x567; 
        access_control::add_asset_supported(deployer, stable_coin_metadata); 

        let vector_stablecoin_metadata = access_control::get_asset_supported(); 

        assert!(vector::contains(&vector_stablecoin_metadata, &stable_coin_metadata)); 
    }
    
    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_remove_asset_supported_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        
        let user1_addr = signer::address_of(user1);

        let stable_coin_metadata = @0x567; 
        access_control::add_asset_supported(deployer, stable_coin_metadata); 

        access_control::remove_asset_supported(deployer, stable_coin_metadata);
        let vector_stablecoin_metadata = access_control::get_asset_supported(); 
        assert!(!vector::contains(&vector_stablecoin_metadata, &stable_coin_metadata)); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_set_protocol_fee_rate_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 
        
        let user1_addr = signer::address_of(user1);

        let rate = 100; 

        access_control::set_protocol_fee_rate(deployer, rate); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_set_referral_fee_rate_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        let rate = 100; 

        access_control::set_referral_fee_rate(deployer, rate); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_must_be_admin(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        access_control::set_role(deployer, user1_addr, 1); 

        access_control::must_be_admin(user1); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_must_be_operator(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        access_control::set_role(deployer, user1_addr, 2); 

        access_control::must_be_operator(user1); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_must_be_delegator(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        access_control::set_role(deployer, user1_addr, 3); 

        access_control::must_be_delegator(user1); 
    }

    #[test(deployer = @moneyfi, user1 = @0x2, aptos_framework = @0x1)]
    fun test_add_system_fee_should_right(deployer: &signer, user1: &signer, aptos_framework: &signer) {
        set_up(deployer, aptos_framework); 

        let user1_addr = signer::address_of(user1);

        let server_signer = access_control::get_object_data_signer();
        
        let stable_coin_addr = @0x567; 
        let fee_amount = 100; 

        
        access_control::add_asset_supported(deployer, stable_coin_addr); 

        access_control::add_withdraw_fee(
                &server_signer,
                stable_coin_addr,
                fee_amount
        );
        
           access_control::add_rebalance_fee(
                &server_signer,
                stable_coin_addr,
                fee_amount
        );
        

        access_control::add_distribute_fee(
                &server_signer,
                stable_coin_addr,
                fee_amount
        );
        

        access_control::add_referral_fee(
                &server_signer,
                stable_coin_addr,
                fee_amount
        );


        access_control::add_protocol_fee(
                &server_signer,
                stable_coin_addr,
                fee_amount
        );

        let (distribute_fee, withdraw_fee, rebalance_fee, referral_fee,pending_referral_fee, protocol_fee, pending_protocol_fee)  = access_control::get_system_fee(stable_coin_addr); 


        assert!(distribute_fee == fee_amount);
        assert!(withdraw_fee == fee_amount);
        assert!(rebalance_fee == fee_amount);
        assert!(referral_fee == fee_amount);
        assert!(pending_referral_fee == fee_amount);
        assert!(protocol_fee == fee_amount);
        assert!(pending_protocol_fee == fee_amount);

        // Test get_pending_referral_fee
        let (vector_asset, vector_fee) = access_control::get_pending_referral_fee(); 
        assert!(*vector::borrow(&vector_asset, 0) == stable_coin_addr); 
        assert!(*vector::borrow(&vector_fee, 0) == fee_amount); 

         // Test get_pending_protocol_fee
        let (vector_asset, vector_fee) = access_control::get_pending_protocol_fee(); 
        assert!(*vector::borrow(&vector_asset, 0) == stable_coin_addr); 
        assert!(*vector::borrow(&vector_fee, 0) == fee_amount); 
    }
}




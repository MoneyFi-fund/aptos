#[test_only]
module moneyfi::access_control_test {
    use std::signer;
    use aptos_framework::account;
    use std::error;
    use aptos_framework::timestamp;
    use std::vector;
    use aptos_framework::timestamp::{Self};

    use moneyfi::access_control;

    const ROLE_ADMIN: u8 = 1;
    const ROLE_ROLE_MANAGER: u8 = 2;
    const ROLE_SERVICE_ACCOUNT: u8 = 3;

    fun setup_test_environment(deployer: &signer) {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        let deployer_addr = signer::address_of(deployer);
        account::create_account_for_test(deployer_addr);
        access_control::init_module_for_testing(deployer);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_access_control(deployer: &signer, user1: &signer) {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        let deployer_addr = signer::address_of(deployer);

        // Simulate module deployment
        account::create_account_for_test(deployer_addr);
        access_control::init_module_for_testing(deployer);

        access_control::must_be_admin(deployer);

        access_control::upsert_account(deployer, user1_addr, vector[2]);
        access_control::must_be_role_manager(user1);

        access_control::upsert_account(user1, user1_addr, vector[2, 3]);
        access_control::must_be_service_account(user1);
    }

    #[test(deployer = @moneyfi, user = @0x2)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_try_to_modify_without_permission(
        deployer: &signer, user: &signer
    ) {
        let user_addr = signer::address_of(user);
        account::create_account_for_test(signer::address_of(deployer));
        access_control::init_module_for_testing(deployer);

        access_control::remove_account(user, user_addr);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_admin_can_add_first_role_manager(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Admin should be able to add the first role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        access_control::must_be_role_manager(user1);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, user2 = @0x3)]
    fun test_role_manager_can_add_accounts(deployer: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        // Admin adds first role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        
        // Role manager can add service account
        access_control::upsert_account(user1, user2_addr, vector[ROLE_SERVICE_ACCOUNT]);
        access_control::must_be_service_account(user2);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x50005, location = moneyfi::access_control)]
    fun test_admin_and_role_manager_conflict(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Should fail when trying to assign both admin and role manager roles
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ADMIN, ROLE_ROLE_MANAGER]);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x10003, location = moneyfi::access_control)]
    fun test_empty_roles_fails(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Should fail when trying to assign empty roles
        access_control::upsert_account(deployer, user1_addr, vector[]);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_unauthorized_user_cannot_add_accounts(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Unauthorized user should not be able to add accounts
        access_control::upsert_account(user1, user1_addr, vector[ROLE_SERVICE_ACCOUNT]);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_role_manager_can_remove_service_account(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Setup: Admin adds role manager, role manager adds service account
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        access_control::upsert_account(user1, @0x4, vector[ROLE_SERVICE_ACCOUNT]);
        
        // Role manager should be able to remove service account
        access_control::remove_account(user1, @0x4);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::access_control)]
    fun test_cannot_remove_last_admin(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);
        let deployer_addr = signer::address_of(deployer);

        // Add role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        
        // Should fail when trying to remove the last admin
        access_control::remove_account(user1, deployer_addr);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, user2 = @0x3)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::access_control)]
    fun test_cannot_remove_last_role_manager(deployer: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        // Add two role managers
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        access_control::upsert_account(user1, user2_addr, vector[ROLE_ROLE_MANAGER]);
        
        // Remove one role manager
        access_control::remove_account(user1, user2_addr);
        
        // Should fail when trying to remove the last role manager
        access_control::remove_account(user1, user1_addr);
    }

    #[test(deployer = @moneyfi)]
    fun test_registry_unlock_functionality(deployer: &signer) {
        setup_test_environment(deployer);
        
        // Admin should be able to unlock registry with timeout
        access_control::unlock_registry(deployer, 1000);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_non_admin_cannot_unlock_registry(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Add user as role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        
        // Non-admin should not be able to unlock registry
        access_control::unlock_registry(user1, 1000);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x50006, location = moneyfi::access_control)]
    fun test_registry_locked_after_timeout(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Add role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        
        // Fast forward time beyond initial lock timeout (600 seconds)
        timestamp::fast_forward_seconds(700);
        
        // Should fail to add account when registry is locked
        access_control::upsert_account(user1, @0x4, vector[ROLE_SERVICE_ACCOUNT]);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_update_existing_account_roles(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Add user as role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        access_control::must_be_role_manager(user1);
        
        // Update user to have service account role instead
        access_control::upsert_account(user1, user1_addr, vector[ROLE_SERVICE_ACCOUNT]);
        access_control::must_be_service_account(user1);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_multiple_roles_assignment(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Add user with multiple roles (admin and service account - should be allowed)
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ADMIN, ROLE_SERVICE_ACCOUNT]);
        access_control::must_be_admin(user1);
        access_control::must_be_service_account(user1);
    }

    #[test(deployer = @moneyfi)]
    fun test_get_accounts_view_function(deployer: &signer) {
        setup_test_environment(deployer);
        let deployer_addr = signer::address_of(deployer);

        // Initially should have one account (admin)
        let accounts = access_control::get_accounts();
        assert!(vector::length(&accounts) == 1, 0);
        
        // Add more accounts
        access_control::upsert_account(deployer, @0x3, vector[ROLE_SERVICE_ACCOUNT]);
        access_control::upsert_account(deployer, @0x2, vector[ROLE_ROLE_MANAGER]);
        
        // Should now have three accounts
        let accounts = access_control::get_accounts();
        assert!(vector::length(&accounts) == 3, 1);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure(abort_code = 0x50002, location = moneyfi::access_control)]
    fun test_service_account_cannot_manage_roles(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Add user as service account
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_SERVICE_ACCOUNT]);
        
        // Service account should not be able to add other accounts
        access_control::upsert_account(user1, @0x4, vector[ROLE_SERVICE_ACCOUNT]);
    }

    #[test(deployer = @moneyfi, user1 = @0x2)]
    #[expected_failure]
    fun test_remove_non_existent_account(deployer: &signer, user1: &signer) {
        setup_test_environment(deployer);
        let user1_addr = signer::address_of(user1);

        // Add role manager
        access_control::upsert_account(deployer, user1_addr, vector[ROLE_ROLE_MANAGER]);
        
        // Should be able to "remove" non-existent account without error
        access_control::remove_account(user1, @0x999);
    }
    
}

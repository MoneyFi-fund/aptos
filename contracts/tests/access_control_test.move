module moneyfi::access_control_test {
    use std::signer;
    use aptos_std::table;
    use aptos_framework::account;
    use std::error;
    use aptos_framework::timestamp;

    use moneyfi::access_control;

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_access_control(deployer: &signer, user1: &signer) {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        let deployer_addr = signer::address_of(deployer);
        let user1_addr = signer::address_of(user1);

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
    #[expected_failure]
    fun test_try_to_modify_without_permission(
        deployer: &signer, user: &signer
    ) {
        let user_addr = signer::address_of(user);
        account::create_account_for_test(signer::address_of(deployer));
        access_control::init_module_for_testing(deployer);

        access_control::remove_account(user, user_addr);
    }
}

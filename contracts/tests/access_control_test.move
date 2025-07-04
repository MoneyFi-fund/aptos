module moneyfi::access_control_test {
    use std::signer;
    use aptos_std::table;
    use aptos_framework::account;
    use std::error;

    use moneyfi::access_control;

    #[test(deployer = @moneyfi, user1 = @0x2)]
    fun test_access_control(deployer: &signer, user1: &signer) {
        let deployer_addr = signer::address_of(deployer);
        let user1_addr = signer::address_of(user1);

        // Simulate module deployment
        account::create_account_for_test(deployer_addr);
        access_control::initialize(deployer);

        access_control::must_be_admin(deployer);

        // Deployer assigns roles
        access_control::set_role(deployer, user1_addr, 2);
        access_control::must_be_operator(user1);

        // Update role
        access_control::set_role(deployer, user1_addr, 1);
        access_control::must_be_admin(user1);

        // Revoke role
        access_control::revoke(deployer, user1_addr);
        // TODO: not sure how to expect failure when call must_be_admin yet
    }

    #[test(deployer = @moneyfi, user = @0x2)]
    #[expected_failure]
    fun test_non_admin_cannot_set_role(deployer: &signer, user: &signer) {
        let user_addr = signer::address_of(user);
        account::create_account_for_test(signer::address_of(deployer));
        access_control::initialize(deployer);

        access_control::set_role(user, user_addr, 1);
    }
}

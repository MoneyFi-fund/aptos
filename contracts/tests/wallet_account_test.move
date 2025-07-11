#[test_only]
module moneyfi::wallet_account_test {
    use std::signer;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use std::vector;
    use aptos_framework::timestamp::{Self};

    use moneyfi::test_helpers; 
    use moneyfi::wallet_account::{Self, WalletAccount};

    fun get_position(user: address): (address, signer){
        let contructor_ref = object::create_sticky_object(user);
        (
            object::object_address<ObjectCore>(&object::object_from_constructor_ref(&contructor_ref)),
            object::generate_signer(&contructor_ref)
        )
    }

    fun get_test_wallet_id(user: address): vector<u8>{
        bcs::to_bytes<address>(&user)
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    fun test_create_wallet_account(deployer: &signer, user: &signer, aptos_framework: &signer) {

        let fa = test_helpers::setup_for_test(deployer, signer::address_of(deployer), aptos_framework);
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(deployer), fa);
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);

        let wallet_obj_addr = wallet_account::get_wallet_account_object_address(wallet_id);

        assert!(object::object_exists<WalletAccount>(wallet_obj_addr), 1);
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x80001, location = moneyfi::wallet_account)]
    fun test_create_wallet_account_already_exists(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let fa = test_helpers::setup_for_test(deployer, signer::address_of(deployer), aptos_framework);
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(deployer), fa);

        //first call
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        //second call
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
    }


}
#[test_only]
module moneyfi::wallet_account_test {
    use std::signer;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use std::vector;
    use aptos_framework::timestamp::{Self};

    use moneyfi::test_helpers; 
    use moneyfi::access_control;
    use moneyfi::wallet_account::{Self, WalletAccount, WalletAccountObject};


    fun setup_for_test(deployer: &signer,fee_to: address ,aptos_framework: &signer, amount: u64): (FungibleAsset, Object<Metadata>) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let deployer_addr = signer::address_of(deployer);
        // Simulate module deployment
        account::create_account_for_test(deployer_addr);
        access_control::initialize(deployer);
        access_control::set_fee_to(deployer, fee_to);

       let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"token1", amount);
       let metadata = fungible_asset::metadata_from_asset(&fa);
       access_control::add_asset_supported(deployer, object::object_address(&metadata));
       (fa, metadata)
        }

    fun get_position(wallet_account_addr: address): (address, signer){
        let contructor_ref = object::create_sticky_object(wallet_account_addr);
        (
            object::object_address<ObjectCore>(&object::object_from_constructor_ref(&contructor_ref)),
            object::generate_signer(&contructor_ref)
        )
    }

    fun get_test_wallet_id(user: address): vector<u8>{
        bcs::to_bytes<address>(&user)
    }

    fun create_token_and_add_to_supported_asset(deployer: &signer,  name: vector<u8>): FungibleAsset { 
       let fa = test_helpers::create_fungible_asset_and_mint(deployer, name, 10000);
       let metadata = fungible_asset::metadata_from_asset(&fa);
       access_control::add_asset_supported(deployer, object::object_address(&metadata));
       fa 
    }
    
    fun deposit_token_to_wallet_account( sender: &signer, wallet_id: vector<u8>, asset: Object<Metadata>, amount: u64,fee_amount: u64) {
        let deposit_amounts = vector::empty<u64>(); 
        vector::push_back(&mut deposit_amounts, amount); 

        // // create vector asset 
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, asset);

        wallet_account::deposit_to_wallet_account(sender, wallet_id, assets, deposit_amounts, fee_amount); 
    }

    fun withdraw_from_wallet_account_by_user(sender: &signer, wallet_id: vector<u8>, asset: Object<Metadata>, amount: u64) {
        let withdraw_amounts = vector::empty<u64>(); 
        vector::push_back(&mut withdraw_amounts, amount); 

        // // create vector asset 
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, asset);

        wallet_account::withdraw_from_wallet_account_by_user(sender, wallet_id, assets, withdraw_amounts); 
    }

    fun get_asset_deposit_to_wallet_account(wallet_id: vector<u8>, metadata: Object<Metadata>): (bool, u64) {
        let (metadata_addrs, amounts) = wallet_account::get_assets(wallet_id);
        let (b,index) = vector::index_of(&metadata_addrs, &object::object_address(&metadata));
        (b,if(b){*vector::borrow(&amounts, index)} else{0})
    }

    fun get_asset_distribute_wallet_account(wallet_id: vector<u8>, metadata: Object<Metadata>): (bool ,u64) {
        let (metadata_addrs, amounts) = wallet_account::get_distributed_assets(wallet_id);
        let (b,index) = vector::index_of(&metadata_addrs, &object::object_address(&metadata));
        (b,if(b){*vector::borrow(&amounts, index)} else{0})
    }

    ////////////////////////////////////////////////
    ///////////// connect_aptos_wallet ////////////
    //////////////////////////////////////////////
    #[test(deployer = @moneyfi, user1 = @0xa1, fee_to = @0xa10, aptos_framework = @0x1)]
    fun test_connect_aptos_wallet_should_right(deployer: &signer, user1: &signer, fee_to: &signer,  aptos_framework: &signer) {
        let (token_1, _) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 1);
        primary_fungible_store::deposit(signer::address_of(deployer), token_1); 

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 

        wallet_account::connect_aptos_wallet(user1, wallet_id); 
    }

    #[test(deployer = @moneyfi, user1 = @0xa1, user2 =  @0xa2, fee_to =  @0xa10, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_connect_aptos_wallet_should_revert_E_NOT_APTOS_WALLET_ACCOUNT(deployer: &signer, user1: &signer, user2: &signer, fee_to: &signer, aptos_framework: &signer) {
        let (token_1, _) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 1);
        primary_fungible_store::deposit(signer::address_of(deployer), token_1); 

        let wallet_id = bcs::to_bytes<address>(&signer::address_of(user1));

        wallet_account::connect_aptos_wallet(user1, wallet_id); 

    }   
    
    #[test(deployer = @moneyfi, user1 = @0xa1, user2 =  @0xa2, fee_to =  @0xa10 , aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_connect_aptos_wallet_should_revert_E_NOT_OWNER(deployer: &signer, user1: &signer, user2: &signer, fee_to: &signer, aptos_framework: &signer) {
        let (token_1, _) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 1);
        primary_fungible_store::deposit(signer::address_of(deployer), token_1); 

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user2), true); 

        wallet_account::connect_aptos_wallet(user1, wallet_id); 
    }

    ////////////////////////////////////////////////
    ////////// deposit_to_wallet_account //////////
    //////////////////////////////////////////////
    #[test(deployer = @moneyfi, user1 = @0x2, fee_to =  @0xa10, aptos_framework = @0x1)]
    fun test_deposit_to_wallet_account_should_right(deployer: &signer, user1: &signer, fee_to: &signer, aptos_framework: &signer) {
        let (token_1, fa_metadata) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);

        primary_fungible_store::deposit(signer::address_of(user1), token_1);   

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 
        wallet_account::connect_aptos_wallet(user1, wallet_id); 

        let deposit_amount = 10000;  
        let fee_amount = 100; 
 
        let pre_data_object_balance = primary_fungible_store::balance(access_control::get_data_object_address(), fa_metadata); 
        let pre_wallet_account_balance = primary_fungible_store::balance(wallet_account::get_wallet_account_object_address(wallet_id),fa_metadata); 
        deposit_token_to_wallet_account(user1, wallet_id, fa_metadata, deposit_amount, fee_amount);
        
        let pos_data_object_balance = primary_fungible_store::balance(access_control::get_data_object_address(), fa_metadata); 
        let pos_wallet_account_balance = primary_fungible_store::balance(wallet_account::get_wallet_account_object_address(wallet_id),fa_metadata); 

        assert!(pos_data_object_balance  - pre_data_object_balance == fee_amount);
        assert!(pos_wallet_account_balance - pre_wallet_account_balance == deposit_amount - fee_amount);

        // Check asset field in <WalletAccount> 
        let (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(wallet_id, fa_metadata); 
        assert!(is_exist == true);
        assert!(remaining_amount_asset == deposit_amount - fee_amount);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, fee_to =  @0xa10, aptos_framework = @0x1)]
    fun test_deposit_to_wallet_account_multiple_token_should_right(deployer: &signer, user1: &signer, fee_to: &signer, aptos_framework: &signer) {
        let (token_1, fa_metadata_1 ) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);   

        let token_2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let fa_metadata_2 = fungible_asset::metadata_from_asset(&token_2);
        primary_fungible_store::deposit(signer::address_of(user1), token_2);   

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 

        wallet_account::connect_aptos_wallet(user1, wallet_id); 

        // create vector deposit amount corresponding to vector asset 
        let deposit_amount = 10000;  
        let fee_amount = 100; 
        let deposit_amounts = vector::empty<u64>(); 
        vector::push_back(&mut deposit_amounts, deposit_amount); 
        vector::push_back(&mut deposit_amounts, deposit_amount); 

        // create vector asset 
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, fa_metadata_1);
        vector::push_back(&mut assets, fa_metadata_2);

        let pre_data_object_balance_1 = primary_fungible_store::balance(access_control::get_data_object_address(), fa_metadata_1); 
        let pre_wallet_account_balance_1 = primary_fungible_store::balance(wallet_account::get_wallet_account_object_address(wallet_id),fa_metadata_1); 
        let pre_data_object_balance_2 = primary_fungible_store::balance(access_control::get_data_object_address(), fa_metadata_2); 
        let pre_wallet_account_balance_2 = primary_fungible_store::balance(wallet_account::get_wallet_account_object_address(wallet_id),fa_metadata_2); 
       
        wallet_account::deposit_to_wallet_account(user1, wallet_id, assets, deposit_amounts, fee_amount); 
        
        let pos_data_object_balance_1 = primary_fungible_store::balance(access_control::get_data_object_address(), fa_metadata_1); 
        let pos_wallet_account_balance_1 = primary_fungible_store::balance(wallet_account::get_wallet_account_object_address(wallet_id),fa_metadata_1); 
        let pos_data_object_balance_2 = primary_fungible_store::balance(access_control::get_data_object_address(), fa_metadata_2); 
        let pos_wallet_account_balance_2 = primary_fungible_store::balance(wallet_account::get_wallet_account_object_address(wallet_id),fa_metadata_2); 


        assert!(pos_data_object_balance_1  - pre_data_object_balance_1 == fee_amount);
        assert!(pos_wallet_account_balance_1 - pre_wallet_account_balance_1 == deposit_amount - fee_amount);

        // Just only minus fee amount one time 
        assert!(pre_data_object_balance_2 == 0);
        assert!(pos_data_object_balance_2 == 0);
        assert!(pos_wallet_account_balance_2 - pre_wallet_account_balance_2 == deposit_amount);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, fee_to =  @0xa10, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_deposit_to_wallet_account_should_revert_E_WALLET_ACCOUNT_NOT_EXISTS(deployer: &signer, user1: &signer, fee_to: &signer,  aptos_framework: &signer) {
        let (token_1, fa_metadata_1 ) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let wallet_id = bcs::to_bytes<address>(&signer::address_of(user1));

        let deposit_amount = 100000;  

        // // init FA and mint        
        let token_1 = test_helpers::create_fungible_asset_and_mint(deployer, b"TT", deposit_amount);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        primary_fungible_store::deposit(signer::address_of(user1), token_1); 

        deposit_token_to_wallet_account(user1, wallet_id, fa_metadata, deposit_amount, 0);
    }

    // In case of 
    #[test(deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_deposit_to_wallet_account_should_revert_E_INVALID_ARGUMENT(deployer: &signer, user1: &signer, fee_to: &signer,  aptos_framework: &signer) {
        let (token_1, fa_metadata_1 ) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);
        primary_fungible_store::deposit(signer::address_of(deployer), token_1);   

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 

        wallet_account::connect_aptos_wallet(user1, wallet_id); 

        // create vector deposit amount corresponding to vector asset 
        let deposit_amount = 100000;  
        let deposit_amounts = vector::empty<u64>(); 
        vector::push_back(&mut deposit_amounts, deposit_amount); 
        vector::push_back(&mut deposit_amounts, deposit_amount); 

        // // init FA and mint        
        let token_1 = test_helpers::create_fungible_asset_and_mint(deployer, b"TT", deposit_amount);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        primary_fungible_store::deposit(signer::address_of(user1), token_1); 

        // create vector asset 
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, fa_metadata);

        wallet_account::deposit_to_wallet_account(user1, wallet_id, assets, deposit_amounts, 0); 
    }   
    
    ////////////////////////////////////////////////
    ///// withdraw_from_wallet_account_by_user/////
    //////////////////////////////////////////////
    #[test(deployer = @moneyfi, user1 = @0x2, fee_to =  @0xa10, aptos_framework = @0x1)]
    fun test_withdraw_from_wallet_account_by_user_should_right(deployer: &signer, user1: &signer, fee_to: &signer, aptos_framework: &signer) {
         let (token_1, fa_metadata ) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        let token_1_addr = object::object_address(&fa_metadata);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);   

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 

        wallet_account::connect_aptos_wallet(user1, wallet_id); 

        // create vector deposit amount corresponding to vector asset 
        let deposit_amount = 10000;  
        let fee_amount = 100; 
        deposit_token_to_wallet_account(user1, wallet_id, fa_metadata, deposit_amount, fee_amount);

        let total_amount_withdraw = deposit_amount - fee_amount; 

        // Test withdraw partly
        let pre_user1_balance = primary_fungible_store::balance(signer::address_of(user1),fa_metadata); 
        withdraw_from_wallet_account_by_user(user1, wallet_id, fa_metadata, total_amount_withdraw/2); 
        let pos_user1_balance = primary_fungible_store::balance(signer::address_of(user1),fa_metadata);
        assert!(pos_user1_balance - pre_user1_balance == total_amount_withdraw/2);
        let (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(wallet_id, fa_metadata); 
        assert!(is_exist == true);
        assert!(remaining_amount_asset == total_amount_withdraw/2);

        // Test withdraw all 
        pre_user1_balance = primary_fungible_store::balance(signer::address_of(user1),fa_metadata); 
        withdraw_from_wallet_account_by_user(user1, wallet_id, fa_metadata, total_amount_withdraw/2); 
        pos_user1_balance = primary_fungible_store::balance(signer::address_of(user1),fa_metadata);
        (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(wallet_id, fa_metadata); 
        assert!(pos_user1_balance - pre_user1_balance == total_amount_withdraw/2);
        assert!(is_exist == false);
        assert!(remaining_amount_asset == 0);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, fee_to =  @0xa10, aptos_framework = @0x1)]
    fun test_withdraw_from_wallet_account_by_user_multiple_asset_should_right(deployer: &signer, user1: &signer, fee_to: &signer, aptos_framework: &signer) {
        let (token_1, fa_metadata_1) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);
        let fa_metadata_1 = fungible_asset::metadata_from_asset(&token_1);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);   

        let token_2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let fa_metadata_2 = fungible_asset::metadata_from_asset(&token_2);
        primary_fungible_store::deposit(signer::address_of(user1), token_2);   

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 
        wallet_account::connect_aptos_wallet(user1, wallet_id); 
        
        // create vector deposit amount corresponding to vector asset 
        let deposit_amount = 10000;  
        let fee_amount = 100; 
        let deposit_amounts = vector::empty<u64>(); 
        vector::push_back(&mut deposit_amounts, deposit_amount); 
        vector::push_back(&mut deposit_amounts, deposit_amount); 

        // create vector asset 
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, fa_metadata_1);
        vector::push_back(&mut assets, fa_metadata_2);

        // deposit multiple amount
        wallet_account::deposit_to_wallet_account(user1, wallet_id, assets, deposit_amounts, fee_amount); 

        let withdraw_amounts = vector::empty<u64>(); 
        vector::push_back(&mut withdraw_amounts, deposit_amount - fee_amount); 
        vector::push_back(&mut withdraw_amounts, deposit_amount); 
        
        let pre_user1_balance_token_1 = primary_fungible_store::balance(signer::address_of(user1),fa_metadata_1); 
        let pre_user1_balance_token_2 = primary_fungible_store::balance(signer::address_of(user1),fa_metadata_2); 
        wallet_account::withdraw_from_wallet_account_by_user(user1, wallet_id, assets, withdraw_amounts); 

        // Test withdraw all token_1
        let pos_user1_balance_token_1 = primary_fungible_store::balance(signer::address_of(user1),fa_metadata_1);
        let (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(wallet_id, fa_metadata_1); 
        assert!(pos_user1_balance_token_1 - pre_user1_balance_token_1 == deposit_amount - fee_amount);
        assert!(is_exist == false);
        assert!(remaining_amount_asset == 0);

        // Test withdraw all token_2
        let pos_user1_balance_token_2 = primary_fungible_store::balance(signer::address_of(user1),fa_metadata_2);
        (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(wallet_id, fa_metadata_2); 
        assert!(pos_user1_balance_token_2 - pre_user1_balance_token_2 == deposit_amount);
        assert!(is_exist == false);
        assert!(remaining_amount_asset == 0);
    }

    #[test(deployer = @moneyfi, user1 = @0x2, fee_to =  @0xa10, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_withdraw_from_wallet_account_by_user_should_revert_E_INVALID_ARGUMENT(deployer: &signer, user1: &signer, fee_to: &signer, aptos_framework: &signer) {
        let (token_1, fa_metadata) = setup_for_test(deployer, signer::address_of(fee_to), aptos_framework, 10000);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        let token_1_addr = object::object_address(&fa_metadata);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);   

        let wallet_id = wallet_account::create_wallet_account_for_test(signer::address_of(user1), true); 

        wallet_account::connect_aptos_wallet(user1, wallet_id); 

        // create vector deposit amount corresponding to vector asset 
        let deposit_amount = 10000;  
        let fee_amount = 100; 
        deposit_token_to_wallet_account(user1, wallet_id, fa_metadata, deposit_amount, fee_amount);

        let total_amount_withdraw = deposit_amount - fee_amount; 

        // create withdraw amount vector
        let withdraw_amounts= vector::empty<u64>(); 
        vector::push_back(&mut withdraw_amounts, deposit_amount); 
        vector::push_back(&mut withdraw_amounts, deposit_amount); 

        // // create vector asset 
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, fa_metadata);
        
        // revert when withdraw_amounts_exceed.lenght > assets.lenght 
        wallet_account::withdraw_from_wallet_account_by_user(user1, wallet_id, assets, withdraw_amounts); 
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    fun test_create_wallet_account(deployer: &signer, user: &signer, aptos_framework: &signer) {

        let (fa,_) = setup_for_test(deployer, signer::address_of(deployer), aptos_framework,10000);
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(deployer), fa);
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);

        let wallet_obj_addr = wallet_account::get_wallet_account_object_address(wallet_id);

        assert!(object::object_exists<WalletAccount>(wallet_obj_addr), 1);
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x80001, location = moneyfi::wallet_account)]
    fun test_create_wallet_account_already_exists(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa,_) = setup_for_test(deployer, signer::address_of(deployer), aptos_framework,10000);
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(deployer), fa);

        //first call
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        //second call
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
    }

    //test conncec, deposit, withdraw

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    fun test_add_position_opened(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa, metadata) = setup_for_test(
                deployer, 
                signer::address_of(deployer), 
                aptos_framework, 
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        //-- deposit to wallet account
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr = wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer = wallet_account::get_wallet_account_signer(deployer, wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );
        assert!(test_helpers::balance_of_token(signer::address_of(user), metadata) == 0, 1);
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 10000, 1);
        let (_, a) = get_asset_deposit_to_wallet_account(wallet_id, metadata);
        assert!( a == 10000, 1);
        //-- add position
        // simulate position
        let (position_addr, position_signer) = get_position(wallet_account_addr);
        primary_fungible_store::transfer(
            &wallet_account_signer,
            metadata,
            position_addr,
            5000
        );
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 5000, 1);
        assert!(test_helpers::balance_of_token(position_addr, metadata) == 5000, 1);
        let (_, b) = get_asset_deposit_to_wallet_account(wallet_id, metadata);
        assert!(b == 5000, 1);
        let (_, c) = get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(c == 5000, 1);
        let (position_openeds,_) = wallet_account::get_position_opened(wallet_id);
        assert!(vector::contains(&position_openeds, &position_addr), 1);
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_add_position_opened_not_sever_called(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa, metadata) = setup_for_test(
                deployer, 
                signer::address_of(deployer), 
                aptos_framework, 
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        //-- deposit to wallet account
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr = wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer = wallet_account::get_wallet_account_signer(deployer, wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, position_signer) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            user,
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_add_position_opened_not_create_wallet_account(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa, metadata) = setup_for_test(
                deployer, 
                signer::address_of(deployer), 
                aptos_framework, 
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        let wallet_account_addr = wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, position_signer) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );
    }
    
    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_add_position_opened_invalid_argument(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa, metadata) = setup_for_test(
                deployer, 
                signer::address_of(deployer), 
                aptos_framework, 
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        primary_fungible_store::deposit(signer::address_of(user), fa);
        let wallet_account_addr = wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );
        let amounts = vector::singleton<u64>(5000);
        vector::push_back(&mut amounts, 5000);
        let (position_addr, position_signer) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            amounts,
            1,
            0
        );
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x80009, location = moneyfi::wallet_account)]
    fun test_add_position_opened_already_exists_position(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa, metadata) = setup_for_test(
                deployer, 
                signer::address_of(deployer), 
                aptos_framework, 
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        primary_fungible_store::deposit(signer::address_of(user), fa);
        let wallet_account_addr = wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );
        let (position_addr, position_signer) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );
    }

    #[test(deployer = @moneyfi,user = @0xab, aptos_framework = @0x1)]
    fun test_remove_position_opened(deployer: &signer, user: &signer, aptos_framework: &signer) {
        let (fa, metadata) = setup_for_test(
                deployer, 
                signer::address_of(deployer), 
                aptos_framework, 
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        //-- deposit to wallet account
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr = wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer = wallet_account::get_wallet_account_signer(deployer, wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );
        assert!(test_helpers::balance_of_token(signer::address_of(user), metadata) == 0, 1);
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 10000, 1);
        let (_, a) = get_asset_deposit_to_wallet_account(wallet_id, metadata);
        assert!( a == 10000, 1);
        //-- add position
        // simulate position
        let (position_addr, position_signer) = get_position(wallet_account_addr);
        primary_fungible_store::transfer(
            &wallet_account_signer,
            metadata,
            position_addr,
            5000
        );
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 5000, 1);
        assert!(test_helpers::balance_of_token(position_addr, metadata) == 5000, 1);
        let (_, b) = get_asset_deposit_to_wallet_account(wallet_id, metadata);
        assert!(b == 5000, 1);
        let (_, c) = get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(c == 5000, 1);
        let (position_openeds,_) = wallet_account::get_position_opened(wallet_id);
        assert!(vector::contains(&position_openeds, &position_addr), 1);

        // remove position
        primary_fungible_store::transfer(
            &position_signer,
            metadata,
            wallet_account_addr,
            5000
        );

        wallet_account::remove_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            metadata,
            100
        );
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 9900, 1);
        assert!(test_helpers::balance_of_token(position_addr, metadata) == 0, 1);
        let (_, d) = get_asset_deposit_to_wallet_account(wallet_id, metadata);
        assert!(d == 10000, 1);
        let (_, e) = get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(e == 0, 1);
        let (position_openeds,_) = wallet_account::get_position_opened(wallet_id);
        assert!(!vector::contains(&position_openeds, &position_addr), 1);

    }

}
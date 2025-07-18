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

    fun setup_for_test(
        deployer: &signer,
        fee_to: address,
        aptos_framework: &signer,
        amount: u64
    ): (FungibleAsset, Object<Metadata>) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let deployer_addr = signer::address_of(deployer);
        // Simulate module deployment
        account::create_account_for_test(deployer_addr);
        access_control::initialize(deployer);
        wallet_account::initialize(deployer);

        let fa = test_helpers::create_fungible_asset_and_mint(
            deployer, b"token1", amount
        );
        let metadata = fungible_asset::metadata_from_asset(&fa);
        access_control::add_asset_supported(deployer, object::object_address(&metadata));
        (fa, metadata)
    }

    fun get_position(wallet_account_addr: address): (address, signer) {
        let contructor_ref = object::create_sticky_object(wallet_account_addr);
        (
            object::object_address<ObjectCore>(
                &object::object_from_constructor_ref(&contructor_ref)
            ),
            object::generate_signer(&contructor_ref)
        )
    }

    fun get_test_wallet_id(user: address): vector<u8> {
        bcs::to_bytes<address>(&user)
    }

    fun create_token_and_add_to_supported_asset(
        deployer: &signer, name: vector<u8>
    ): FungibleAsset {
        let fa = test_helpers::create_fungible_asset_and_mint(deployer, name, 10000);
        let metadata = fungible_asset::metadata_from_asset(&fa);
        access_control::add_asset_supported(deployer, object::object_address(&metadata));
        fa
    }

    fun deposit_token_to_wallet_account(
        sender: &signer,
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        amount: u64,
        fee_amount: u64
    ) {
        let deposit_amounts = vector::empty<u64>();
        vector::push_back(&mut deposit_amounts, amount);

        // // create vector asset
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, asset);

        wallet_account::deposit_to_wallet_account(
            sender,
            wallet_id,
            assets,
            deposit_amounts,
            fee_amount
        );
    }

    fun withdraw_from_wallet_account_by_user(
        sender: &signer,
        wallet_id: vector<u8>,
        asset: Object<Metadata>,
        amount: u64
    ) {
        let withdraw_amounts = vector::empty<u64>();
        vector::push_back(&mut withdraw_amounts, amount);

        // // create vector asset
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, asset);

        wallet_account::withdraw_from_wallet_account_by_user(
            sender, wallet_id, assets, withdraw_amounts
        );
    }

    fun get_asset_deposit_to_wallet_account(
        wallet_id: vector<u8>, metadata: Object<Metadata>
    ): (bool, u64) {
        let (metadata_addrs, amounts) = wallet_account::get_assets(wallet_id);
        let (b, index) = vector::index_of(
            &metadata_addrs, &object::object_address(&metadata)
        );
        (b, if (b) {
            *vector::borrow(&amounts, index)
        } else { 0 })
    }

    fun get_asset_distribute_wallet_account(
        wallet_id: vector<u8>, metadata: Object<Metadata>
    ): (bool, u64) {
        let (metadata_addrs, amounts) = wallet_account::get_distributed_assets(wallet_id);
        let (b, index) = vector::index_of(
            &metadata_addrs, &object::object_address(&metadata)
        );
        (b, if (b) {
            *vector::borrow(&amounts, index)
        } else { 0 })
    }

    fun get_total_profit_claimed_by_metadata(
        wallet_id: vector<u8>, metadata: Object<Metadata>
    ): (bool, u64) {
        let (metadata_addrs, amounts) =
            wallet_account::get_total_profit_claimed(wallet_id);
        let (b, index) = vector::index_of(
            &metadata_addrs, &object::object_address(&metadata)
        );
        (b, if (b) {
            *vector::borrow(&amounts, index)
        } else { 0 })
    }

    ////////////////////////////////////////////////
    ///////////// connect_aptos_wallet ////////////
    //////////////////////////////////////////////
    #[test(
        deployer = @moneyfi, user1 = @0xa1, fee_to = @0xa10, aptos_framework = @0x1
    )]
    fun test_connect_aptos_wallet_should_right(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, _) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                1
            );
        primary_fungible_store::deposit(signer::address_of(deployer), token_1);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );

        wallet_account::connect_aptos_wallet(user1, wallet_id);
    }

    #[
        test(
            deployer = @moneyfi,
            user1 = @0xa1,
            user2 = @0xa2,
            fee_to = @0xa10,
            aptos_framework = @0x1
        )
    ]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_connect_aptos_wallet_should_revert_E_NOT_APTOS_WALLET_ACCOUNT(
        deployer: &signer,
        user1: &signer,
        user2: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, _) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                1
            );
        primary_fungible_store::deposit(signer::address_of(deployer), token_1);

        let wallet_id = bcs::to_bytes<address>(&signer::address_of(user1));

        wallet_account::connect_aptos_wallet(user1, wallet_id);

    }

    #[
        test(
            deployer = @moneyfi,
            user1 = @0xa1,
            user2 = @0xa2,
            fee_to = @0xa10,
            aptos_framework = @0x1
        )
    ]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_connect_aptos_wallet_should_revert_E_NOT_OWNER(
        deployer: &signer,
        user1: &signer,
        user2: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, _) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                1
            );
        primary_fungible_store::deposit(signer::address_of(deployer), token_1);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user2), true
            );

        wallet_account::connect_aptos_wallet(user1, wallet_id);
    }

    ////////////////////////////////////////////////
    ////////// deposit_to_wallet_account //////////
    //////////////////////////////////////////////
    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    fun test_deposit_to_wallet_account_should_right(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );

        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );
        wallet_account::connect_aptos_wallet(user1, wallet_id);

        let deposit_amount = 10000;
        let fee_amount = 100;

        let pre_data_object_balance =
            primary_fungible_store::balance(
                access_control::get_data_object_address(), fa_metadata
            );
        let pre_wallet_account_balance =
            primary_fungible_store::balance(
                wallet_account::get_wallet_account_object_address(wallet_id),
                fa_metadata
            );
        deposit_token_to_wallet_account(
            user1,
            wallet_id,
            fa_metadata,
            deposit_amount,
            fee_amount
        );

        let pos_data_object_balance =
            primary_fungible_store::balance(
                access_control::get_data_object_address(), fa_metadata
            );
        let pos_wallet_account_balance =
            primary_fungible_store::balance(
                wallet_account::get_wallet_account_object_address(wallet_id),
                fa_metadata
            );

        assert!(
            pos_data_object_balance - pre_data_object_balance == fee_amount
        );
        assert!(
            pos_wallet_account_balance - pre_wallet_account_balance
                == deposit_amount - fee_amount
        );

        // Check asset field in <WalletAccount>
        let (is_exist, remaining_amount_asset) =
            get_asset_deposit_to_wallet_account(wallet_id, fa_metadata);
        assert!(is_exist == true);
        assert!(
            remaining_amount_asset == deposit_amount - fee_amount
        );
    }

    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    fun test_deposit_to_wallet_account_multiple_token_should_right(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata_1) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let token_2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let fa_metadata_2 = fungible_asset::metadata_from_asset(&token_2);
        primary_fungible_store::deposit(signer::address_of(user1), token_2);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );

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

        let pre_data_object_balance_1 =
            primary_fungible_store::balance(
                access_control::get_data_object_address(), fa_metadata_1
            );
        let pre_wallet_account_balance_1 =
            primary_fungible_store::balance(
                wallet_account::get_wallet_account_object_address(wallet_id),
                fa_metadata_1
            );
        let pre_data_object_balance_2 =
            primary_fungible_store::balance(
                access_control::get_data_object_address(), fa_metadata_2
            );
        let pre_wallet_account_balance_2 =
            primary_fungible_store::balance(
                wallet_account::get_wallet_account_object_address(wallet_id),
                fa_metadata_2
            );

        wallet_account::deposit_to_wallet_account(
            user1,
            wallet_id,
            assets,
            deposit_amounts,
            fee_amount
        );

        let pos_data_object_balance_1 =
            primary_fungible_store::balance(
                access_control::get_data_object_address(), fa_metadata_1
            );
        let pos_wallet_account_balance_1 =
            primary_fungible_store::balance(
                wallet_account::get_wallet_account_object_address(wallet_id),
                fa_metadata_1
            );
        let pos_data_object_balance_2 =
            primary_fungible_store::balance(
                access_control::get_data_object_address(), fa_metadata_2
            );
        let pos_wallet_account_balance_2 =
            primary_fungible_store::balance(
                wallet_account::get_wallet_account_object_address(wallet_id),
                fa_metadata_2
            );

        assert!(
            pos_data_object_balance_1 - pre_data_object_balance_1 == fee_amount
        );
        assert!(
            pos_wallet_account_balance_1 - pre_wallet_account_balance_1
                == deposit_amount - fee_amount
        );

        // Just only minus fee amount one time
        assert!(pre_data_object_balance_2 == 0);
        assert!(pos_data_object_balance_2 == 0);
        assert!(
            pos_wallet_account_balance_2 - pre_wallet_account_balance_2
                == deposit_amount
        );
    }

    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_deposit_to_wallet_account_should_revert_E_WALLET_ACCOUNT_NOT_EXISTS(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata_1) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let wallet_id = bcs::to_bytes<address>(&signer::address_of(user1));

        let deposit_amount = 100000;

        // // init FA and mint
        let token_1 =
            test_helpers::create_fungible_asset_and_mint(deployer, b"TT", deposit_amount);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        deposit_token_to_wallet_account(
            user1,
            wallet_id,
            fa_metadata,
            deposit_amount,
            0
        );
    }

    // In case of
    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_deposit_to_wallet_account_should_revert_E_INVALID_ARGUMENT(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata_1) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );
        primary_fungible_store::deposit(signer::address_of(deployer), token_1);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );

        wallet_account::connect_aptos_wallet(user1, wallet_id);

        // create vector deposit amount corresponding to vector asset
        let deposit_amount = 100000;
        let deposit_amounts = vector::empty<u64>();
        vector::push_back(&mut deposit_amounts, deposit_amount);
        vector::push_back(&mut deposit_amounts, deposit_amount);

        // // init FA and mint
        let token_1 =
            test_helpers::create_fungible_asset_and_mint(deployer, b"TT", deposit_amount);
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        // create vector asset
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, fa_metadata);

        wallet_account::deposit_to_wallet_account(
            user1, wallet_id, assets, deposit_amounts, 0
        );
    }

    ////////////////////////////////////////////////
    ///// withdraw_from_wallet_account_by_user/////
    //////////////////////////////////////////////
    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    fun test_withdraw_from_wallet_account_by_user_should_right(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        let token_1_addr = object::object_address(&fa_metadata);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );

        wallet_account::connect_aptos_wallet(user1, wallet_id);

        // create vector deposit amount corresponding to vector asset
        let deposit_amount = 10000;
        let fee_amount = 100;
        deposit_token_to_wallet_account(
            user1,
            wallet_id,
            fa_metadata,
            deposit_amount,
            fee_amount
        );

        let total_amount_withdraw = deposit_amount - fee_amount;

        // Test withdraw partly
        let pre_user1_balance =
            primary_fungible_store::balance(signer::address_of(user1), fa_metadata);
        withdraw_from_wallet_account_by_user(
            user1,
            wallet_id,
            fa_metadata,
            total_amount_withdraw / 2
        );
        let pos_user1_balance =
            primary_fungible_store::balance(signer::address_of(user1), fa_metadata);
        assert!(
            pos_user1_balance - pre_user1_balance == total_amount_withdraw / 2
        );
        let (is_exist, remaining_amount_asset) =
            get_asset_deposit_to_wallet_account(wallet_id, fa_metadata);
        assert!(is_exist == true);
        assert!(
            remaining_amount_asset == total_amount_withdraw / 2
        );

        // Test withdraw all
        pre_user1_balance = primary_fungible_store::balance(
            signer::address_of(user1), fa_metadata
        );
        withdraw_from_wallet_account_by_user(
            user1,
            wallet_id,
            fa_metadata,
            total_amount_withdraw / 2
        );
        pos_user1_balance = primary_fungible_store::balance(
            signer::address_of(user1), fa_metadata
        );
        (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(
            wallet_id, fa_metadata
        );
        assert!(
            pos_user1_balance - pre_user1_balance == total_amount_withdraw / 2
        );
        assert!(is_exist == false);
        assert!(remaining_amount_asset == 0);
    }

    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    fun test_withdraw_from_wallet_account_by_user_multiple_asset_should_right(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata_1) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );
        let fa_metadata_1 = fungible_asset::metadata_from_asset(&token_1);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let token_2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let fa_metadata_2 = fungible_asset::metadata_from_asset(&token_2);
        primary_fungible_store::deposit(signer::address_of(user1), token_2);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );
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
        wallet_account::deposit_to_wallet_account(
            user1,
            wallet_id,
            assets,
            deposit_amounts,
            fee_amount
        );

        let withdraw_amounts = vector::empty<u64>();
        vector::push_back(&mut withdraw_amounts, deposit_amount - fee_amount);
        vector::push_back(&mut withdraw_amounts, deposit_amount);

        let pre_user1_balance_token_1 =
            primary_fungible_store::balance(signer::address_of(user1), fa_metadata_1);
        let pre_user1_balance_token_2 =
            primary_fungible_store::balance(signer::address_of(user1), fa_metadata_2);
        wallet_account::withdraw_from_wallet_account_by_user(
            user1, wallet_id, assets, withdraw_amounts
        );

        // Test withdraw all token_1
        let pos_user1_balance_token_1 =
            primary_fungible_store::balance(signer::address_of(user1), fa_metadata_1);
        let (is_exist, remaining_amount_asset) =
            get_asset_deposit_to_wallet_account(wallet_id, fa_metadata_1);
        assert!(
            pos_user1_balance_token_1 - pre_user1_balance_token_1
                == deposit_amount - fee_amount
        );
        assert!(is_exist == false);
        assert!(remaining_amount_asset == 0);

        // Test withdraw all token_2
        let pos_user1_balance_token_2 =
            primary_fungible_store::balance(signer::address_of(user1), fa_metadata_2);
        (is_exist, remaining_amount_asset) = get_asset_deposit_to_wallet_account(
            wallet_id, fa_metadata_2
        );
        assert!(
            pos_user1_balance_token_2 - pre_user1_balance_token_2 == deposit_amount
        );
        assert!(is_exist == false);
        assert!(remaining_amount_asset == 0);
    }

    #[test(
        deployer = @moneyfi, user1 = @0x2, fee_to = @0xa10, aptos_framework = @0x1
    )]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_withdraw_from_wallet_account_by_user_should_revert_E_INVALID_ARGUMENT(
        deployer: &signer,
        user1: &signer,
        fee_to: &signer,
        aptos_framework: &signer
    ) {
        let (token_1, fa_metadata) =
            setup_for_test(
                deployer,
                signer::address_of(fee_to),
                aptos_framework,
                10000
            );
        let fa_metadata = fungible_asset::metadata_from_asset(&token_1);
        let token_1_addr = object::object_address(&fa_metadata);
        primary_fungible_store::deposit(signer::address_of(user1), token_1);

        let wallet_id =
            wallet_account::create_wallet_account_for_test(
                signer::address_of(user1), true
            );

        wallet_account::connect_aptos_wallet(user1, wallet_id);

        // create vector deposit amount corresponding to vector asset
        let deposit_amount = 10000;
        let fee_amount = 100;
        deposit_token_to_wallet_account(
            user1,
            wallet_id,
            fa_metadata,
            deposit_amount,
            fee_amount
        );

        let total_amount_withdraw = deposit_amount - fee_amount;

        // create withdraw amount vector
        let withdraw_amounts = vector::empty<u64>();
        vector::push_back(&mut withdraw_amounts, deposit_amount);
        vector::push_back(&mut withdraw_amounts, deposit_amount);

        // // create vector asset
        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, fa_metadata);

        // revert when withdraw_amounts_exceed.lenght > assets.lenght
        wallet_account::withdraw_from_wallet_account_by_user(
            user1, wallet_id, assets, withdraw_amounts
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_create_wallet_account(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {

        let (fa, _) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(deployer), fa);
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);

        let wallet_obj_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);

        assert!(object::object_exists<WalletAccount>(wallet_obj_addr), 1);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x80001, location = moneyfi::wallet_account)]
    fun test_create_wallet_account_already_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, _) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(deployer), fa);

        //first call
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        //second call
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
    }

    //test conncec, deposit, withdraw

    // ========== ADD_POSITION_OPENED TESTS ==========
    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_add_position_opened(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        //-- deposit to wallet account
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer =
            wallet_account::get_wallet_account_signer(deployer, wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );
        assert!(
            test_helpers::balance_of_token(signer::address_of(user), metadata) == 0, 1
        );
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 10000, 1);
        let (_, a) = get_asset_deposit_to_wallet_account(wallet_id, metadata);
        assert!(a == 10000, 1);
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
        let (position_openeds, _) = wallet_account::get_position_opened(wallet_id);
        assert!(vector::contains(&position_openeds, &position_addr), 1);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_add_position_opened_not_sever_called(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        //-- deposit to wallet account
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer =
            wallet_account::get_wallet_account_signer(deployer, wallet_id);
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

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_add_position_opened_not_create_wallet_account(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
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

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_add_position_opened_invalid_argument(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        primary_fungible_store::deposit(signer::address_of(user), fa);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
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

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x80009, location = moneyfi::wallet_account)]
    fun test_add_position_opened_already_exists_position(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        primary_fungible_store::deposit(signer::address_of(user), fa);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
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

    // ========== REMOVE_POSITION_OPENED TESTS ==========

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_remove_position_opened_success(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer =
            wallet_account::get_wallet_account_signer(deployer, wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Create and add position
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

        // Verify position was added
        let (position_openeds, _) = wallet_account::get_position_opened(wallet_id);
        assert!(vector::contains(&position_openeds, &position_addr), 1);

        // Transfer assets back to wallet account before removing position
        primary_fungible_store::transfer(
            &position_signer,
            metadata,
            wallet_account_addr,
            5000
        );

        // Remove position
        wallet_account::remove_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            metadata,
            100
        );

        // Verify position was removed
        let (position_openeds_after, _) = wallet_account::get_position_opened(wallet_id);
        assert!(!vector::contains(&position_openeds_after, &position_addr), 2);

        // Verify balances updated correctly
        assert!(test_helpers::balance_of_token(wallet_account_addr, metadata) == 9900, 3); // 5000 - 100 fee + 5000 remaining
        let (_, wallet_balance) = get_asset_deposit_to_wallet_account(
            wallet_id, metadata
        );
        assert!(wallet_balance == 9900, 4);
        let (_, distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(distributed_balance == 0, 5);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_remove_position_opened_not_data_signer(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Try to remove position with wrong signer
        wallet_account::remove_position_opened(
            user, // Wrong signer
            wallet_id,
            position_addr,
            metadata,
            100
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60008, location = moneyfi::wallet_account)]
    fun test_remove_position_opened_position_not_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);

        // Try to remove position that doesn't exist
        wallet_account::remove_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            metadata,
            100
        );
    }

    // ========== UPGRADE_POSITION_OPENED TESTS ==========

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_upgrade_position_opened_success(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(20000),
            0
        );

        // Create and add initial position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Verify initial state
        let (_, initial_wallet_balance) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata);
        let (_, initial_distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(initial_wallet_balance == 15000, 1); // 20000 - 5000
        assert!(initial_distributed_balance == 5000, 2);

        // Upgrade position with additional assets
        wallet_account::upgrade_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(3000),
            100 // fee
        );

        // Verify updated state
        let (_, final_wallet_balance) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata);
        let (_, final_distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(final_wallet_balance == 11900, 3); // 15000 - 3000 - 100 fee
        assert!(final_distributed_balance == 8000, 4); // 5000 + 3000
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_upgrade_position_opened_not_data_signer(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Try to upgrade position with wrong signer
        wallet_account::upgrade_position_opened(
            user, // Wrong signer
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(2000),
            100
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_upgrade_position_opened_invalid_argument(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Try to upgrade with mismatched assets and amounts vectors
        let assets = vector::singleton<address>(
            object::object_address<Metadata>(&metadata)
        );
        let amounts = vector::empty<u64>();
        vector::push_back(&mut amounts, 2000);
        vector::push_back(&mut amounts, 1000); // Extra amount

        wallet_account::upgrade_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            assets,
            amounts,
            100
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60008, location = moneyfi::wallet_account)]
    fun test_upgrade_position_opened_position_not_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);

        // Try to upgrade position that doesn't exist
        wallet_account::upgrade_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(2000),
            100
        );
    }

    // ========== ADD_PROFIT_UNCLAIMED TESTS ==========

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_add_profit_unclaimed_success_with_referral(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account with referral enabled
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        let wallet_account_signer =
            wallet_account::get_wallet_account_signer(deployer, wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Simulate profit by transferring tokens to wallet account
        let profit_amount = 2000;
        primary_fungible_store::transfer(
            user,
            metadata,
            wallet_account_addr,
            profit_amount
        );

        // Add profit unclaimed
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            profit_amount,
            100 // fee
        );

        // Verify profit was added to unclaimed
        let (profit_assets, profit_amounts) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets) == 1, 1);
        assert!(
            vector::contains(
                &profit_assets, &object::object_address<Metadata>(&metadata)
            ),
            2
        );

        // Calculate expected user amount after protocol fee and withdrawal fee
        let protocol_fee = access_control::calculate_protocol_fee(profit_amount);
        let user_amount = profit_amount - protocol_fee;
        let expected_user_profit = user_amount - 100; // minus withdrawal fee

        let profit_amount_actual = *vector::borrow(&profit_amounts, 0);
        assert!(profit_amount_actual == expected_user_profit, 3);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_add_profit_unclaimed_success_without_referral(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account without referral
        wallet_account::create_wallet_account(deployer, wallet_id, 9, false);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Simulate profit
        let profit_amount = 1500;
        primary_fungible_store::transfer(
            user,
            metadata,
            wallet_account_addr,
            profit_amount
        );

        // Add profit unclaimed
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            profit_amount,
            50 // fee
        );

        // Verify profit was added correctly
        let (profit_assets, profit_amounts) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets) == 1, 1);

        let protocol_fee = access_control::calculate_protocol_fee(profit_amount);
        let user_amount = profit_amount - protocol_fee;
        let expected_user_profit = user_amount - 50; // minus withdrawal fee

        let profit_amount_actual = *vector::borrow(&profit_amounts, 0);
        assert!(profit_amount_actual == expected_user_profit, 2);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_add_profit_unclaimed_not_data_signer(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Try to add profit with wrong signer
        wallet_account::add_profit_unclaimed(
            user, // Wrong signer
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            1000,
            50
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60008, location = moneyfi::wallet_account)]
    fun test_add_profit_unclaimed_position_not_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);

        // Try to add profit for position that doesn't exist
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            1000,
            50
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_add_profit_unclaimed_multiple_calls(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                30000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, false);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Add profit multiple times
        let profit1 = 1000;
        let profit2 = 800;

        // Transfer profits to wallet account
        primary_fungible_store::transfer(user, metadata, wallet_account_addr, profit1);
        primary_fungible_store::transfer(user, metadata, wallet_account_addr, profit2);

        // Add first profit
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            profit1,
            25
        );

        // Add second profit
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            profit2,
            20
        );

        // Verify accumulated profit
        let (profit_assets, profit_amounts) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets) == 1, 1);

        let protocol_fee1 = access_control::calculate_protocol_fee(profit1);
        let protocol_fee2 = access_control::calculate_protocol_fee(profit2);
        let user_amount1 = profit1 - protocol_fee1 - 25;
        let user_amount2 = profit2 - protocol_fee2 - 20;
        let expected_total = user_amount1 + user_amount2;

        let actual_profit = *vector::borrow(&profit_amounts, 0);
        assert!(actual_profit == expected_total, 2);
    }

    // ========== CLAIM_REWARDS TESTS ==========

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_claim_rewards_success(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Simulate profit by transferring tokens to wallet account
        let profit_amount = 2000;
        primary_fungible_store::transfer(
            user,
            metadata,
            wallet_account_addr,
            profit_amount
        );

        // Add profit unclaimed
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            profit_amount,
            50 // fee
        );

        // Verify profit was added
        let (profit_assets_before, profit_amounts_before) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_before) == 1, 1);

        // Get user balance before claiming
        let user_balance_before =
            primary_fungible_store::balance(signer::address_of(user), metadata);

        // Claim all rewards
        wallet_account::claim_rewards(user, wallet_id);

        // Verify rewards were claimed
        let user_balance_after =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        let claimed_amount = *vector::borrow(&profit_amounts_before, 0);
        assert!(
            user_balance_after - user_balance_before == claimed_amount,
            2
        );

        // Verify all profit unclaimed was cleared
        let (profit_assets_after, _) = wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after) == 0, 3);

        // Verify total profit claimed was updated
        let (_, total_claimed) = get_total_profit_claimed_by_metadata(
            wallet_id, metadata
        );
        assert!(total_claimed == claimed_amount, 4);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_claim_rewards_multiple_assets(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa1, metadata1) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        primary_fungible_store::deposit(signer::address_of(user), fa1);

        // Create second token
        let fa2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let metadata2 = fungible_asset::metadata_from_asset(&fa2);
        primary_fungible_store::deposit(signer::address_of(user), fa2);

        let wallet_id = get_test_wallet_id(signer::address_of(user));

        // Create wallet account and deposit both tokens
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);

        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, metadata1);
        vector::push_back(&mut assets, metadata2);

        let amounts = vector::empty<u64>();
        vector::push_back(&mut amounts, 10000);
        vector::push_back(&mut amounts, 9000);

        wallet_account::deposit_to_wallet_account(user, wallet_id, assets, amounts, 0);

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);

        let position_assets = vector::empty<address>();
        vector::push_back(
            &mut position_assets, object::object_address<Metadata>(&metadata1)
        );
        vector::push_back(
            &mut position_assets, object::object_address<Metadata>(&metadata2)
        );

        let position_amounts = vector::empty<u64>();
        vector::push_back(&mut position_amounts, 5000);
        vector::push_back(&mut position_amounts, 5000);

        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            position_assets,
            position_amounts,
            1,
            0
        );

        // Add profits for both tokens
        primary_fungible_store::transfer(user, metadata1, wallet_account_addr, 1000);
        primary_fungible_store::transfer(user, metadata2, wallet_account_addr, 800);

        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata1),
            1000,
            50
        );

        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata2),
            800,
            40
        );

        // Get profit amounts before claiming
        let (profit_assets, profit_amounts) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets) == 2, 1);

        // Get user balances before claiming
        let user_balance1_before =
            primary_fungible_store::balance(signer::address_of(user), metadata1);
        let user_balance2_before =
            primary_fungible_store::balance(signer::address_of(user), metadata2);

        // Claim all rewards
        wallet_account::claim_rewards(user, wallet_id);

        // Verify both rewards were claimed
        let user_balance1_after =
            primary_fungible_store::balance(signer::address_of(user), metadata1);
        let user_balance2_after =
            primary_fungible_store::balance(signer::address_of(user), metadata2);

        let (_, metadata1_index) = vector::index_of(
            &profit_assets, &object::object_address<Metadata>(&metadata1)
        );
        let (_, metadata2_index) = vector::index_of(
            &profit_assets, &object::object_address<Metadata>(&metadata2)
        );

        assert!(
            user_balance1_after - user_balance1_before
                == *vector::borrow(&profit_amounts, metadata1_index),
            2
        );
        assert!(
            user_balance2_after - user_balance2_before
                == *vector::borrow(&profit_amounts, metadata2_index),
            3
        );

        // Verify all profits were claimed
        let (profit_assets_after, _) = wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after) == 0, 4);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_claim_rewards_with_zero_amounts(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa1, metadata1) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        primary_fungible_store::deposit(signer::address_of(user), fa1);

        // Create second token
        let fa2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let metadata2 = fungible_asset::metadata_from_asset(&fa2);
        primary_fungible_store::deposit(signer::address_of(user), fa2);

        let wallet_id = get_test_wallet_id(signer::address_of(user));

        // Create wallet account and deposit both tokens
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);

        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, metadata1);
        vector::push_back(&mut assets, metadata2);

        let amounts = vector::empty<u64>();
        vector::push_back(&mut amounts, 10000);
        vector::push_back(&mut amounts, 10000);

        wallet_account::deposit_to_wallet_account(user, wallet_id, assets, amounts, 0);

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);

        let position_assets = vector::empty<address>();
        vector::push_back(
            &mut position_assets, object::object_address<Metadata>(&metadata1)
        );
        vector::push_back(
            &mut position_assets, object::object_address<Metadata>(&metadata2)
        );

        let position_amounts = vector::empty<u64>();
        vector::push_back(&mut position_amounts, 5000);
        vector::push_back(&mut position_amounts, 5000);

        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            position_assets,
            position_amounts,
            1,
            0
        );

        // Add profit for only one token (metadata1), metadata2 will have 0 profit
        primary_fungible_store::transfer(user, metadata1, wallet_account_addr, 1000);

        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata1),
            1000,
            50
        );

        // Manually add zero profit for metadata2 to test zero amount handling
        // This simulates a scenario where one asset has profit and another doesn't

        // Get user balances before claiming
        let user_balance1_before =
            primary_fungible_store::balance(signer::address_of(user), metadata1);
        let user_balance2_before =
            primary_fungible_store::balance(signer::address_of(user), metadata2);

        // Claim all rewards
        wallet_account::claim_rewards(user, wallet_id);

        // Verify only non-zero rewards were claimed
        let user_balance1_after =
            primary_fungible_store::balance(signer::address_of(user), metadata1);
        let user_balance2_after =
            primary_fungible_store::balance(signer::address_of(user), metadata2);

        // metadata1 should have increased balance
        assert!(user_balance1_after > user_balance1_before, 1);
        // metadata2 should have same balance (no profit to claim)
        assert!(user_balance2_after == user_balance2_before, 2);

        // Verify all profits were cleared
        let (profit_assets_after, _) = wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after) == 0, 3);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_claim_rewards_no_profit_available(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Get user balance before claiming
        let user_balance_before =
            primary_fungible_store::balance(signer::address_of(user), metadata);

        // Claim rewards when no profit is available
        wallet_account::claim_rewards(user, wallet_id);

        // Verify no change in balance
        let user_balance_after =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        assert!(user_balance_after == user_balance_before, 1);

        // Verify profit unclaimed is still empty
        let (profit_assets_after, _) = wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after) == 0, 2);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_claim_rewards_auto_connect_wallet(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Add profit
        let profit_amount = 1500;
        primary_fungible_store::transfer(
            user,
            metadata,
            wallet_account_addr,
            profit_amount
        );
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            profit_amount,
            75
        );

        // Verify user is not connected initially (if there's a way to check this)
        // Note: This test assumes the wallet connection logic works as intended

        // Get user balance before claiming
        let user_balance_before =
            primary_fungible_store::balance(signer::address_of(user), metadata);

        // Claim rewards - this should auto-connect the wallet if not connected
        wallet_account::claim_rewards(user, wallet_id);

        // Verify rewards were claimed successfully
        let user_balance_after =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        assert!(user_balance_after > user_balance_before, 1);

        // Verify profit was cleared
        let (profit_assets_after, _) = wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after) == 0, 2);
    }

    #[test(
        deployer = @moneyfi, user1 = @0xab, user2 = @0xac, aptos_framework = @0x1
    )]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_claim_rewards_not_owner(
        deployer: &signer,
        user1: &signer,
        user2: &signer,
        aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user1));
        primary_fungible_store::deposit(signer::address_of(user1), fa);

        // Create wallet account for user1
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user1,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(10000),
            0
        );

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(5000),
            1,
            0
        );

        // Add profit
        primary_fungible_store::transfer(user1, metadata, wallet_account_addr, 1000);
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            1000,
            50
        );

        // Try to claim rewards with wrong user (user2 instead of user1)
        wallet_account::claim_rewards(user2, wallet_id); // Wrong user
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_claim_rewards_wallet_not_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                10000
            );
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Use wallet_id that doesn't exist
        let wallet_id = get_test_wallet_id(signer::address_of(user));

        // Try to claim rewards from non-existent wallet
        wallet_account::claim_rewards(user, wallet_id);
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_claim_rewards_multiple_claims(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                30000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(15000),
            0
        );

        // Create and add position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(10000),
            1,
            0
        );

        // Add first profit and claim
        primary_fungible_store::transfer(user, metadata, wallet_account_addr, 1000);
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            1000,
            50
        );

        let user_balance_before_first =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        wallet_account::claim_rewards(user, wallet_id);
        let user_balance_after_first =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        let first_claim_amount = user_balance_after_first - user_balance_before_first;

        // Verify first claim worked
        assert!(first_claim_amount > 0, 1);
        let (profit_assets_after_first, _) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after_first) == 0, 2);

        // Add second profit and claim
        primary_fungible_store::transfer(user, metadata, wallet_account_addr, 800);
        wallet_account::add_profit_unclaimed(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            object::object_address<Metadata>(&metadata),
            800,
            40
        );

        let user_balance_before_second =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        wallet_account::claim_rewards(user, wallet_id);
        let user_balance_after_second =
            primary_fungible_store::balance(signer::address_of(user), metadata);
        let second_claim_amount = user_balance_after_second
            - user_balance_before_second;

        // Verify second claim worked
        assert!(second_claim_amount > 0, 3);
        let (profit_assets_after_second, _) =
            wallet_account::get_profit_unclaimed(wallet_id);
        assert!(vector::length(&profit_assets_after_second) == 0, 4);

        // Verify total profit claimed is cumulative
        let (_, total_claimed) = get_total_profit_claimed_by_metadata(
            wallet_id, metadata
        );
        assert!(
            total_claimed == first_claim_amount + second_claim_amount,
            5
        );
    }

    // ========== UPDATE_POSITION_AFTER_PARTIAL_REMOVAL TESTS ==========

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_update_position_after_partial_removal_success(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(20000),
            0
        );

        // Create and add initial position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(10000),
            1,
            0
        );

        // Verify initial state
        let (_, initial_wallet_balance) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata);
        let (_, initial_distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(initial_wallet_balance == 10000, 1); // 20000 - 10000
        assert!(initial_distributed_balance == 10000, 2);

        // Update position after partial removal
        let removal_amount = 3000;
        let fee_amount = 50;
        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(removal_amount),
            vector::singleton<u64>(7000),
            fee_amount
        );

        // Verify updated state
        let (_, final_wallet_balance) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata);
        let (_, final_distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(final_wallet_balance == 13000 - fee_amount, 3); // 10000 + 3000 - fee
        assert!(final_distributed_balance == 7000, 4); // 10000 - 3000
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_update_position_after_partial_removal_multiple_assets(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa1, metadata1) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                30000
            );
        primary_fungible_store::deposit(signer::address_of(user), fa1);

        // Create second token
        let fa2 = create_token_and_add_to_supported_asset(deployer, b"token2");
        let metadata2 = fungible_asset::metadata_from_asset(&fa2);
        primary_fungible_store::deposit(signer::address_of(user), fa2);

        let wallet_id = get_test_wallet_id(signer::address_of(user));

        // Create wallet account and deposit both tokens
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);

        let assets = vector::empty<Object<Metadata>>();
        vector::push_back(&mut assets, metadata1);
        vector::push_back(&mut assets, metadata2);

        let amounts = vector::empty<u64>();
        vector::push_back(&mut amounts, 15000);
        vector::push_back(&mut amounts, 10000);

        wallet_account::deposit_to_wallet_account(user, wallet_id, assets, amounts, 0);

        // Create and add position with both assets
        let (position_addr, _) = get_position(wallet_account_addr);

        let position_assets = vector::empty<address>();
        vector::push_back(
            &mut position_assets, object::object_address<Metadata>(&metadata1)
        );
        vector::push_back(
            &mut position_assets, object::object_address<Metadata>(&metadata2)
        );

        let position_amounts = vector::empty<u64>();
        vector::push_back(&mut position_amounts, 8000);
        vector::push_back(&mut position_amounts, 6000);

        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            position_assets,
            position_amounts,
            1,
            0
        );

        // Verify initial state
        let (_, initial_wallet_balance1) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata1);
        let (_, initial_distributed_balance1) =
            get_asset_distribute_wallet_account(wallet_id, metadata1);
        let (_, initial_wallet_balance2) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata2);
        let (_, initial_distributed_balance2) =
            get_asset_distribute_wallet_account(wallet_id, metadata2);

        assert!(initial_wallet_balance1 == 7000, 1); // 15000 - 8000
        assert!(initial_distributed_balance1 == 8000, 2);
        assert!(initial_wallet_balance2 == 4000, 3); // 10000 - 6000
        assert!(initial_distributed_balance2 == 6000, 4);

        // Update position after partial removal of both assets
        let removal_amounts = vector::empty<u64>();
        vector::push_back(&mut removal_amounts, 2000); // Remove 2000 from metadata1
        vector::push_back(&mut removal_amounts, 1500); // Remove 1500 from metadata2
        let amounts_after = vector::empty<u64>();
        vector::push_back(&mut amounts_after, 6000);
        vector::push_back(&mut amounts_after, 4500);
        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            position_assets,
            removal_amounts,
            amounts_after,
            100 // fee
        );

        // Verify updated state
        let (_, final_wallet_balance1) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata1);
        let (_, final_distributed_balance1) =
            get_asset_distribute_wallet_account(wallet_id, metadata1);
        let (_, final_wallet_balance2) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata2);
        let (_, final_distributed_balance2) =
            get_asset_distribute_wallet_account(wallet_id, metadata2);

        assert!(final_wallet_balance1 == 8900, 5); // 7000 + 2000 - 100 fee
        assert!(final_distributed_balance1 == 6000, 6); // 8000 - 2000
        assert!(final_wallet_balance2 == 5500, 7); // 6000 + 1500 (no fee for second asset)
        assert!(final_distributed_balance2 == 4500, 8); // 6000 - 1500
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x50004, location = moneyfi::wallet_account)]
    fun test_update_position_after_partial_removal_not_data_signer(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                15000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(15000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(8000),
            1,
            0
        );

        // Try to update position with wrong signer
        wallet_account::update_position_after_partial_removal(
            user, // Wrong signer
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(2000),
            vector::singleton<u64>(6000),
            50
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x10007, location = moneyfi::wallet_account)]
    fun test_update_position_after_partial_removal_invalid_argument(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                15000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(15000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(8000),
            1,
            0
        );

        // Try to update with mismatched assets and amounts vectors
        let assets = vector::singleton<address>(
            object::object_address<Metadata>(&metadata)
        );
        let amounts = vector::empty<u64>();
        vector::push_back(&mut amounts, 2000);
        vector::push_back(&mut amounts, 1000); // Extra amount

        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            assets,
            amounts,
            vector::singleton<u64>(7000),
            50
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60008, location = moneyfi::wallet_account)]
    fun test_update_position_after_partial_removal_position_not_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                15000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(15000),
            0
        );

        let (position_addr, _) = get_position(wallet_account_addr);

        // Try to update position that doesn't exist
        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(2000),
            vector::singleton<u64>(7000),
            50
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = moneyfi::wallet_account)]
    fun test_update_position_after_partial_removal_wallet_not_exists(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                15000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Don't create wallet account
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        let (position_addr, _) = get_position(wallet_account_addr);

        // Try to update position on non-existent wallet
        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(2000),
            vector::singleton<u64>(7000),
            50
        );
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_update_position_after_partial_removal_full_amount(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                20000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(20000),
            0
        );

        // Create and add initial position
        let (position_addr, _) = get_position(wallet_account_addr);
        let position_amount = 8000;
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(position_amount),
            1,
            0
        );

        // Update position by removing the full amount
        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(position_amount),
            vector::singleton<u64>(0), // Remove full amount
            100 // fee
        );

        // Verify final state
        let (_, final_wallet_balance) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata);
        let (_, final_distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(
            final_wallet_balance == 20000 - 100,
            final_wallet_balance
        ); // All back to wallet minus fee
        assert!(final_distributed_balance == 0, 2); // No distributed assets left
    }

    #[test(deployer = @moneyfi, user = @0xab, aptos_framework = @0x1)]
    fun test_update_position_after_partial_removal_with_high_fee(
        deployer: &signer, user: &signer, aptos_framework: &signer
    ) {
        let (fa, metadata) =
            setup_for_test(
                deployer,
                signer::address_of(deployer),
                aptos_framework,
                25000
            );
        let wallet_id = get_test_wallet_id(signer::address_of(user));
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Create wallet account and deposit
        wallet_account::create_wallet_account(deployer, wallet_id, 9, true);
        let wallet_account_addr =
            wallet_account::get_wallet_account_object_address(wallet_id);
        wallet_account::deposit_to_wallet_account(
            user,
            wallet_id,
            vector::singleton<Object<Metadata>>(metadata),
            vector::singleton<u64>(25000),
            0
        );

        // Create and add initial position
        let (position_addr, _) = get_position(wallet_account_addr);
        wallet_account::add_position_opened(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(15000),
            1,
            0
        );

        // Update position with high fee
        let removal_amount = 5000;
        let high_fee = 1000;
        wallet_account::update_position_after_partial_removal(
            &access_control::get_object_data_signer(),
            wallet_id,
            position_addr,
            vector::singleton<address>(object::object_address<Metadata>(&metadata)),
            vector::singleton<u64>(removal_amount),
            vector::singleton<u64>(10000),
            high_fee
        );

        // Verify state with high fee deduction
        let (_, final_wallet_balance) =
            get_asset_deposit_to_wallet_account(wallet_id, metadata);
        let (_, final_distributed_balance) =
            get_asset_distribute_wallet_account(wallet_id, metadata);
        assert!(
            final_wallet_balance == 10000 + removal_amount - high_fee,
            1
        ); // 10000 + 5000 - 1000
        assert!(
            final_distributed_balance == 15000 - removal_amount,
            2
        ); // 15000 - 5000
    }
}

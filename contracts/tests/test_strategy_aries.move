module moneyfi::strategy_aries_test {
    use std::signer;
    use std::debug;
    use std::error;
    use aptos_std::table;
    use aptos_std::any;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        Metadata,
        MintRef,
        BurnRef,
        TransferRef
    };

    use moneyfi::wallet_account;
    use moneyfi::strategy_aries::{Self, get_vault_data};
    use moneyfi::vault;
    use moneyfi::storage;
    use moneyfi::access_control;
    use moneyfi::test_helpers;

    struct TestContext has drop {
        wallet1_id: vector<u8>,
        vault_name: String,
        usdc: Object<Metadata>,
        usdc_mint_ref: MintRef,
        usdc_burn_ref: BurnRef,
        usdc_transfer_ref: TransferRef,
        usdt: Object<Metadata>,
        usdt_mint_ref: MintRef,
        usdt_burn_ref: BurnRef,
        usdt_transfer_ref: TransferRef
    }

    fun setup(
        deployer: &signer, aries_deployer: &signer, wallet1: &signer
    ): TestContext {
        // setup clock
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );

        aries::mock::init(aries_deployer);

        // setup modules
        storage::init_module_for_testing(deployer);
        access_control::init_module_for_testing(deployer);
        vault::init_module_for_testing(deployer);
        strategy_aries::init_module_for_testing(deployer);

        // setup acccounts
        let deployer_addr = signer::address_of(deployer);
        let wallet1_addr = signer::address_of(wallet1);
        account::create_account_for_test(deployer_addr);
        account::create_account_for_test(wallet1_addr);

        access_control::upsert_account(deployer, deployer_addr, vector[1, 3, 4]);

        // setup asset
        let (usdc, usdc_mint_ref, usdc_transfer_ref, usdc_burn_ref) =
            test_helpers::create_fake_USDC(deployer);
        let (usdt, usdt_mint_ref, usdt_transfer_ref, usdt_burn_ref) =
            test_helpers::create_fake_USDT(deployer);
        vault::upsert_supported_asset(deployer, usdc, true, 0, 0, 0, 0, 1000);
        vault::upsert_supported_asset(deployer, usdt, true, 0, 0, 0, 0, 1000);

        let init_amount = 1_000_000_000; // 1000 USDC
        primary_fungible_store::mint(&usdc_mint_ref, wallet1_addr, init_amount);
        primary_fungible_store::mint(&usdt_mint_ref, wallet1_addr, init_amount);

        let wallet1_id = b"wallet1";
        wallet_account::create_wallet_account_for_test(wallet1, wallet1_id, 0, vector[]);
        let deposit_amount = 10_000_000;
        vault::deposit(wallet1, usdt, deposit_amount);

        TestContext {
            usdc,
            usdc_mint_ref,
            usdc_burn_ref,
            usdc_transfer_ref,
            usdt,
            usdt_mint_ref,
            usdt_burn_ref,
            usdt_transfer_ref,
            wallet1_id,
            vault_name: string::utf8(b"")
        }
    }

    fun test_create_vault(self: &mut TestContext, sender: &signer) {
        aries::mock::on(b"profile::profile_exists", false, 1);
        aries::mock::on(b"profile::is_registered", false, 1);
        aries::mock::on(b"profile::get_profile_address", @0xabc, 1000);

        let name = string::utf8(b"vault_usdt_usdc");
        strategy_aries::create_vault(sender, name, self.usdt, self.usdc);

        let (addr, vault) = strategy_aries::get_vault(name);
        assert!(addr == @0xabc);
        assert!(get_vault_data<String>(&vault, b"name") == name);

        self.vault_name = name;
    }

    fun test_deposit(self: &mut TestContext, sender: &signer) {
        strategy_aries::deposit(
            sender,
            self.vault_name,
            self.wallet1_id,
            5_000_000
        );

        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 5_000_000);
        assert!(deposited == 0);
        assert!(withdrawable == 0);

        let account1_addr =
            wallet_account::get_wallet_account_object_address(self.wallet1_id);
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(
            get_vault_data<OrderedMap<address, u64>>(&vault, b"pending_amount")
                == ordered_map::new_from(vector[account1_addr], vector[5_000_000])
        );
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 5_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_deposited_amount") == 5_000_000);
    }

    fun test_withdraw_pending_amount(
        self: &mut TestContext, sender: &signer
    ) {
        strategy_aries::withdraw(
            sender,
            self.vault_name,
            self.wallet1_id,
            1_000_000,
            0
        );

        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 4_000_000);
        assert!(deposited == 0);
        assert!(withdrawable == 0);

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 4_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_withdrawn_amount") == 1_000_000);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 4_000_000);
        assert!(deposited == 0);
        assert!(withdrawable == 0);

        // assert wallet account state
        let account_asset =
            wallet_account::get_wallet_account_asset(self.wallet1_id, self.usdt);
        assert!(
            wallet_account::get_account_asset_data<u64>(
                &account_asset, b"distributed_amount"
            ) == 4_000_000
        );
        assert!(
            wallet_account::get_account_asset_data<u64>(
                &account_asset, b"interest_amount"
            ) == 0
        );
    }

    fun test_vault_deposit(self: &mut TestContext, sender: &signer) {
        // before deposit
        aries::mock::on(b"profile::get_deposited_amount", 0, 3);
        aries::mock::on(b"reserve::get_lp_amount_from_underlying_amount", 0, 4);
        // after deposit
        aries::mock::on(b"profile::get_deposited_amount", 100, 1000); // 100 shares
        aries::mock::on(b"reserve::get_lp_amount_from_underlying_amount", 100, 1000);
        aries::mock::on(
            b"reserve::get_underlying_amount_from_lp_amount", 1_000_001, 1000
        );
        aries::mock::on(
            b"controller::deposit_fa", object::object_address(&self.usdt), 1
        );

        strategy_aries::vault_deposit(sender, self.vault_name, 1_000_000);

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 3_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 100_0000_0000);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 3_000_000);
        assert!(deposited == 1_000_000);
        assert!(withdrawable == 1_000_001);
    }

    fun test_withdraw_mix(self: &mut TestContext, sender: &signer) {
        let strategy_addr = strategy_aries::get_strategy_address();
        let ref = object::create_object(strategy_addr);
        let store = fungible_asset::create_store(&ref, self.usdt);
        fungible_asset::mint_to(&self.usdt_mint_ref, store, 1_000_000);
        aries::mock::on(
            b"controller::withdraw_fa:store", object::object_address(&store), 1
        );
        aries::mock::on(
            b"controller::withdraw_fa:asset", object::object_address(&self.usdt), 1
        );
        aries::mock::reset(b"profile::get_deposited_amount");
        aries::mock::reset(b"get_underlying_amount_from_lp_amount");
        // before withdraw
        aries::mock::on(b"profile::get_deposited_amount", 100, 4);
        // after withdraw
        aries::mock::on(b"profile::get_deposited_amount", 51, 100);

        strategy_aries::withdraw(
            sender,
            self.vault_name,
            self.wallet1_id,
            3_500_000,
            0
        );

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 0);
        assert!(get_vault_data<u128>(&vault, b"total_withdrawn_amount") == 4_500_000);

        // assert account state
        let account_data =
            wallet_account::get_strategy_data<strategy_aries::AccountData>(
                &wallet_account::get_wallet_account(self.wallet1_id)
            );
        debug::print(&account_data);

        let (pending, deposited, _) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 0);
        assert!(deposited == 510_000);

        // assert wallet account state
        let account_asset =
            wallet_account::get_wallet_account_asset(self.wallet1_id, self.usdt);
        assert!(
            wallet_account::get_account_asset_data<u64>(
                &account_asset, b"distributed_amount"
            ) == 510_000
        );
        assert!(
            wallet_account::get_account_asset_data<u64>(
                &account_asset, b"interest_amount"
            ) == 10_000
        );
    }

    fun test_borrow_and_deposit(self: &mut TestContext, sender: &signer) {
        let strategy_addr = strategy_aries::get_strategy_address();
        let ref = object::create_object(strategy_addr);
        let store = fungible_asset::create_store(&ref, self.usdc);
        fungible_asset::mint_to(&self.usdc_mint_ref, store, 1_000_000);
        aries::mock::reset(b"controller::withdraw_fa:store");
        aries::mock::reset(b"controller::withdraw_fa:asset");
        aries::mock::on(
            b"controller::withdraw_fa:store", object::object_address(&store), 1
        );
        aries::mock::on(
            b"controller::withdraw_fa:asset", object::object_address(&self.usdc), 1
        );
        aries::mock::on(b"profile::max_borrow_amount", 200_000, 10);
        // mock hyperion swap
        let ref = object::create_object(strategy_addr);
        let usdt_store = fungible_asset::create_store(&ref, self.usdt);
        fungible_asset::mint_to(&self.usdt_mint_ref, usdt_store, 1_000_000);
        aries::mock::on(
            b"router_v3::exact_input_swap_entry",
            object::object_address(&usdt_store),
            1
        );
        aries::mock::on(
            b"controller::deposit_fa", object::object_address(&self.usdt), 1
        );
        aries::mock::reset(b"profile::get_deposited_amount");
        // before deposit
        aries::mock::on(b"profile::get_deposited_amount", 51, 2);
        // after deposit
        aries::mock::on(b"profile::get_deposited_amount", 60, 10);

        let max_borrow_amount = strategy_aries::get_max_borrow_amount(self.vault_name);
        debug::print(&string::utf8(b"max_borrow_amount"));
        debug::print(&max_borrow_amount);
        assert!(max_borrow_amount < 200_000);

        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 5_100_000_000);
        assert!(get_vault_data<u128>(&vault, b"owned_shares") == 0);

        strategy_aries::borrow_and_deposit(sender, self.vault_name, 150_000);

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 6_000_000_000);
        assert!(get_vault_data<u128>(&vault, b"owned_shares") == 900_000_000);
    }

    fun test_withdraw_trigger_repay(
        self: &mut TestContext, sender: &signer
    ) {
        let strategy_addr = strategy_aries::get_strategy_address();
        let ref = object::create_object(strategy_addr);
        let store = fungible_asset::create_store(&ref, self.usdt);
        fungible_asset::mint_to(&self.usdt_mint_ref, store, 10_000_000);
        // withdraw: 2 for repay, 1 for withdraw
        aries::mock::on(
            b"controller::withdraw_fa:store", object::object_address(&store), 3
        );
        aries::mock::on(
            b"controller::withdraw_fa:asset", object::object_address(&self.usdt), 3
        );
        aries::mock::reset(b"profile::get_deposited_amount");
        aries::mock::reset(b"reserve::get_underlying_amount_from_lp_amount");
        aries::mock::reset(b"reserve::get_lp_amount_from_underlying_amount");
        // before withdraw
        aries::mock::on(b"profile::get_deposited_amount", 60, 4);
        aries::mock::on(b"profile::get_deposited_amount", 54, 1); // after repay 1st
        aries::mock::on(b"profile::get_deposited_amount", 50, 2); // after repay 2 times
        aries::mock::on(
            b"profile::profile_loan",
            vector<u128>[120, aries::decimal::raw(aries::decimal::from_u128(151_000))],
            6
        );
        // after repay first time
        aries::mock::on(
            b"profile::profile_loan",
            vector<u128>[10, aries::decimal::raw(aries::decimal::from_u128(16675))],
            3
        );
        // after repay 2 times
        aries::mock::on(
            b"profile::profile_loan",
            vector<u128>[0, aries::decimal::raw(aries::decimal::from_u128(0))],
            10
        );
        aries::mock::on(b"reserve::get_lp_amount_from_underlying_amount", 6, 1); // get shares from withdraw amount when repay 1st
        aries::mock::on(b"reserve::get_lp_amount_from_underlying_amount", 3, 1); // get shares from withdraw amount when repay 2st
        aries::mock::on(b"reserve::get_lp_amount_from_underlying_amount", 51, 1); // get shares from withdraw amount

        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 600_000, 1); // get_deposited_amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 90_000, 1); // get owned deposited amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 600_000, 1); // get_deposited_amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 510_000, 1); // get acc_deposit_amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 600_000, 1); // get_deposited_amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 90_000, 1); // get owned deposited amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 600_000, 1); // get_deposited_amount
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 540_000, 1); // after repay 1st
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 500_000, 1); // after repay 2nd
        // aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 2000, 1); // compouand again
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 0, 1);
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 500_000, 1);
        aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 0, 1);
        // aries::mock::on(b"reserve::get_underlying_amount_from_lp_amount", 500_000, );

        aries::mock::on(b"reserve::get_borrow_amount_from_share_dec", 152_000 as u128, 1);
        aries::mock::on(b"profile::available_borrowing_power", 150000, 2); // before repay 1st
        aries::mock::on(b"profile::available_borrowing_power", 152000, 1); // after repay 1st

        let ref = object::create_object(strategy_addr);
        let usdc_store = fungible_asset::create_store(&ref, self.usdc);
        fungible_asset::mint_to(&self.usdc_mint_ref, usdc_store, 1_000_000);
        aries::mock::on(
            b"router_v3::exact_input_swap_entry",
            object::object_address(&usdc_store),
            2 // repay 2 times
        );
        // repay
        aries::mock::on(
            b"controller::deposit_fa", object::object_address(&self.usdc), 2
        );
        // recompound
        aries::mock::on(
            b"controller::deposit_fa", object::object_address(&self.usdt), 1
        );
        // after withdraw
        aries::mock::on(b"profile::get_deposited_amount", 0, 1);

        // let (_, vault) = strategy_aries::get_vault(self.vault_name);
        // debug::print(&vault);
        strategy_aries::withdraw(
            sender,
            self.vault_name,
            self.wallet1_id,
            600_000,
            0
        );

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        debug::print(&vault);
        assert!(get_vault_data<u128>(&vault, b"owned_shares") == 0);
        assert!(get_vault_data<u64>(&vault, b"available_borrow_amount") == 0);
        assert!(get_vault_data<u128>(&vault, b"total_withdrawn_amount") == 5000000);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 0);

        // assert account state
        let account_data =
            wallet_account::get_strategy_data<strategy_aries::AccountData>(
                &wallet_account::get_wallet_account(self.wallet1_id)
            );
        debug::print(&account_data);

        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 0);
        assert!(deposited == 0);
        assert!(withdrawable == 0);
    }

    #[test(deployer = @moneyfi, aries_deployer = @aries, wallet1 = @0x111)]
    fun test_all(
        deployer: &signer, aries_deployer: &signer, wallet1: &signer
    ) {
        let ctx = setup(deployer, aries_deployer, wallet1);

        debug::print(&string::utf8(b"--------------- test_create_vault"));
        ctx.test_create_vault(deployer);
        debug::print(&string::utf8(b"--------------- test_deposit"));
        ctx.test_deposit(deployer);
        debug::print(&string::utf8(b"--------------- test_withdraw_pending_amount"));
        ctx.test_withdraw_pending_amount(deployer);
        debug::print(&string::utf8(b"--------------- test_vault_deposit"));
        ctx.test_vault_deposit(deployer);
        debug::print(&string::utf8(b"--------------- test_withdraw_mix"));
        ctx.test_withdraw_mix(deployer);
        debug::print(&string::utf8(b"--------------- test_borrow_and_deposit"));
        ctx.test_borrow_and_deposit(deployer);
        debug::print(&string::utf8(b"--------------- test_withdraw_trigger_repay"));
        ctx.test_withdraw_trigger_repay(deployer);
    }
}

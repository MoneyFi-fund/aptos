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

    fun test_create_vault(
        self: &mut TestContext, sender: &signer, wallet1: &signer
    ) {
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
            self.usdt,
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
            self.usdt,
            1_000_000,
            0,
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
        debug::print(&vault);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 3_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 100_0000_0000);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 3_000_000);
        assert!(deposited == 1_000_000);
        assert!(withdrawable == 1_000_001);
    }

    #[test(deployer = @moneyfi, aries_deployer = @aries, wallet1 = @0x111)]
    fun test_all(
        deployer: &signer, aries_deployer: &signer, wallet1: &signer
    ) {
        let ctx = setup(deployer, aries_deployer, wallet1);

        ctx.test_create_vault(deployer, wallet1);
        ctx.test_deposit(deployer);
        ctx.test_withdraw_pending_amount(deployer);
        ctx.test_vault_deposit(deployer);
    }
}

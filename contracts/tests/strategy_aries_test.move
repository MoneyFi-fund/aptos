module moneyfi::strategy_aries_test {
    use std::signer;
    use std::debug;
    use std::error;
    use aptos_std::table;
    use aptos_std::any;
    use aptos_std::math64;
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin;
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
        wallet2_id: vector<u8>,
        vault_name: String,
        vault_address: address,
        usdc: Object<Metadata>,
        usdc_mint_ref: MintRef,
        usdc_burn_ref: BurnRef,
        usdc_transfer_ref: TransferRef,
        usdt: Object<Metadata>,
        usdt_mint_ref: MintRef,
        usdt_burn_ref: BurnRef,
        usdt_transfer_ref: TransferRef,
        strategy_addr: address,
        usdt_secondary_store: address,
        usdc_secondary_store: address,
        apt_secondary_store: address
    }

    fun setup(
        deployer: &signer,
        aries_deployer: &signer,
        wallet1: &signer,
        wallet2: &signer
    ): TestContext {
        let framework_signer = &account::create_signer_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(framework_signer);
        aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();

        aries::mock::init(aries_deployer);

        // setup modules
        storage::init_module_for_testing(deployer);
        access_control::init_module_for_testing(deployer);
        vault::init_module_for_testing(deployer);
        strategy_aries::init_module_for_testing(deployer);

        // setup acccounts
        let deployer_addr = signer::address_of(deployer);
        let wallet1_addr = signer::address_of(wallet1);
        let wallet2_addr = signer::address_of(wallet2);
        account::create_account_for_test(deployer_addr);
        account::create_account_for_test(wallet1_addr);
        account::create_account_for_test(wallet2_addr);

        access_control::upsert_account(deployer, deployer_addr, vector[1, 3, 4]);

        // setup asset
        let (usdc, usdc_mint_ref, usdc_transfer_ref, usdc_burn_ref) =
            test_helpers::create_fake_USDC(deployer);
        let (usdt, usdt_mint_ref, usdt_transfer_ref, usdt_burn_ref) =
            test_helpers::create_fake_USDT(deployer);
        vault::upsert_supported_asset(deployer, usdc, true, 0, 0, 0, 0, 1000);
        vault::upsert_supported_asset(deployer, usdt, true, 0, 0, 0, 0, 1000);

        let init_amount = 1_000_000_000; // 1000 USDT
        primary_fungible_store::mint(&usdt_mint_ref, wallet1_addr, init_amount);
        primary_fungible_store::mint(&usdt_mint_ref, wallet2_addr, init_amount);

        let wallet1_id = b"wallet1";
        let wallet2_id = b"wallet2";
        wallet_account::create_wallet_account_for_test(wallet1, wallet1_id, 0, vector[]);
        wallet_account::create_wallet_account_for_test(wallet2, wallet2_id, 0, vector[]);
        let deposit_amount = 10_000_000;
        vault::deposit(wallet1, usdt, deposit_amount);
        vault::deposit(wallet2, usdt, deposit_amount);

        let strategy_signer = &strategy_aries::get_strategy_signer_for_testing();
        let usdt_store = fungible_asset::create_test_store(strategy_signer, usdt);
        fungible_asset::mint_to(&usdt_mint_ref, usdt_store, 1_000_000_000);
        let usdc_store = fungible_asset::create_test_store(strategy_signer, usdc);
        fungible_asset::mint_to(&usdc_mint_ref, usdc_store, 1_000_000_000);
        let apt_store =
            fungible_asset::create_test_store(
                strategy_signer, object::address_to_object<Metadata>(@0xa)
            );
        let fa = aptos_coin::mint_apt_fa_for_test(1_000_0000_0000);
        fungible_asset::deposit(apt_store, fa);

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
            wallet2_id,
            vault_name: string::utf8(b""),
            vault_address: @0x0,
            strategy_addr: strategy_aries::get_strategy_address(),
            usdt_secondary_store: object::object_address(&usdt_store),
            usdc_secondary_store: object::object_address(&usdc_store),
            apt_secondary_store: object::object_address(&apt_store)
        }
    }

    fun test_create_vault(self: &mut TestContext, sender: &signer) {
        aries::mock::on(b"profile::profile_exists", false, 1);
        aries::mock::on(b"profile::is_registered", false, 1);
        aries::mock::on(b"profile::get_profile_address", @0xabc, 999);

        let name = string::utf8(b"vault_usdt_usdc");
        strategy_aries::create_vault(sender, name, self.usdt, self.usdc);

        let (addr, vault) = strategy_aries::get_vault(name);
        assert!(addr == @0xabc);
        assert!(get_vault_data<String>(&vault, b"name") == name);

        self.vault_name = name;
        self.vault_address = addr;
    }

    fun assert_pending_amount(
        self: &mut TestContext,
        vault: &strategy_aries::Vault,
        amount1: u64,
        amount2: u64
    ) {
        let want = ordered_map::new();
        if (amount1 > 0) {
            want.add(
                wallet_account::get_wallet_account_object_address(self.wallet1_id), amount1
            );
        };
        if (amount2 > 0) {
            want.add(
                wallet_account::get_wallet_account_object_address(self.wallet2_id), amount2
            );
        };
        assert!(
            get_vault_data<OrderedMap<address, u64>>(vault, b"pending_amount") == want
        );
    }

    fun test_deposit(self: &mut TestContext, sender: &signer) {
        strategy_aries::deposit(
            sender,
            self.vault_name,
            self.wallet1_id,
            5_000_000
        );
        strategy_aries::deposit(
            sender,
            self.vault_name,
            self.wallet2_id,
            10_000_000
        );

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        self.assert_pending_amount(&vault, 5_000_000, 10_000_000);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 15_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_deposited_amount") == 15_000_000);
        debug::print(&vault);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 5_000_000);
        assert!(deposited == 0);
        assert!(withdrawable == 5_000_000);

        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet2_id);
        assert!(pending == 10_000_000);
        assert!(deposited == 0);
        assert!(withdrawable == 10_000_000);
    }

    fun test_withdraw_pending_amount(
        self: &mut TestContext, sender: &signer
    ) {
        // withdraw 1 pending USDT
        strategy_aries::withdraw(
            sender,
            self.vault_name,
            self.wallet1_id,
            1_000_000,
            0
        );

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        self.assert_pending_amount(&vault, 4_000_000, 10_000_000);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 14_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_withdrawn_amount") == 1_000_000);
        debug::print(&vault);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 4_000_000);
        assert!(deposited == 0);
        assert!(withdrawable == 4_000_000);

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
        self.mock_compound_vault(
            0, 0, 0, 0
        );
        aries::mock::on(b"profile::get_deposited_amount", 0, 1);
        aries::mock::on(b"profile::get_deposited_amount", 7_000_000, 99); // after deposit
        aries::mock::on(
            b"controller::deposit_fa:asset", object::object_address(&self.usdt), 1
        );
        aries::mock::on(b"controller::deposit_fa:amount", 7_000_000, 1);

        // deposit 7 USDT to aries: 2 from wallet1, 5 from wallet2
        strategy_aries::vault_deposit(sender, self.vault_name, 7_000_000);

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        debug::print(&vault);
        self.assert_pending_amount(&vault, 2_000_000, 5_000_000);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 7_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 7_000_000_0000_0000);
        self.assert_pending_amount(&vault, 2_000_000, 5_000_000);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 2_000_000);
        assert!(deposited == 2_000_000);
        assert!(withdrawable == 4_000_000);

        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet2_id);
        assert!(pending == 5_000_000);
        assert!(deposited == 5_000_000);
        assert!(withdrawable == 10_000_000);
    }

    fun mock_withdraw_fa(
        self: &TestContext,
        asset: &Object<Metadata>,
        times: u64,
        reset: bool
    ) {
        if (reset) {
            aries::mock::reset(b"controller::withdraw_fa:store");
            aries::mock::reset(b"controller::withdraw_fa:asset");
        };
        let store_addr =
            if (asset == &self.usdt) {
                self.usdt_secondary_store
            } else {
                self.usdc_secondary_store
            };
        aries::mock::on(b"controller::withdraw_fa:store", store_addr, times);
        aries::mock::on(
            b"controller::withdraw_fa:asset", object::object_address(asset), times
        );
    }

    /// lp = amount * rate / 1000
    fun mock_exchange_deposit_shares(rate: u64) {
        aries::mock::reset(b"reserve::get_lp_amount_from_underlying_amount:rate");
        aries::mock::reset(b"reserve::get_lp_amount_from_underlying_amount");
        aries::mock::reset(b"reserve::get_underlying_amount_from_lp_amount:rate");
        aries::mock::reset(b"reserve::get_underlying_amount_from_lp_amount");

        aries::mock::on(
            b"reserve::get_lp_amount_from_underlying_amount:rate", rate, 999
        );
        aries::mock::on(
            b"reserve::get_underlying_amount_from_lp_amount:rate", rate * 1_000_000, 999
        );
    }

    fun test_withdraw_mix(self: &mut TestContext, sender: &signer) {
        aries::mock::reset(b"profile::get_deposited_amount");
        // mock_exchange_deposit_shares(999); // 999 shares => 1000 amount
        self.mock_withdraw_fa(&self.usdt, 1, true);
        self.mock_compound_vault(
            0, 0, 7_000_000, 0
        );
        // before withdraw
        aries::mock::on(b"profile::get_deposited_amount", 7_000_000, 3);
        // after withdraw
        aries::mock::on(b"profile::get_deposited_amount", 6_000_000, 99);

        // withdraw 5 pending + 1 deposited USDT
        strategy_aries::withdraw(
            sender,
            self.vault_name,
            self.wallet2_id,
            6_000_000,
            0
        );

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        debug::print(&vault);
        assert!(get_vault_data<u64>(&vault, b"available_amount") == 2_000_000);
        assert!(get_vault_data<u128>(&vault, b"total_withdrawn_amount") == 7_000_000);
        self.assert_pending_amount(&vault, 2_000_000, 0);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet2_id);
        assert!(pending == 0);
        assert!(deposited == 4_000_000);
        assert!(withdrawable == 4_000_000);

        // assert wallet account state
        let account_asset =
            wallet_account::get_wallet_account_asset(self.wallet2_id, self.usdt);
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

    fun test_borrow_and_deposit(self: &mut TestContext, sender: &signer) {
        self.mock_withdraw_fa(&self.usdc, 1, true);
        aries::mock::on(b"profile::max_borrow_amount", 3_000_000, 10);
        // mock hyperion swap
        aries::mock::on(
            b"router_v3::exact_input_swap_entry", self.usdt_secondary_store, 1
        );
        aries::mock::on(
            b"controller::deposit_fa:asset", object::object_address(&self.usdt), 1
        );
        aries::mock::reset(b"profile::get_deposited_amount");
        // before deposit
        aries::mock::on(b"profile::get_deposited_amount", 6_000_000, 1);
        // after deposit
        aries::mock::on(b"profile::get_deposited_amount", 7_990_000, 10);

        let max_borrow_amount = strategy_aries::get_max_borrow_amount(self.vault_name);
        assert!(max_borrow_amount < 3_000_000);

        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 6_000_000_0000_0000);
        assert!(get_vault_data<u128>(&vault, b"owned_shares") == 0);

        // borrow 2 USDC
        strategy_aries::borrow_and_deposit(sender, self.vault_name, 2_000_000);

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        debug::print(&vault);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == 7_990_000_0000_0000);
        assert!(get_vault_data<u128>(&vault, b"owned_shares") == 1_990_000_0000_0000);

        // assert account state
        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 2_000_000);
        assert!(deposited == 2_000_000);
        assert!(withdrawable == 4_000_000);
    }

    fun mock_compound_vault(
        self: &TestContext,
        deposit_reward: u64,
        borrow_reward: u64,
        deposited_shares: u64,
        loan_amount: u128
    ): (u64, u64) {
        aries::mock::on(
            b"profile::claimable_reward_amount_on_farming", deposit_reward, 1
        );
        aries::mock::on(
            b"profile::claimable_reward_amount_on_farming", borrow_reward, 1
        );
        aries::mock::on(
            b"controller::claim_reward_ti:store", self.apt_secondary_store, 99
        );
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        let vault_asset = get_vault_data<Object<Metadata>>(&vault, b"asset");
        // let borrow_asset = get_vault_data<Object<Metadata>>(&vault, b"borrow_asset");

        let store =
            if (object::object_address(&vault_asset) == @usdt) {
                self.usdt_secondary_store
            } else {
                self.usdc_secondary_store
            };

        let asset_amount = 0;
        if (deposit_reward > 0) {
            let amount = deposit_reward / 100 * 9900 / 10000;
            asset_amount = asset_amount + amount;
            aries::mock::on(b"controller::claim_reward_ti:amount", deposit_reward, 1);
            aries::mock::on(b"pool_v3::get_amount_out", amount, 1);
            aries::mock::on(b"router_v3::exact_input_swap_entry", store, 1);
            aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 1);
            aries::mock::on(
                b"controller::deposit_fa:asset",
                object::object_address(&vault_asset),
                1
            );
            let shares = strategy_aries::get_shares_from_amount(&vault_asset, amount);
            deposited_shares = deposited_shares + shares;
            aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 1);
        };
        if (borrow_reward > 0) {
            let amount = borrow_reward / 100 * 9900 / 10000;
            aries::mock::on(b"controller::claim_reward_ti:amount", borrow_reward, 1);
            aries::mock::on(b"pool_v3::get_amount_out", amount, 1);
            aries::mock::on(b"router_v3::exact_input_swap_entry", store, 1);
            aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 1);
            aries::mock::on(
                b"profile::profile_loan",
                vector<u128>[loan_amount, loan_amount], // just set borrow shares = loan amount, it doesnt matter
                2
            );

            let (_, owned_deposit_amount, amount_to_repay) =
                vault.get_vault_borrowing_state(deposited_shares);
            if (owned_deposit_amount < amount_to_repay) {
                aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 1);
                aries::mock::on(
                    b"controller::deposit_fa:asset",
                    object::object_address(&vault_asset),
                    2
                );
                let owned_amount =
                    math64::min(amount_to_repay - owned_deposit_amount, amount);
                let shares =
                    strategy_aries::get_shares_from_amount(&vault_asset, owned_amount);
                deposited_shares = deposited_shares + shares;
                aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 1);

                let remaining_amount = amount - owned_amount;
                if (remaining_amount > 0) {
                    aries::mock::on(
                        b"profile::get_deposited_amount", deposited_shares, 1
                    );
                    let shares =
                        strategy_aries::get_shares_from_amount(
                            &vault_asset, remaining_amount
                        );
                    deposited_shares = deposited_shares + shares;
                    aries::mock::on(
                        b"profile::get_deposited_amount", deposited_shares, 1
                    );
                };
            }
        };

        aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 1);

        (asset_amount, deposited_shares)
    }

    fun test_compound_vault(self: &TestContext, sender: &signer) {
        aries::mock::reset(b"profile::get_deposited_amount");

        let deposited_shares: u64 = 7_990_000;
        let (_, final_deposited_shares) =
            self.mock_compound_vault(
                1_0000_0000,
                2_0000_0000,
                deposited_shares,
                aries::decimal::raw(aries::decimal::from_u128(2_400_000))
            );

        let deposit_reward: u64 = 990_000; // 1_0000_0000 * 90 / 100
        let borrow_reward: u64 = 1_980_000; // 2_0000_0000 * 90 / 100
        let total_shares: u128 = 7_990_000_0000_0000;
        let owned_shares: u128 = 1_990_000_0000_0000;

        deposited_shares = deposited_shares + deposit_reward;

        let repay_amount: u64 = 2_412_000;
        let owned_deposited_shares =
            (owned_shares * (deposited_shares as u128) / total_shares) as u64;
        let owned_amount = owned_deposited_shares;
        let amount = repay_amount - owned_amount;
        let shares = amount;
        let vault_shares = (shares as u128) * total_shares / (deposited_shares as u128);
        total_shares = total_shares + vault_shares;
        owned_shares = owned_shares + vault_shares;
        deposited_shares = deposited_shares + shares;

        let remaining = borrow_reward - amount;
        let shares = remaining;
        deposited_shares = deposited_shares + shares;
        assert!(deposited_shares == final_deposited_shares);
        aries::mock::on(b"profile::get_deposited_amount", deposited_shares, 99);

        strategy_aries::compound_vault(sender, self.vault_name);

        debug::print(
            &aptos_std::string_utils::format2(
                &b"deposited_shares: {}, total_shares: {}",
                deposited_shares,
                total_shares
            )
        );

        // assert vault state
        let (_, vault) = strategy_aries::get_vault(self.vault_name);
        debug::print(&vault);
        assert!(get_vault_data<u128>(&vault, b"total_shares") == total_shares);
        assert!(get_vault_data<u128>(&vault, b"owned_shares") == owned_shares);

        // assert account state
        let account_data =
            wallet_account::get_strategy_data<strategy_aries::AccountData>(
                &wallet_account::get_wallet_account(self.wallet1_id)
            );
        let (_, vault_shares) =
            account_data.get_raw_account_data_for_vault(self.vault_address);
        let deposit_shares =
            vault.get_deposit_shares_from_vault_shares(vault_shares, deposited_shares);

        let (pending, deposited, withdrawable) =
            strategy_aries::get_account_state(self.vault_name, self.wallet1_id);
        assert!(pending == 2_000_000);
        assert!(deposited == 2_000_000);
        assert!(withdrawable == 2_000_000 + deposit_shares);
    }

    #[test(
        deployer = @moneyfi, aries_deployer = @aries, wallet1 = @0x111, wallet2 = @0x222
    )]
    fun test_all(
        deployer: &signer,
        aries_deployer: &signer,
        wallet1: &signer,
        wallet2: &signer
    ) {
        let ctx = setup(deployer, aries_deployer, wallet1, wallet2);

        debug::print(
            &string::utf8(b"TEST ===> test_create_vault: create USDT/USDC vault")
        );
        ctx.test_create_vault(deployer);
        debug::print(
            &string::utf8(
                b"TEST ===> test_deposit: deposit 5 USDT from wallet1, 10 USDT from wallet2"
            )
        );
        ctx.test_deposit(deployer);
        debug::print(
            &string::utf8(
                b"TEST ===> test_withdraw_pending_amount: withdraw 1 USDT from vault to wallet1"
            )
        );
        ctx.test_withdraw_pending_amount(deployer);
        debug::print(
            &string::utf8(b"TEST ===> test_vault_deposit: vault deposit 7 USDT to aries")
        );
        ctx.test_vault_deposit(deployer);
        debug::print(
            &string::utf8(
                b"TEST ===> test_withdraw_mix: withdraw 6 USDT from vault to wallet2"
            )
        );
        ctx.test_withdraw_mix(deployer);
        debug::print(&string::utf8(b"TEST ===> test_borrow_and_deposit: borrow 2 USDC"));
        ctx.test_borrow_and_deposit(deployer);
        debug::print(&string::utf8(b"TEST ===> test_compound_vault"));
        ctx.test_compound_vault(deployer);
        // debug::print(
        //     &string::utf8(b"TEST ===> test_withdraw_trigger_repay: wallet1 withdraw max")
        // );
        // ctx.test_withdraw_trigger_repay(deployer);
    }
}

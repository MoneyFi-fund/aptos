module moneyfi::strategy_aries {
    use std::option::{Self, Option};
    use std::error;
    use std::signer;
    use std::string::String;
    use aptos_std::math64;
    use aptos_std::math128;
    use aptos_std::from_bcs;
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;

    use moneyfi::access_control;
    use moneyfi::storage;
    use moneyfi::wallet_account::{Self, WalletAccount};

    friend moneyfi::strategy;

    const STRATEGY_ACCOUNT_SEED: vector<u8> = b"strategy_aries::STRATEGY_ACCOUNT";
    const APT_FA_ADDRESS: address = @0xa;
    const U64_MAX: u64 = 18446744073709551615;
    const SHARE_DECIMALS: u64 = 8;

    const E_VAULT_EXISTS: u64 = 1;
    const E_EXCEED_CAPACITY: u64 = 2;
    const E_UNSUPPORTED_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;

    struct Strategy has key {
        extend_ref: ExtendRef,
        vaults: OrderedMap<address, Vault>
    }

    struct Vault has store, copy {
        name: String,
        asset: Object<Metadata>,
        borrow_asset: Object<Metadata>,
        deposit_cap: u64,
        // accumulated deposited amount
        total_deposited_amount: u128,
        // accumulated withdrawn amount
        total_withdrawn_amount: u128,
        // unused amount, includes: pending deposited amount, dust when counpound reward, swap assets
        available_amount: u64,
        available_borrow_amount: u64,
        rewards: OrderedMap<address, u64>,
        // amount deposited from wallet account but not yet deposited to Aries
        pending_amount: OrderedMap<address, u64>,
        // shares minted by vault for wallet account
        total_shares: u128,
        // shares minted by vault to itself when looping
        owned_shares: u128,
        paused: bool
    }

    /// Track asset of an account in vault
    struct VaultAsset has copy, store, drop {
        // amount deposited to aries
        deposited_amount: u64,
        vault_shares: u128
    }

    // -- Events
    #[event]
    struct VaultCreatedEvent has drop, store {
        address: address,
        name: String,
        timestamp: u64
    }

    fun init_module(_sender: &signer) {
        init_strategy_account();
    }

    // -- Entries

    public entry fun create_vault(
        sender: &signer,
        name: String,
        asset: Object<Metadata>,
        borrow_asset: Object<Metadata>
    ) acquires Strategy {
        access_control::must_be_service_account(sender);
        assert!(!name.is_empty());
        assert!(&asset != &borrow_asset);
        // assert assets are supported
        get_reserve_type_info(&asset);
        get_reserve_type_info(&borrow_asset);

        let strategy_addr = get_strategy_address();
        assert!(
            !aries::profile::profile_exists(strategy_addr, name),
            error::already_exists(E_VAULT_EXISTS)
        );

        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();

        if (!aries::profile::is_registered(strategy_addr)) {
            aries::profile::init_with_referrer(&strategy_signer, strategy_addr);
        };
        aries::profile::new(&strategy_signer, name);

        let addr = aries::profile::get_profile_address(strategy_addr, name);
        ordered_map::add(
            &mut strategy.vaults,
            addr,
            Vault {
                name,
                asset,
                borrow_asset,
                deposit_cap: U64_MAX,
                available_amount: 0,
                available_borrow_amount: 0,
                total_deposited_amount: 0,
                total_withdrawn_amount: 0,
                rewards: ordered_map::new(),
                pending_amount: ordered_map::new(),
                total_shares: 0,
                owned_shares: 0,
                paused: false
            }
        );

        event::emit(
            VaultCreatedEvent { address: addr, name, timestamp: timestamp::now_seconds() }
        );
    }

    public entry fun config_vault(
        sender: &signer,
        name: String,
        emode: Option<String>,
        deposit_cap: u64,
        paused: bool
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();
        let vault = strategy.get_vault_mut(name);

        vault.deposit_cap = deposit_cap;
        vault.paused = paused;

        if (option::is_some(&emode)) {
            let emode = option::borrow(&emode);
            if (emode.is_empty()) {
                aries::controller::exit_emode(&strategy_signer, name);
            } else {
                aries::controller::enter_emode(&strategy_signer, name, *emode);
            }
        };
    }

    /// Deposits fund from vault to Aries
    /// Pass amount = U64_MAX to deposit all pending amount
    public entry fun vault_deposit(
        sender: &signer, vault_name: String, amount: u64
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        let total_pending_amount = vault.get_total_pending_amount();
        if (amount > total_pending_amount) {
            amount = total_pending_amount;
        };

        vault.compound_vault_impl(strategy_signer);

        let (total_deposit_shares, _) = vault.get_deposited_amount();
        let (deposited_amount, deposited_shares) =
            vault.deposit_to_aries(strategy_signer, amount);
        let vault_shares = vault.mint_vault_shares(deposited_shares, total_deposit_shares);

        vault.pending_amount.for_each_mut(
            |k, v| {
                let acc_deposited_amount = *v * deposited_amount / total_pending_amount;
                let acc_vault_shares =
                    (*v as u128) * vault_shares / (total_pending_amount as u128);
                *v = *v - acc_deposited_amount;

                let vault_addr = get_vault_address(vault_name);
                let account = &object::address_to_object<WalletAccount>(*k);
                let account_data = get_account_data(account);
                let account_vault_data =
                    get_account_data_for_vault(&mut account_data, vault_addr);
                account_vault_data.deposited_amount =
                    account_vault_data.deposited_amount + acc_deposited_amount;
                account_vault_data.vault_shares =
                    account_vault_data.vault_shares + acc_vault_shares;

                wallet_account::set_strategy_data(account, account_data);
            }
        );

        if (deposited_amount == total_pending_amount) {
            vault.pending_amount = ordered_map::new();
        };

        // TODO: emit an event if needed
    }

    public entry fun borrow_and_deposit(
        sender: &signer,
        vault_name: String,
        amount: u64,
        swap_slippage: u64
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        vault.borrow_and_deposit_impl(strategy_signer, amount, swap_slippage);

        // TODO: emit an event if needed
    }

    public entry fun compound_vault(sender: &signer, vault_name: String) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        vault.compound_vault_impl(strategy_signer);

        // TODO: emit an event if needed
    }

    // -- Views

    #[view]
    fun get_strategy_address(): address {
        storage::get_child_object_address(STRATEGY_ACCOUNT_SEED)
    }

    #[view]
    public fun get_vault(name: String): (address, Vault) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let vault_addr = get_vault_address(name);
        assert!(
            ordered_map::contains(&strategy.vaults, &vault_addr),
            error::not_found(E_VAULT_EXISTS)
        );

        (vault_addr, *ordered_map::borrow(&strategy.vaults, &vault_addr))
    }

    #[view]
    public fun get_max_borrow_amount(vault_name: String): u64 acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        let vault = strategy.vaults.borrow(&get_vault_address(vault_name));

        vault.max_borrow_amount()
    }

    // -- Public

    /// deposit fund from wallet account to strategy vault
    public(friend) fun deposit_to_vault(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount: u64,
        extra_data: vector<vector<u8>>
    ): u64 acquires Strategy {
        assert!(amount > 0);
        assert!(extra_data.length() > 0);

        let vault_name = from_bcs::to_string(*extra_data.borrow(0));
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);
        assert!(&vault.asset == asset);
        assert!(amount > 0);

        let (_, asset_amount) = vault.get_deposited_amount();
        assert!(
            asset_amount + vault.available_amount + amount <= vault.deposit_cap,
            error::permission_denied(E_EXCEED_CAPACITY)
        );

        let account_signer = wallet_account::get_wallet_account_signer(account);
        primary_fungible_store::transfer(
            &account_signer,
            vault.asset,
            strategy_addr,
            amount
        );
        vault.total_deposited_amount = vault.total_deposited_amount + (amount as u128);
        vault.available_amount = vault.available_amount + amount;
        vault.update_pending_amount(account, amount, 0);

        amount
    }

    /// Withdraw fund from strategy vault to wallet account
    /// Pass amount = U64_MAX to withdraw all
    public(friend) fun withdraw_from_vault(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64, u64) acquires Strategy {
        assert!(amount > 0);
        assert!(extra_data.length() > 1);

        // TODO: check rate limit

        let vault_name = from_bcs::to_string(*extra_data.borrow(0));
        let swap_slippage = from_bcs::to_u64(*extra_data.borrow(1));
        assert!(swap_slippage < 10000);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();

        let vault_addr = get_vault_address(vault_name);
        let account_data = get_account_data(account);
        let account_vault_data = get_account_data_for_vault(
            &mut account_data, vault_addr
        );

        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);
        assert!(&vault.asset == asset);

        let deposited_amount = amount;
        let pending_amount = vault.get_pending_amount(account);
        if (amount > pending_amount) {
            vault.compound_vault_impl(strategy_signer);

            let withdraw_amount = amount - pending_amount;
            amount = pending_amount;
            let (total_deposit_shares, _) = vault.get_deposited_amount();
            let acc_deposit_shares =
                vault.get_deposit_shares_from_vault_shares(
                    account_vault_data.vault_shares, total_deposit_shares
                );
            let reserve_type = get_reserve_type_info(&vault.asset);
            let acc_deposit_amount =
                aries::reserve::get_underlying_amount_from_lp_amount(
                    reserve_type, acc_deposit_shares
                );
            if (withdraw_amount > acc_deposit_amount) {
                withdraw_amount = acc_deposit_amount;
            };

            let (withdrawn_amount, burned_shares) =
                vault.withdraw_from_aries(strategy_signer, withdraw_amount, swap_slippage);

            let dep_amount =
                math64::mul_div(
                    account_vault_data.deposited_amount,
                    burned_shares,
                    acc_deposit_shares
                );
            account_vault_data.deposited_amount =
                if (account_vault_data.deposited_amount > dep_amount) {
                    account_vault_data.deposited_amount - dep_amount
                } else { 0 };
            let burned_vault_shares =
                vault.burn_vault_shares(burned_shares, total_deposit_shares);
            account_vault_data.vault_shares =
                if (account_vault_data.vault_shares > burned_vault_shares) {
                    account_vault_data.vault_shares - burned_vault_shares
                } else { 0 };

            let (_, owned_deposited_amount) =
                vault.get_owned_deposited_amount(total_deposit_shares);
            let total_loan_amount = vault.estimate_amount_to_repay();
            if (total_loan_amount > owned_deposited_amount) {
                let deduct_amount =
                    (total_loan_amount - owned_deposited_amount) * burned_shares
                        / total_deposit_shares;
                withdrawn_amount =
                    withdrawn_amount
                        - math64::min(withdraw_amount, deduct_amount as u64);
            };

            deposited_amount = deposited_amount + dep_amount;
            amount = amount + withdrawn_amount;
            vault.update_pending_amount(account, withdrawn_amount, 0);
        };

        let account_addr = object::object_address(account);
        primary_fungible_store::transfer(
            strategy_signer,
            vault.asset,
            account_addr,
            amount
        );
        vault.update_pending_amount(account, 0, amount);
        vault.available_amount = vault.available_amount - amount;
        vault.total_withdrawn_amount = vault.total_withdrawn_amount + (amount as u128);

        wallet_account::set_strategy_data(account, account_data);

        (deposited_amount, amount, 0)
    }

    public fun get_stats(asset: &Object<Metadata>): (u128, u128, u128) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);

        let total_deposited = 0;
        let total_withdrawn = 0;
        let current_tvl = 0;
        strategy.vaults.for_each_ref(|_, v| {
            if (&v.asset == asset) {
                total_deposited = total_deposited + v.total_deposited_amount;
                total_withdrawn = total_withdrawn + v.total_withdrawn_amount;

                let (_, asset_amount) = get_deposited_amount(v);
                current_tvl = current_tvl + (asset_amount as u128);
            };
        });

        (current_tvl, total_deposited, total_withdrawn)
    }

    //  -- Private

    fun init_strategy_account() {
        let account_addr = storage::get_child_object_address(STRATEGY_ACCOUNT_SEED);
        assert!(!exists<Strategy>(account_addr));

        let extend_ref =
            storage::create_child_object_with_phantom_owner(STRATEGY_ACCOUNT_SEED);
        let account_signer = object::generate_signer_for_extending(&extend_ref);
        move_to(
            &account_signer,
            Strategy { extend_ref, vaults: ordered_map::new() }
        );
    }

    fun get_account_signer(self: &Strategy): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    fun get_vault_mut_by_address(self: &mut Strategy, addr: address): &mut Vault {
        assert!(ordered_map::contains(&self.vaults, &addr));

        ordered_map::borrow_mut(&mut self.vaults, &addr)
    }

    fun get_vault_address(name: String): address {
        let strategy_addr = get_strategy_address();

        aries::profile::get_profile_address(strategy_addr, name)
    }

    fun get_vault_mut(self: &mut Strategy, name: String): &mut Vault {
        self.get_vault_mut_by_address(get_vault_address(name))
    }

    fun get_account_data(account: &Object<WalletAccount>): OrderedMap<address, VaultAsset> {
        let account_data =
            if (wallet_account::strategy_data_exists<OrderedMap<address, VaultAsset>>(
                account
            )) {
                wallet_account::get_strategy_data<OrderedMap<address, VaultAsset>>(
                    account
                )
            } else {
                ordered_map::new()
            };

        account_data
    }

    fun get_account_data_for_vault(
        account_data: &mut OrderedMap<address, VaultAsset>, vault_addr: address
    ): &mut VaultAsset {
        if (!account_data.contains(&vault_addr)) {
            account_data.add(
                vault_addr, VaultAsset { deposited_amount: 0, vault_shares: 0 }
            )
        };

        account_data.borrow_mut(&vault_addr)
    }

    fun get_pending_amount(
        self: &Vault, account: &Object<WalletAccount>
    ): u64 {
        let account_addr = object::object_address(account);

        if (self.pending_amount.contains(&account_addr)) {
            *self.pending_amount.borrow(&account_addr)
        } else { 0 }
    }

    fun update_pending_amount(
        self: &mut Vault,
        account: &Object<WalletAccount>,
        add_amount: u64,
        remove_amount: u64
    ): u64 {
        let account_addr = object::object_address(account);
        if (!self.pending_amount.contains(&account_addr)) {
            self.pending_amount.add(account_addr, 0);
        };
        let pending_amount = self.pending_amount.borrow_mut(&account_addr);
        if (add_amount > 0) {
            *pending_amount = *pending_amount + add_amount;
        };
        if (remove_amount > 0) {
            *pending_amount = *pending_amount
                - math64::min(*pending_amount, remove_amount);
        };

        let pending_amount = *pending_amount;
        if (pending_amount == 0) {
            self.pending_amount.remove(&account_addr);
        };

        pending_amount
    }

    /// Deposit asset from vault to Aries
    /// Return actual amount and shares
    fun deposit_to_aries(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u64) {
        let (shares_before, _) = self.get_deposited_amount();
        let actual_amount =
            deposit_to_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        let (shares_after, _) = self.get_deposited_amount();
        assert!(shares_after > shares_before);

        let shares = shares_after - shares_before;
        self.available_amount = self.available_amount - actual_amount;

        (actual_amount, shares)
    }

    /// Returns actual amount
    fun deposit_to_aries_impl(
        caller: &signer,
        profile: vector<u8>,
        asset: &Object<Metadata>,
        amount: u64
    ): u64 {
        let asset_addr = object::object_address(asset);
        assert!(
            asset_addr == @usdc || asset_addr == @usdt,
            error::permission_denied(E_UNSUPPORTED_ASSET)
        );

        let addr = signer::address_of(caller);
        let balance_before = primary_fungible_store::balance(addr, *asset);
        if (asset_addr == @usdc) {
            aries::controller::deposit_fa<aries::wrapped_coins::WrappedUSDC>(
                caller, profile, amount
            );
        } else if (asset_addr == @usdt) {
            aries::controller::deposit_fa<aries::fa_to_coin_wrapper::WrappedUSDT>(
                caller, profile, amount
            );
        };
        let balance_after = primary_fungible_store::balance(addr, *asset);
        assert!(balance_before >= balance_after);

        balance_before - balance_after
    }

    /// Withdraw asset from Aries back to vault
    /// Assumes vault has been compounded
    /// Return received amount and burned shares
    fun withdraw_from_aries(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        swap_slippage: u64
    ): (u64, u64) {
        let reserve_type = get_reserve_type_info(&self.asset);
        let (borrow_shares, _) = self.get_loan_amount();
        let (total_deposit_shares, _) = self.get_deposited_amount();
        if (borrow_shares > 0) {
            let avail_amount = self.get_available_withdraw_amount();
            if (amount > avail_amount) {
                let shares =
                    aries::reserve::get_lp_amount_from_underlying_amount(
                        reserve_type, amount
                    );
                let vault_shares =
                    self.get_vault_shares_from_deposit_shares(
                        shares, total_deposit_shares
                    );

                let owned_shares =
                    if (self.total_shares > self.owned_shares) {
                        vault_shares * self.owned_shares
                            / (self.total_shares - self.owned_shares)
                    } else {
                        self.owned_shares
                    };
                let withdrawn_amount =
                    self.withdraw_owned_shares(strategy_signer, owned_shares);
                self.repay_aries(strategy_signer, withdrawn_amount, swap_slippage);

                return self.withdraw_from_aries(strategy_signer, amount, swap_slippage);
            }
        };

        let (shares_before, _) = self.get_deposited_amount();
        let amount =
            withdraw_from_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        let (shares_after, _) = self.get_deposited_amount();
        assert!(shares_before >= shares_after);

        let shares = shares_before - shares_after;
        self.available_amount = self.available_amount + amount;

        (amount, shares)
    }

    fun withdraw_owned_shares(
        self: &mut Vault, strategy_signer: &signer, shares: u128
    ): u64 {
        assert!(shares <= self.owned_shares);

        let reserve_type = get_reserve_type_info(&self.asset);
        let (total_deposit_shares, _) = self.get_deposited_amount();
        let deposit_shares =
            self.get_deposit_shares_from_vault_shares(shares, total_deposit_shares);
        let amount =
            aries::reserve::get_underlying_amount_from_lp_amount(
                reserve_type, deposit_shares
            );

        let amount =
            withdraw_from_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        self.available_amount = self.available_amount + amount;
        let shares = self.burn_vault_shares(deposit_shares, total_deposit_shares);
        self.owned_shares =
            if (self.owned_shares > shares) {
                self.owned_shares - shares
            } else { 0 };

        amount
    }

    fun compound_vault_impl(self: &mut Vault, strategy_signer: &signer) {
        let amount =
            compound_rewards<aries::reserve_config::DepositFarming>(
                self, strategy_signer
            );
        if (amount > 0) {
            self.deposit_to_aries(strategy_signer, amount);
        };

        self.compound_borrow_asset(strategy_signer);

        // deposit all avail amount to aries
        let avail_amount = self.get_avail_amount_without_pending_amount();
        if (avail_amount > 0) {
            self.deposit_to_aries(strategy_signer, avail_amount);
        }
    }

    /// Assume deposit rewards have been compounded
    /// Return interest amount
    fun compound_borrow_asset(
        self: &mut Vault, strategy_signer: &signer
    ): u64 {
        let slippage = 10; // TODO: determine slippage

        if (self.available_borrow_amount > 0) {
            let amount = self.available_borrow_amount;
            self.repay_aries(strategy_signer, amount, slippage);
        };

        let amount = 0;
        if (self.available_borrow_amount > 0) {
            let avail_amount = self.available_borrow_amount;
            let (_, amount_out) =
                self.swap_from_borrow_asset(strategy_signer, avail_amount, slippage);
            amount = amount + amount_out;
        };

        // compound borrowing rewards
        let reward_amount =
            compound_rewards<aries::reserve_config::BorrowFarming>(
                self, strategy_signer
            );
        amount = amount + reward_amount;

        let (total_shares, _) = self.get_deposited_amount();
        let (_, deposited_amount) = self.get_owned_deposited_amount(total_shares);
        let total_loan_amount = self.estimate_amount_to_repay();

        let vault_amount = 0;
        if (deposited_amount < total_loan_amount) {
            vault_amount =
                if (total_loan_amount - deposited_amount < amount) {
                    amount - (total_loan_amount - deposited_amount)
                } else { amount };
        } else {
            let interest = deposited_amount - total_loan_amount;
            amount = amount + interest;
            // burn owned_shares to distribute interest to accounts
            let shares =
                aries::reserve::get_lp_amount_from_underlying_amount(
                    get_reserve_type_info(&self.asset), interest
                );
            let vault_shares = self.burn_vault_shares(shares, total_shares);
            self.owned_shares =
                if (self.owned_shares > vault_shares) {
                    self.owned_shares - vault_shares
                } else { 0 };
        };

        if (vault_amount > 0) {
            let (shares, _) = self.deposit_to_aries(strategy_signer, vault_amount);
            self.owned_shares =
                self.owned_shares + self.mint_vault_shares(shares, total_shares);
        };

        amount
    }

    fun estimate_amount_to_repay(self: &Vault): u64 {
        let (borrow_shares, loan_amount) = self.get_loan_amount();

        if (borrow_shares > 0) {
            let loan_amount =
                aries::decimal::ceil_u64(aries::decimal::from_scaled_val(loan_amount));
            if (self.available_borrow_amount < loan_amount) {
                return self.estimate_swap_amount_to_repay(
                    loan_amount - self.available_borrow_amount,
                    10 // TODO: determine slippage
                );
            }
        };

        0
    }

    fun get_total_pending_amount(self: &Vault): u64 {
        let amount = 0;
        self.pending_amount.for_each_ref(|_, v| {
            amount = amount + *v;
        });

        amount
    }

    fun get_avail_amount_without_pending_amount(self: &Vault): u64 {
        self.available_amount - self.get_total_pending_amount()
    }

    fun get_available_withdraw_amount(self: &Vault): u64 {
        let strategy_addr = get_strategy_address();
        let avail_power =
            aries::profile::available_borrowing_power(strategy_addr, &self.name);
        let price = get_asset_price(&self.asset);
        let amount = aries::decimal::as_u64(aries::decimal::div(avail_power, price));

        amount - amount * 10 / 100 // 90% of available power
    }

    fun withdraw_from_aries_impl(
        caller: &signer,
        profile: vector<u8>,
        asset: &Object<Metadata>,
        amount: u64
    ): u64 {
        let asset_addr = object::object_address(asset);
        assert!(
            asset_addr == @usdc || asset_addr == @usdt,
            error::permission_denied(E_UNSUPPORTED_ASSET)
        );

        let addr = signer::address_of(caller);
        let balance_before = primary_fungible_store::balance(addr, *asset);
        if (asset_addr == @usdc) {
            aries::controller::withdraw_fa<aries::wrapped_coins::WrappedUSDC>(
                caller, profile, amount, false
            );
        } else if (asset_addr == @usdt) {
            aries::controller::withdraw_fa<aries::fa_to_coin_wrapper::WrappedUSDT>(
                caller, profile, amount, false
            );
        };

        let balance_after = primary_fungible_store::balance(addr, *asset);
        assert!(balance_after >= balance_before);

        balance_after - balance_before
    }

    fun max_borrow_amount(self: &Vault): u64 {
        let strategy_addr = get_strategy_address();
        let reserve_info = get_reserve_type_info(&self.borrow_asset);

        aries::profile::max_borrow_amount(strategy_addr, &self.name, reserve_info)
    }

    /// Returns amount, shares and loan amount
    fun borrow_from_aries(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u128, u128) {
        let borrowable_amount = self.max_borrow_amount();
        assert!(borrowable_amount > amount);

        let (shares_before, loan_amount_before) = self.get_loan_amount();
        let amount =
            withdraw_from_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        let (shares_after, loan_amount_after) = self.get_loan_amount();
        assert!(loan_amount_after >= shares_after);
        assert!(shares_after >= shares_before);

        let shares = shares_before - shares_after;
        let loan_amount = loan_amount_after - loan_amount_before;
        self.available_borrow_amount = self.available_borrow_amount + amount;

        (amount, shares, loan_amount)
    }

    fun borrow_and_deposit_impl(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        swap_slippage: u64
    ) {
        self.borrow_from_aries(strategy_signer, amount);
        assert!(self.available_borrow_amount > 0);
        let amount = self.available_borrow_amount;
        let (_, amount_out) =
            self.swap_from_borrow_asset(strategy_signer, amount, swap_slippage);
        let (total_shares, _) = self.get_deposited_amount();
        let (_, shares) = self.deposit_to_aries(strategy_signer, amount_out);
        let vault_shares = self.mint_vault_shares(shares, total_shares);
        self.owned_shares = self.owned_shares + vault_shares;
    }

    /// Repays borrowed asset to Aries. Requires sufficient available amount.
    /// Returns repaid amount and swapped asset amount
    fun repay_aries(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        swap_slippage: u64
    ): (u64, u64) {
        let (shares, loan_amount) = self.get_loan_amount();
        let amount =
            if (aries::decimal::raw(aries::decimal::from_u64(amount)) <= loan_amount) {
                amount
            } else {
                aries::decimal::ceil_u64(
                    aries::reserve::get_borrow_amount_from_share_dec(
                        get_reserve_type_info(&self.borrow_asset),
                        aries::decimal::from_scaled_val(shares)
                    )
                )
            };
        if (amount == 0) {
            return (0, 0);
        };

        let asset_amount = 0;
        if (amount > self.available_borrow_amount) {
            let amount_in =
                self.estimate_swap_amount_to_repay(
                    amount - self.available_borrow_amount, swap_slippage
                );
            if (amount_in > 0) {
                assert!(amount_in <= self.available_amount);
                (asset_amount, _) = self.swap_to_borrow_asset(
                    strategy_signer, amount_in, swap_slippage
                );
            }
        };

        let amount =
            deposit_to_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        self.available_borrow_amount = self.available_borrow_amount - amount;

        (amount, asset_amount)
    }

    /// Returns amaount of swapped vault asset and received borrow asset
    fun swap_to_borrow_asset(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        slippage: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                &self.asset,
                &self.borrow_asset,
                amount,
                slippage,
                true
            );
        self.available_amount = self.available_amount - amount_in;
        self.available_borrow_amount = self.available_borrow_amount + amount_out;

        (amount_in, amount_out)
    }

    /// Returns amaount of swapped borrow asset and received vault asset
    fun swap_from_borrow_asset(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        slippage: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                &self.borrow_asset,
                &self.asset,
                amount,
                slippage,
                false
            );
        self.available_amount = self.available_amount + amount_out;
        self.available_borrow_amount = self.available_borrow_amount - amount_in;

        (amount_in, amount_out)
    }

    fun estimate_swap_amount_to_repay(
        self: &Vault, repay_amount: u64, slippage: u64
    ): u64 {
        let (_, pool) = get_hyperion_pool(&self.asset, &self.borrow_asset);
        let (amount_in, _) =
            hyperion::pool_v3::get_amount_in(pool, self.borrow_asset, repay_amount);

        amount_in + amount_in * slippage / 10000
    }

    fun estimate_repay_amount(
        self: &Vault,
        borrow_asset: &Object<Metadata>,
        amount: u64,
        slippage: u64
    ): u64 {
        let (_, pool) = get_hyperion_pool(&self.asset, borrow_asset);
        let (amount_out, _) =
            hyperion::pool_v3::get_amount_out(pool, *borrow_asset, amount);

        amount_out - amount_out * slippage / 10000
    }

    fun get_reward(self: &Vault, reward: address): u64 {
        if (self.rewards.contains(&reward)) {
            *self.rewards.borrow(&reward)
        } else { 0 }
    }

    fun get_reward_mut(self: &mut Vault, reward: address): &mut u64 {
        if (!self.rewards.contains(&reward)) {
            self.rewards.add(reward, 0);
        };

        self.rewards.borrow_mut(&reward)
    }

    fun mint_vault_shares(
        self: &mut Vault, deposit_shares: u64, total_deposit_shares: u64
    ): u128 {
        let vault_shares =
            self.get_vault_shares_from_deposit_shares(
                deposit_shares, total_deposit_shares
            );
        self.total_shares = self.total_shares + vault_shares;

        vault_shares
    }

    fun burn_vault_shares(
        self: &mut Vault, burned_deposit_shares: u64, total_deposit_shares: u64
    ): u128 {
        let vault_shares =
            math128::ceil_div(
                self.total_shares * (burned_deposit_shares as u128),
                (total_deposit_shares as u128)
            );
        self.total_shares =
            if (self.total_shares > vault_shares) {
                self.total_shares - vault_shares
            } else { 0 };

        vault_shares
    }

    fun get_deposit_shares_from_vault_shares(
        self: &Vault, vault_shares: u128, total_deposit_shares: u64
    ): u64 {
        if (self.total_shares == 0) {
            total_deposit_shares
        } else {
            (vault_shares * (total_deposit_shares as u128) / self.total_shares) as u64
        }
    }

    fun get_vault_shares_from_deposit_shares(
        self: &Vault, deposit_shares: u64, total_deposit_shares: u64
    ): u128 {
        if (total_deposit_shares == 0) {
            (deposit_shares as u128) * math128::pow(10, SHARE_DECIMALS as u128)
        } else {
            (deposit_shares as u128) * math128::pow(10, SHARE_DECIMALS as u128)
                * self.total_shares / (total_deposit_shares as u128)
        }
    }

    fun get_owned_deposited_amount(
        self: &Vault, total_deposit_shares: u64
    ): (u64, u64) {
        let shares =
            self.get_deposit_shares_from_vault_shares(
                self.owned_shares, total_deposit_shares
            );

        let amount =
            aries::reserve::get_underlying_amount_from_lp_amount(
                get_reserve_type_info(&self.asset), shares
            );

        (shares, amount)
    }

    /// Returns shares and current asset amount
    fun get_deposited_amount(self: &Vault): (u64, u64) {
        let strategy_addr = get_strategy_address();

        let reserve_type = get_reserve_type_info(&self.asset);
        let shares =
            aries::profile::get_deposited_amount(strategy_addr, &self.name, reserve_type);
        let asset_amount =
            aries::reserve::get_underlying_amount_from_lp_amount(reserve_type, shares);

        (shares, asset_amount)
    }

    /// Returns shares and current loan
    fun get_loan_amount(self: &Vault): (u128, u128) {
        let strategy_addr = get_strategy_address();

        let asset_addr = object::object_address(&self.borrow_asset);
        if (asset_addr == @usdt) {
            aries::profile::profile_loan<aries::fa_to_coin_wrapper::WrappedUSDT>(
                strategy_addr, self.name
            )
        } else if (asset_addr == @usdc) {
            aries::profile::profile_loan<aries::wrapped_coins::WrappedUSDC>(
                strategy_addr, self.name
            )
        } else { (0, 0) }
    }

    /// Claims all rewards abd swap to vault asset
    fun compound_rewards<T>(self: &mut Vault, strategy_signer: &signer): u64 {
        let asset = self.asset;
        // TODO: claim other rewards
        let min_amount = 100_000_000; // 1 APT
        claim_reward<AptosCoin, T>(self, strategy_signer, min_amount);

        let apt_amount = self.get_reward_mut(APT_FA_ADDRESS);
        if (*apt_amount < min_amount) {
            return 0;
        };

        let apt_reward = object::address_to_object<Metadata>(APT_FA_ADDRESS);
        let (in_amount, out_amount) =
            swap_with_hyperion(
                strategy_signer,
                &apt_reward,
                &asset,
                *apt_amount,
                50, // 0.5%
                false
            );
        *apt_amount = *apt_amount - in_amount;
        if (out_amount > 0) {
            self.available_amount = self.available_amount + out_amount;
        };

        out_amount
    }

    /// Returns claimed amount
    fun claim_reward<R, F>(
        self: &mut Vault, strategy_signer: &signer, min_amount: u64
    ): u64 {
        let strategy_addr = get_strategy_address();
        let reserve_type = get_reserve_type_info(&self.asset);
        let farming_type = type_info::type_of<F>();

        let claimed_amount = 0;
        let (rewards, amounts) =
            aries::profile::claimable_reward_amount_on_farming<F>(
                strategy_addr, self.name
            );
        while (rewards.length() > 0) {
            let reward_type = rewards.pop_back();
            let amount = amounts.pop_back();
            if (&reward_type == &type_info::type_of<R>()) {
                if (amount > 0 && amount >= min_amount) {
                    let reward_addr = get_asset_address_from_info_type(&reward_type);
                    let reward = object::address_to_object<Metadata>(reward_addr);
                    let balance_before =
                        primary_fungible_store::balance(strategy_addr, reward);
                    aries::controller::claim_reward_ti<R>(
                        strategy_signer,
                        *self.name.bytes(),
                        reserve_type,
                        farming_type
                    );
                    let balance_after =
                        primary_fungible_store::balance(strategy_addr, reward);

                    claimed_amount =
                        if (balance_after > balance_before) {
                            balance_after - balance_before
                        } else { 0 };

                    if (claimed_amount > 0) {
                        let reward_amount = self.get_reward_mut(reward_addr);
                        *reward_amount = *reward_amount + claimed_amount;
                    }
                };

                break;
            }
        };

        claimed_amount
    }

    fun get_asset_address_from_info_type(type: &TypeInfo): address {
        if (type == &type_info::type_of<AptosCoin>()) {
            return APT_FA_ADDRESS
        };

        abort(E_UNSUPPORTED_ASSET);
        APT_FA_ADDRESS // fallback
    }

    fun get_reserve_type_info(asset: &Object<Metadata>): TypeInfo {
        let asset_addr = object::object_address(asset);
        if (asset_addr == @usdc) {
            return type_info::type_of<aries::wrapped_coins::WrappedUSDC>();
        } else if (asset_addr == @usdt) {
            return type_info::type_of<aries::fa_to_coin_wrapper::WrappedUSDT>();
        };

        abort error::permission_denied(E_UNSUPPORTED_ASSET);
        type_info::type_of<TypeInfo>() // Fallback
    }

    fun get_hyperion_pool(
        asset_0: &Object<Metadata>, asset_1: &Object<Metadata>
    ): (u8, Object<hyperion::pool_v3::LiquidityPoolV3>) {
        let addr_0 = object::object_address(asset_0);
        let addr_1 = object::object_address(asset_1);
        let fee_tier =
            if (addr_0 == APT_FA_ADDRESS || addr_1 == APT_FA_ADDRESS) {
                1 // 0.05%
            } else {
                0 // 0.01%
            };
        let (exist, pool_addr) =
            hyperion::pool_v3::liquidity_pool_address_safe(*asset_0, *asset_1, fee_tier);
        assert!(exist, error::permission_denied(E_POOL_NOT_EXIST));

        let pool =
            object::address_to_object<hyperion::pool_v3::LiquidityPoolV3>(pool_addr);

        (fee_tier, pool)
    }

    /// Returns actual swapped amount and recived amount
    fun swap_with_hyperion(
        caller: &signer,
        from: &Object<Metadata>,
        to: &Object<Metadata>,
        amount: u64,
        slippage: u64, // 100 => 1%
        exact_out: bool
    ): (u64, u64) {
        assert!(slippage < 10000);
        let strategy_addr = get_strategy_address();

        let (fee_tier, pool) = get_hyperion_pool(from, to);
        let (amount_in, amount_out) =
            if (exact_out) {
                let (amount_in, _) = hyperion::pool_v3::get_amount_in(pool, *to, amount);
                amount_in = amount_in + (amount_in * slippage / 10000);
                (amount_in, amount)
            } else {
                let (amount_out, _) =
                    hyperion::pool_v3::get_amount_out(pool, *from, amount);
                amount_out = amount_out - (amount_out * slippage / 10000);
                (amount, amount_out)
            };

        // ignore price impact
        let sqrt_price_limit =
            if (hyperion::utils::is_sorted(*from, *to)) {
                79226673515401279992447579055 // max sqrt price
            } else {
                04295048016 // min sqrt price
            };

        let balance_in_before = primary_fungible_store::balance(strategy_addr, *from);
        let balance_out_before = primary_fungible_store::balance(strategy_addr, *to);
        if (exact_out) {
            hyperion::router_v3::exact_output_swap_entry(
                caller,
                fee_tier,
                amount_in,
                amount_out,
                sqrt_price_limit,
                *from,
                *to,
                strategy_addr,
                timestamp::now_seconds() + 60
            );
        } else {
            hyperion::router_v3::exact_input_swap_entry(
                caller,
                fee_tier,
                amount_in,
                amount_out,
                sqrt_price_limit,
                *from,
                *to,
                strategy_addr,
                timestamp::now_seconds() + 60
            );
        };
        let balance_in_after = primary_fungible_store::balance(strategy_addr, *from);
        let balance_out_after = primary_fungible_store::balance(strategy_addr, *to);

        (balance_in_before - balance_in_after, balance_out_after - balance_out_before)
    }

    fun get_asset_price(asset: &Object<Metadata>): aries::decimal::Decimal {
        let reserve_type = get_reserve_type_info(asset);

        aries::oracle::get_price(reserve_type)
    }
}

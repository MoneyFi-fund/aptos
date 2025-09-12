module moneyfi::strategy_aries {
    use std::option::{Self, Option};
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use aptos_std::math64;
    #[test_only]
    use aptos_std::any;
    use aptos_std::math128;
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
    use moneyfi::vault as moneyfi_vault;
    use moneyfi::wallet_account::{Self, WalletAccount};

    const STRATEGY_ACCOUNT_SEED: vector<u8> = b"strategy_aries::STRATEGY_ACCOUNT";
    const APT_FA_ADDRESS: address = @0xa;
    const U64_MAX: u64 = 18446744073709551615;
    const SHARE_DECIMALS: u64 = 8;

    const E_VAULT_EXISTS: u64 = 1;
    const E_EXCEED_CAPACITY: u64 = 2;
    const E_UNSUPPORTED_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Strategy has key {
        extend_ref: ExtendRef,
        vaults: OrderedMap<address, Vault>
    }

    struct Vault has store, copy, drop {
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

    struct AccountData has store, copy, drop {
        // vault_address => VaultAsset
        vaults: OrderedMap<address, VaultAsset>
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

    fun init_module(sender: &signer) {
        let addr = init_strategy_account();
        moneyfi_vault::register_strategy<Strategy>(sender, addr);
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
        let strategy_signer = strategy.get_strategy_signer();

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
        let strategy_signer = strategy.get_strategy_signer();
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
        let strategy_signer = &strategy.get_strategy_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        vault.compound_vault_impl(strategy_signer);

        let total_pending_amount = vault.get_total_pending_amount();
        if (amount > total_pending_amount) {
            amount = total_pending_amount;
        };

        let (deposited_amount, deposited_shares, total_deposit_shares) =
            vault.deposit_to_aries(strategy_signer, amount);
        let vault_shares = vault.mint_vault_shares(deposited_shares, total_deposit_shares);

        vault.divide_deposited_amount(
            deposited_amount, total_pending_amount, vault_shares
        );

        if (deposited_amount == total_pending_amount) {
            vault.pending_amount = ordered_map::new();
        };

        // TODO: emit an event if needed
    }

    fun divide_deposited_amount(
        self: &mut Vault,
        deposited_amount: u64,
        total_pending_amount: u64,
        vault_shares: u128
    ) {
        let vault_addr = get_vault_address(self.name);

        let remaining_amount = deposited_amount;
        self.pending_amount.for_each_mut(
            |k, v| {
                let acc_deposited_amount =
                    math64::ceil_div(*v * deposited_amount, total_pending_amount);
                acc_deposited_amount = math64::min(acc_deposited_amount, remaining_amount);
                remaining_amount = remaining_amount - acc_deposited_amount;

                let acc_vault_shares =
                    math128::mul_div(
                        acc_deposited_amount as u128,
                        vault_shares,
                        deposited_amount as u128
                    );

                *v = *v - acc_deposited_amount;

                let account = &object::address_to_object<WalletAccount>(*k);
                let account_data = get_account_data(account);
                let account_vault_data =
                    account_data.get_account_data_for_vault(vault_addr);
                account_vault_data.deposited_amount =
                    account_vault_data.deposited_amount + acc_deposited_amount;
                account_vault_data.vault_shares =
                    account_vault_data.vault_shares + acc_vault_shares;

                wallet_account::set_strategy_data(account, account_data);
            }
        );
    }

    public entry fun borrow_and_deposit(
        sender: &signer, vault_name: String, amount: u64
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_strategy_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        vault.borrow_and_deposit_impl(strategy_signer, amount);

        // TODO: emit an event if needed
    }

    public entry fun compound_vault(sender: &signer, vault_name: String) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_strategy_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        vault.compound_vault_impl(strategy_signer);

        // TODO: emit an event if needed
    }

    /// deposit fund from wallet account to strategy vault
    public entry fun deposit(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64
    ) acquires Strategy {
        assert!(amount > 0);
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_strategy_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        let account = wallet_account::get_wallet_account(wallet_id);
        assert!(
            amount + vault.available_amount + amount <= vault.deposit_cap,
            error::permission_denied(E_EXCEED_CAPACITY)
        );
        moneyfi_vault::deposit_to_strategy_vault<Strategy>(
            &strategy_signer,
            wallet_id,
            vault.asset,
            amount
        );

        vault.total_deposited_amount = vault.total_deposited_amount + (amount as u128);
        vault.available_amount = vault.available_amount + amount;
        vault.update_pending_amount(&account, amount, 0);
    }

    /// Withdraw fund from strategy vault to wallet account
    /// Pass amount = U64_MAX to withdraw all
    public entry fun withdraw(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64,
        gas_fee: u64
    ) acquires Strategy {
        assert!(amount > 0);
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_strategy_signer();

        let vault_addr = get_vault_address(vault_name);
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        let account = &wallet_account::get_wallet_account(wallet_id);
        let account_data = get_account_data(account);
        let account_vault_data = account_data.get_account_data_for_vault(vault_addr);

        let deposited_amount = amount;
        let pending_amount = vault.get_pending_amount(account);
        if (amount > pending_amount) {
            vault.compound_vault_impl(strategy_signer);

            let withdraw_amount = amount - pending_amount;
            amount = pending_amount;
            deposited_amount = amount;
            let (total_deposit_shares, _) = vault.get_deposited_amount();
            let reserve_type = get_reserve_type_info(&vault.asset);

            let deposit_shares =
                aries::reserve::get_lp_amount_from_underlying_amount(
                    reserve_type, withdraw_amount
                );
            let vault_shares =
                vault.get_vault_shares_from_deposit_shares(
                    deposit_shares, total_deposit_shares
                );
            if (vault_shares > account_vault_data.vault_shares) {
                vault_shares = account_vault_data.vault_shares;
                deposit_shares = vault.get_deposit_shares_from_vault_shares(
                    vault_shares, total_deposit_shares
                );
                withdraw_amount = aries::reserve::get_underlying_amount_from_lp_amount(
                    reserve_type, deposit_shares
                );
            };

            if (vault_shares > 0 && withdraw_amount > 0) {
                let (withdrawn_amount, burned_shares, total_deposit_shares, _) =
                    vault.withdraw_from_aries(
                        strategy_signer, withdraw_amount, vault_shares
                    );

                let dep_amount =
                    math128::mul_div(
                        account_vault_data.deposited_amount as u128,
                        vault_shares,
                        account_vault_data.vault_shares
                    ) as u64;
                account_vault_data.deposited_amount =
                    if (account_vault_data.deposited_amount > dep_amount) {
                        account_vault_data.deposited_amount - dep_amount
                    } else { 0 };

                // recalc burned_vault_shares from burned_shares not exactly = vault_shares
                // let burned_vault_shares =
                //     vault.burn_vault_shares(burned_shares, total_deposit_shares);
                vault.total_shares = vault.total_shares - vault_shares;
                account_vault_data.vault_shares =
                    if (account_vault_data.vault_shares > vault_shares) {
                        account_vault_data.vault_shares - vault_shares
                    } else { 0 };

                let (_, owned_deposited_amount, total_loan_amount) =
                    vault.get_vault_borrowing_state(total_deposit_shares);
                if (total_loan_amount > owned_deposited_amount) {
                    let deduct_amount =
                        math64::mul_div(
                            total_loan_amount - owned_deposited_amount,
                            burned_shares,
                            total_deposit_shares
                        );
                    withdrawn_amount =
                        withdrawn_amount
                            - math64::min(withdrawn_amount, deduct_amount as u64);
                };

                deposited_amount = deposited_amount + dep_amount;
                amount = amount + withdrawn_amount;
                vault.update_pending_amount(account, withdrawn_amount, 0);
            }
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

        moneyfi_vault::withdrawn_from_strategy<Strategy>(
            strategy_signer,
            wallet_id,
            vault.asset,
            deposited_amount,
            amount,
            0,
            gas_fee
        );
    }

    /// pass amount = U64_MAX to repay all
    public entry fun repay(
        sender: &signer, vault_name: String, amount: u64
    ) acquires Strategy {
        assert!(amount > 0);
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_strategy_signer();
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);

        let (_, loan_amount) = vault.get_loan_amount();
        let amount =
            if (aries::decimal::raw(aries::decimal::from_u64(amount)) <= loan_amount) {
                amount
            } else {
                aries::decimal::ceil_u64(aries::decimal::from_scaled_val(loan_amount))
            };

        vault.compound_vault_impl(strategy_signer);
        vault.repay_aries(strategy_signer, amount);

        // TODO: emit event if needed
    }

    // -- Views

    #[view]
    public fun get_strategy_address(): address {
        storage::get_child_object_address(STRATEGY_ACCOUNT_SEED)
    }

    #[view]
    public fun get_vaults(): (vector<address>, vector<String>) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        let addresses = vector[];
        let names = vector[];
        strategy.vaults.for_each_ref(|k, v| {
            addresses.push_back(*k);
            names.push_back(v.name);
        });

        (addresses, names)
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

    #[view]
    public fun get_borrow_power(vault_name: String): (u64, u64) {
        let strategy_addr = get_strategy_address();
        let power = aries::profile::available_borrowing_power(
            strategy_addr, &vault_name
        );
        let total = aries::profile::get_total_borrowing_power(
            strategy_addr, &vault_name
        );

        (aries::decimal::as_u64(power), aries::decimal::as_u64(total))
    }

    /// Returns (loan_amount, owned_deposited_amount, est_amount_to_repay)
    #[view]
    public fun get_borrowing_state(vault_name: String): (u64, u64, u64) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        let vault = strategy.vaults.borrow(&get_vault_address(vault_name));

        let (total_shares, _) = vault.get_deposited_amount();
        vault.get_vault_borrowing_state(total_shares)
    }

    // Returns (pending_amount, deposited_amount, estimate_withdrawable_amount)
    #[view]
    public fun get_account_state(
        vault_name: String, wallet_id: vector<u8>
    ): (u64, u64, u64) acquires Strategy {
        let account = wallet_account::get_wallet_account(wallet_id);
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        let vault_addr = get_vault_address(vault_name);
        let vault = strategy.vaults.borrow(&vault_addr);

        let pending_amount = vault.get_pending_amount(&account);

        let account_data = get_account_data(&account);
        let (deposited_amount, vault_shares) =
            account_data.get_raw_account_data_for_vault(vault_addr);

        let (total_shares, _) = vault.get_deposited_amount();
        let shares =
            vault.get_deposit_shares_from_vault_shares(vault_shares, total_shares);

        let amount =
            aries::reserve::get_underlying_amount_from_lp_amount(
                get_reserve_type_info(&vault.asset), shares
            );

        (pending_amount, deposited_amount, pending_amount + amount)
    }

    // Returns (current_tvl, total_deposited, total_withdrawn)
    #[view]
    public fun get_strategy_stats(asset: Object<Metadata>): (u128, u128, u128) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);

        let total_deposited = 0;
        let total_withdrawn = 0;
        let current_tvl = 0;
        strategy.vaults.for_each_ref(|_, v| {
            if (&v.asset == &asset) {
                total_deposited = total_deposited + v.total_deposited_amount;
                total_withdrawn = total_withdrawn + v.total_withdrawn_amount;

                let (_, asset_amount) = get_deposited_amount(v);
                current_tvl = current_tvl + (asset_amount as u128);
            };
        });

        (current_tvl, total_deposited, total_withdrawn)
    }

    fun init_strategy_account(): address {
        let account_addr = get_strategy_address();
        assert!(!exists<Strategy>(account_addr));

        let extend_ref =
            storage::create_child_object_with_phantom_owner(STRATEGY_ACCOUNT_SEED);
        let account_signer = object::generate_signer_for_extending(&extend_ref);
        move_to(
            &account_signer,
            Strategy { extend_ref, vaults: ordered_map::new() }
        );

        account_addr
    }

    fun get_strategy_signer(self: &Strategy): signer {
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

    fun get_account_data(account: &Object<WalletAccount>): AccountData {
        let account_data =
            if (wallet_account::strategy_data_exists<AccountData>(account)) {
                wallet_account::get_strategy_data<AccountData>(account)
            } else {
                AccountData { vaults: ordered_map::new() }
            };

        account_data
    }

    fun get_account_data_for_vault(
        self: &mut AccountData, vault_addr: address
    ): &mut VaultAsset {
        if (!self.vaults.contains(&vault_addr)) {
            self.vaults.add(
                vault_addr, VaultAsset { deposited_amount: 0, vault_shares: 0 }
            )
        };

        self.vaults.borrow_mut(&vault_addr)
    }

    public fun get_raw_account_data_for_vault(
        self: &AccountData, vault_addr: address
    ): (u64, u128) {
        if (!self.vaults.contains(&vault_addr)) {
            return (0, 0);
        };

        let data = self.vaults.borrow(&vault_addr);

        (data.deposited_amount, data.vault_shares)
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
    /// Return actual amount and shares, total shares before deposit
    fun deposit_to_aries(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u64, u64) {
        let (shares_before, _) = self.get_deposited_amount();
        let actual_amount =
            deposit_to_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        let (shares_after, _) = self.get_deposited_amount();
        assert!(shares_after >= shares_before);
        assert!(actual_amount <= amount);

        let shares = shares_after - shares_before;
        self.available_amount = self.available_amount - actual_amount;

        (actual_amount, shares, shares_before)
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
    /// Return received amount, burned shares, total shares before withdraw, repaied_amount
    fun withdraw_from_aries(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        vault_shares: u128
    ): (u64, u64, u64, u64) {
        let (_, loan_amount) = self.get_loan_amount();
        let repaid_amount = 0;
        if (loan_amount > 0) {
            let avail_amount = self.get_available_withdraw_amount();
            if (amount > avail_amount) {
                let (total_deposited_shares, total_deposited_amount) =
                    self.get_deposited_amount();
                let loan_amount =
                    aries::decimal::ceil_u64(aries::decimal::from_scaled_val(loan_amount));
                let (_, owned_deposited_amount) =
                    self.get_owned_deposited_amount(total_deposited_shares);
                assert!(total_deposited_amount > owned_deposited_amount);
                let repay_amount =
                    math64::ceil_div(
                        amount * loan_amount,
                        total_deposited_amount - owned_deposited_amount
                    );
                let (_repaid_amount, swapped_amount) =
                    self.repay_aries(strategy_signer, repay_amount);
                repaid_amount = _repaid_amount;
                if (swapped_amount > 0) {
                    // vault must be compounded again after repayment
                    self.compound_vault_impl(strategy_signer);
                }
            }
        };

        let (shares_before, total_deposited_amount) = self.get_deposited_amount();
        let dep_shares =
            self.get_deposit_shares_from_vault_shares(vault_shares, shares_before);
        amount = aries::reserve::get_underlying_amount_from_lp_amount(
            get_reserve_type_info(&self.asset), dep_shares
        );
        assert!(amount > 0);

        let amount =
            withdraw_from_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount,
                false
            );
        let (shares_after, _) = self.get_deposited_amount();
        assert!(shares_before >= shares_after);

        let shares = shares_before - shares_after;
        self.available_amount = self.available_amount + amount;

        (amount, shares, shares_before, repaid_amount)
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
                amount,
                false
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
        if (self.available_borrow_amount > 0) {
            let amount = self.available_borrow_amount;
            self.repay_aries(strategy_signer, amount);
        };

        let amount = 0;
        if (self.available_borrow_amount > 0) {
            let avail_amount = self.available_borrow_amount;
            let (_, amount_out) =
                self.swap_from_borrow_asset(strategy_signer, avail_amount);
            amount = amount + amount_out;
        };

        // compound borrowing rewards
        let reward_amount =
            compound_rewards<aries::reserve_config::BorrowFarming>(
                self, strategy_signer
            );
        amount = amount + reward_amount;
        let (total_shares, _) = self.get_deposited_amount();
        let (_, owned_deposited_amount, total_loan_amount) =
            self.get_vault_borrowing_state(total_shares);

        if (owned_deposited_amount <= total_loan_amount) {
            let vault_amount =
                math64::min(total_loan_amount - owned_deposited_amount, amount);
            if (vault_amount > 0) {
                let (shares, _, total_shares) =
                    self.deposit_to_aries(strategy_signer, vault_amount);
                self.owned_shares =
                    self.owned_shares + self.mint_vault_shares(shares, total_shares);

            };
        } else {
            let interest = owned_deposited_amount - total_loan_amount;
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

        amount
    }

    public fun get_vault_borrowing_state(
        self: &Vault, total_deposited_shares: u64
    ): (u64, u64, u64) {
        let (_, loan_amount) = self.get_loan_amount();
        let loan_amount =
            aries::decimal::ceil_u64(aries::decimal::from_scaled_val(loan_amount));

        let (_, owned_deposited_amount) =
            self.get_owned_deposited_amount(total_deposited_shares);

        let amount_to_repay =
            if (self.available_borrow_amount < loan_amount) {
                self.estimate_swap_amount_to_repay(
                    loan_amount - self.available_borrow_amount
                )
            } else { 0 };

        (loan_amount, owned_deposited_amount, amount_to_repay)
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

        math64::mul_div(amount, 9000, 10000) // 90% of available power
    }

    fun withdraw_from_aries_impl(
        caller: &signer,
        profile: vector<u8>,
        asset: &Object<Metadata>,
        amount: u64,
        allow_borrow: bool
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
                caller, profile, amount, allow_borrow
            );
        } else if (asset_addr == @usdt) {
            aries::controller::withdraw_fa<aries::fa_to_coin_wrapper::WrappedUSDT>(
                caller, profile, amount, allow_borrow
            );
        };

        let balance_after = primary_fungible_store::balance(addr, *asset);
        assert!(balance_after >= balance_before);

        balance_after - balance_before
    }

    fun max_borrow_amount(self: &Vault): u64 {
        let strategy_addr = get_strategy_address();
        let reserve_info = get_reserve_type_info(&self.borrow_asset);

        let amount =
            aries::profile::max_borrow_amount(strategy_addr, &self.name, reserve_info);
        amount * 90 / 100 // TODO: config percent
    }

    /// Returns amount, shares and loan amount
    fun borrow_from_aries(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u128, u128) {
        let borrowable_amount = self.max_borrow_amount();
        assert!(borrowable_amount >= amount);

        let (shares_before, loan_amount_before) = self.get_loan_amount();
        let amount =
            withdraw_from_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.borrow_asset,
                amount,
                true
            );
        let (shares_after, loan_amount_after) = self.get_loan_amount();
        assert!(loan_amount_after >= loan_amount_before);
        assert!(shares_after >= shares_before);

        let shares = shares_after - shares_before;
        let loan_amount = loan_amount_after - loan_amount_before;
        self.available_borrow_amount = self.available_borrow_amount + amount;

        (amount, shares, loan_amount)
    }

    fun borrow_and_deposit_impl(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ) {
        self.borrow_from_aries(strategy_signer, amount);
        assert!(self.available_borrow_amount > 0);
        let amount = self.available_borrow_amount;
        let (_, amount_out) = self.swap_from_borrow_asset(strategy_signer, amount);
        let (_, shares, total_shares) = self.deposit_to_aries(strategy_signer, amount_out);
        let vault_shares = self.mint_vault_shares(shares, total_shares);
        self.owned_shares = self.owned_shares + vault_shares;
    }

    /// Repays borrowed asset to Aries.
    /// Assumes that vault has been compounded.
    /// Returns repaid amount and swapped asset amount
    fun repay_aries(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u64) {
        let (_, loan_amount) = self.get_loan_amount();
        let loan_amount =
            aries::decimal::ceil_u64(aries::decimal::from_scaled_val(loan_amount));

        amount = math64::min(amount, loan_amount);
        if (amount == 0) {
            return (0, 0);
        };

        if (amount > self.available_borrow_amount) {
            let avail_amount = self.available_borrow_amount;
            let (repaid_amount, swapped_amount) =
                self.repay_aries(strategy_signer, avail_amount);
            let remaining_amount = amount - repaid_amount;

            if (repaid_amount == 0) {
                let req_amount = self.estimate_swap_amount_to_repay(amount);
                let avail_amount = self.get_avail_amount_without_pending_amount();
                if (req_amount > avail_amount) {
                    let withdraw_amount = req_amount - avail_amount;
                    let avail_withdraw_amount = self.get_available_withdraw_amount();
                    if (avail_withdraw_amount == 0) {
                        return (repaid_amount, swapped_amount);
                    };
                    withdraw_amount = math64::min(
                        withdraw_amount, avail_withdraw_amount
                    );

                    let (total_deposit_shares, _) = self.get_deposited_amount();
                    let shares =
                        aries::reserve::get_lp_amount_from_underlying_amount(
                            get_reserve_type_info(&self.asset), withdraw_amount
                        );
                    withdraw_amount = withdraw_from_aries_impl(
                        strategy_signer,
                        *self.name.bytes(),
                        &self.asset,
                        withdraw_amount,
                        false
                    );
                    self.available_amount = self.available_amount + withdraw_amount;
                    let vault_shares =
                        self.burn_vault_shares(shares, total_deposit_shares);
                    self.owned_shares =
                        if (self.owned_shares > vault_shares) {
                            self.owned_shares - vault_shares
                        } else { 0 };

                    req_amount = self.get_avail_amount_without_pending_amount();
                };

                let (amount_in, _) =
                    self.swap_from_vault_asset(strategy_signer, req_amount);

                swapped_amount = swapped_amount + amount_in;
            };

            let (_repaid_amount, _swapped_amount) =
                self.repay_aries(strategy_signer, remaining_amount);

            return (repaid_amount + _repaid_amount, swapped_amount + _swapped_amount);
        };

        let repaid_amount =
            deposit_to_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.borrow_asset,
                amount
            );
        self.available_borrow_amount = self.available_borrow_amount - repaid_amount;

        (repaid_amount, 0)
    }

    /// Returns amount of swapped vault asset and received borrow asset
    fun swap_from_vault_asset(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                &self.asset,
                &self.borrow_asset,
                amount,
                false
            );
        self.available_amount = self.available_amount - amount_in;
        self.available_borrow_amount = self.available_borrow_amount + amount_out;

        (amount_in, amount_out)
    }

    /// Returns amount of swapped vault asset and received borrow asset
    fun swap_to_borrow_asset(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                &self.asset,
                &self.borrow_asset,
                amount,
                true
            );
        self.available_amount = self.available_amount - amount_in;
        self.available_borrow_amount = self.available_borrow_amount + amount_out;

        (amount_in, amount_out)
    }

    /// Returns amount of swapped borrow asset and received vault asset
    fun swap_from_borrow_asset(
        self: &mut Vault, strategy_signer: &signer, amount: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                &self.borrow_asset,
                &self.asset,
                amount,
                false
            );
        self.available_amount = self.available_amount + amount_out;
        self.available_borrow_amount = self.available_borrow_amount - amount_in;

        (amount_in, amount_out)
    }

    /// estimate amount of vault asset needed to swap to repay_amount
    fun estimate_swap_amount_to_repay(self: &Vault, repay_amount: u64): u64 {
        let (pool, _, slippage) = get_hyperion_pool(&self.asset, &self.borrow_asset);
        let (amount_in, _) =
            hyperion::pool_v3::get_amount_in(pool, self.asset, repay_amount);

        math64::ceil_div(amount_in * (10000 + slippage), 10000)
    }

    /// estimate amount of borrow asset when swap from vault asset for repayment
    fun estimate_repay_amount(self: &Vault, amount: u64): u64 {
        let (pool, _, slippage) = get_hyperion_pool(&self.asset, &self.borrow_asset);
        let (amount_out, _) = hyperion::pool_v3::get_amount_out(pool, self.asset, amount);

        amount_out * (10000 - slippage) / 10000
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
        if (burned_deposit_shares == 0) {
            return 0;
        };

        let vault_shares =
            if (total_deposit_shares > 0) {
                math128::ceil_div(
                    self.total_shares * (burned_deposit_shares as u128),
                    (total_deposit_shares as u128)
                )
            } else {
                self.total_shares
            };
        self.total_shares =
            if (self.total_shares > vault_shares) {
                self.total_shares - vault_shares
            } else { 0 };

        vault_shares
    }

    public fun get_deposit_shares_from_vault_shares(
        self: &Vault, vault_shares: u128, total_deposit_shares: u64
    ): u64 {
        if (vault_shares == 0) {
            return 0;
        };

        if (self.total_shares == 0) {
            total_deposit_shares
        } else {
            math128::mul_div(
                vault_shares, total_deposit_shares as u128, self.total_shares
            ) as u64
        }
    }

    fun get_vault_shares_from_deposit_shares(
        self: &Vault, deposit_shares: u64, total_deposit_shares: u64
    ): u128 {
        if (total_deposit_shares == 0) {
            (deposit_shares as u128) * math128::pow(10, SHARE_DECIMALS as u128)
        } else {
            math128::mul_div(
                deposit_shares as u128, self.total_shares, total_deposit_shares as u128
            )
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

    /// Claims all rewards and swap to vault asset
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

    /// return (pool, fee_tier, slippage)
    fun get_hyperion_pool(
        asset_0: &Object<Metadata>, asset_1: &Object<Metadata>
    ): (Object<hyperion::pool_v3::LiquidityPoolV3>, u8, u64) {
        let addr_0 = object::object_address(asset_0);
        let addr_1 = object::object_address(asset_1);
        let (fee_tier, slippage) =
            if (addr_0 == APT_FA_ADDRESS || addr_1 == APT_FA_ADDRESS) {
                (1, 100) //  (0.05%, 1%)
            } else {
                (0, 50) // (0.01%, 0.5%)
            };
        let (exist, pool_addr) =
            hyperion::pool_v3::liquidity_pool_address_safe(*asset_0, *asset_1, fee_tier);
        assert!(exist, error::permission_denied(E_POOL_NOT_EXIST));

        let pool =
            object::address_to_object<hyperion::pool_v3::LiquidityPoolV3>(pool_addr);

        (pool, fee_tier, slippage)
    }

    /// Returns actual swapped amount and recived amount
    fun swap_with_hyperion(
        caller: &signer,
        from: &Object<Metadata>,
        to: &Object<Metadata>,
        amount: u64,
        exact_out: bool
    ): (u64, u64) {
        let strategy_addr = get_strategy_address();

        let (pool, fee_tier, slippage) = get_hyperion_pool(from, to);
        let (amount_in, amount_out) =
            if (exact_out) {
                let (amount_in, _) = hyperion::pool_v3::get_amount_in(
                    pool, *from, amount
                );
                amount_in = amount_in * (10000 + slippage) / 10000;
                (amount_in, amount)
            } else {
                let (amount_out, _) =
                    hyperion::pool_v3::get_amount_out(pool, *from, amount);
                amount_out = amount_out * (10000 - slippage) / 10000;
                (amount, amount_out)
            };

        // ignore price impact
        let sqrt_price_limit =
            if (hyperion::utils::is_sorted(*from, *to)) {
                04295048016 // min sqrt price
            } else {
                79226673515401279992447579055 // max sqrt price
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

    #[test_only]
    public fun init_module_for_testing(sender: &signer) {
        init_module(sender);
    }

    #[test_only]
    public fun get_strategy_signer_for_testing(): signer acquires Strategy {
        let strategy = borrow_global_mut<Strategy>(get_strategy_address());
        strategy.get_strategy_signer()
    }

    #[test_only]
    public fun get_shares_from_amount(
        asset: &Object<Metadata>, amount: u64
    ): u64 {
        aries::reserve::get_lp_amount_from_underlying_amount(
            get_reserve_type_info(asset), amount
        )
    }

    #[test_only]
    public fun get_vault_data<T>(self: &Vault, field: vector<u8>): T {
        if (field == b"name") {
            any::unpack<T>(any::pack(self.name))
        } else if (field == b"asset") {
            any::unpack<T>(any::pack(self.asset))
        } else if (field == b"borrow_asset") {
            any::unpack<T>(any::pack(self.borrow_asset))
        } else if (field == b"available_amount") {
            any::unpack<T>(any::pack(self.available_amount))
        } else if (field == b"available_borrow_amount") {
            any::unpack<T>(any::pack(self.available_borrow_amount))
        } else if (field == b"total_shares") {
            any::unpack<T>(any::pack(self.total_shares))
        } else if (field == b"owned_shares") {
            any::unpack<T>(any::pack(self.owned_shares))
        } else if (field == b"rewards") {
            any::unpack<T>(any::pack(self.rewards))
        } else if (field == b"pending_amount") {
            any::unpack<T>(any::pack(self.pending_amount))
        } else if (field == b"total_deposited_amount") {
            any::unpack<T>(any::pack(self.total_deposited_amount))
        } else if (field == b"total_withdrawn_amount") {
            any::unpack<T>(any::pack(self.total_withdrawn_amount))
        } else {
            abort(0);
            any::unpack<T>(any::pack(0))
        }
    }

    #[test(
        deployer = @moneyfi, aries_deployer = @aries, wallet1 = @0x111, wallet2 = @0x222
    )]
    fun test_vault_divide_deposited_amount(
        deployer: &signer,
        aries_deployer: &signer,
        wallet1: &signer,
        wallet2: &signer
    ) {
        aptos_framework::aptos_coin::ensure_initialized_with_apt_fa_metadata_for_test();

        aries::mock::init(aries_deployer);
        storage::init_module_for_testing(deployer);
        wallet_account::create_wallet_account_for_test(wallet1, b"wallet1", 0, vector[]);
        wallet_account::create_wallet_account_for_test(wallet2, b"wallet2", 0, vector[]);
        let addr1 = wallet_account::get_wallet_account_object_address(b"wallet1");
        let addr2 = wallet_account::get_wallet_account_object_address(b"wallet2");

        aries::mock::on(b"profile::get_profile_address", @0xabc, 999);

        let asset = object::address_to_object<Metadata>(@0xa);
        let borrow_asset = object::address_to_object<Metadata>(@0xa);
        let name = string::utf8(b"test_vault");
        let vault = Vault {
            name,
            deposit_cap: U64_MAX,
            asset: asset,
            borrow_asset: borrow_asset,
            available_amount: 20,
            available_borrow_amount: 0,
            total_shares: 0,
            owned_shares: 0,
            rewards: ordered_map::new(),
            pending_amount: ordered_map::new_from(vector[addr1, addr2], vector[10, 20]),
            total_deposited_amount: 0,
            total_withdrawn_amount: 0,
            paused: false
        };

        vault.divide_deposited_amount(10, 30, 0);

        assert!(*vault.pending_amount.borrow(&addr1) == 7);
        assert!(*vault.pending_amount.borrow(&addr2) == 13);
    }
}

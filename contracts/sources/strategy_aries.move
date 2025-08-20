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
        deposit_cap: u64,
        // accumulated deposited amount
        total_deposited_amount: u128,
        // accumulated withdrawn amount
        total_withdrawn_amount: u128,
        // unused amount, includes: pending deposited amount, dust when counpound reward, swap assets
        available_amount: u64,
        rewards: OrderedMap<address, u64>,
        // asset address => available amount
        borrow_assets: OrderedMap<address, u64>,
        // amount deposited from wallet account but not yet deposited to Aries
        pending_amount: OrderedMap<address, u64>,
        // shares minted by vault for wallet account
        total_shares: u128,
        paused: bool
    }

    /// Track asset of an account in vault
    struct VaultAsset has copy, store, drop {
        // amount deposited to aries
        deposited_amount: u64,
        // unused amount
        available_amount: u64,
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
        sender: &signer, name: String, asset: Object<Metadata>
    ) acquires Strategy {
        access_control::must_be_service_account(sender);
        assert!(!name.is_empty());

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
                deposit_cap: U64_MAX,
                available_amount: 0,
                total_deposited_amount: 0,
                total_withdrawn_amount: 0,
                rewards: ordered_map::new(),
                borrow_assets: ordered_map::new(),
                pending_amount: ordered_map::new(),
                total_shares: 0,
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
    public entry fun vault_deposit(
        sender: &signer, vault_name: String, amount: u64
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();
        let vault = strategy.get_vault_mut(vault_name);

        vault.compound_vault_rewards(strategy_signer);
        let total_pending_amount = 0;
        vault.pending_amount.for_each_ref(|_, v| {
            total_pending_amount = total_pending_amount + *v;
        });
        if (amount > total_pending_amount) {
            let (deposited_amount, _) =
                vault.deposit_to_aries(strategy_signer, amount - total_pending_amount);
            amount = math64::min(total_pending_amount, amount - deposited_amount);
        };
        let (total_shares, _) = vault.get_deposited_amount();
        let (deposited_amount, shares) = vault.deposit_to_aries(strategy_signer, amount);

        let vault_shares =
            if (vault.total_shares == 0) {
                (shares as u128) * math128::pow(10, SHARE_DECIMALS as u128)
            } else {
                (shares as u128) * math128::pow(10, SHARE_DECIMALS as u128)
                    * vault.total_shares / (total_shares as u128)
            };

        let will_removes = vector[];
        vault.pending_amount.for_each_mut(|k, v| {
            let acc_deposited_amount = *v * deposited_amount / total_pending_amount;
            let acc_vault_shares = (*v as u128) * vault_shares
                / (total_pending_amount as u128);
            *v = *v - acc_deposited_amount;
            if (*v == 0) {
                will_removes.push_back(*k);
            };

            let vault_addr = get_vault_address(vault_name);
            let account = object::address_to_object<WalletAccount>(*k);
            let account_data = get_account_data_for_vault(&account, vault_addr);
            let vault_asset = account_data.borrow_mut(&vault_addr);
            vault_asset.deposited_amount =
                vault_asset.deposited_amount + acc_deposited_amount;
            vault_asset.available_amount =
                vault_asset.available_amount - acc_deposited_amount;
            vault_asset.vault_shares = vault_asset.vault_shares + acc_vault_shares;

        });

        will_removes.for_each_ref(|k| {
            vault.pending_amount.remove(k);
        });

        // TODO: emit an event if needed
    }

    /// Withdraw fund from Aries back to vault
    // public entry fun vault_withdraw(
    //     sender: &signer,
    //     vault_name: String,
    //     amount: u64,
    //     swap_slippage: u64
    // ) acquires Strategy {
    //     access_control::must_be_service_account(sender);

    //     let strategy_addr = get_strategy_address();
    //     let strategy = borrow_global_mut<Strategy>(strategy_addr);
    //     let strategy_signer = strategy.get_account_signer();
    //     let vault = strategy.get_vault_mut(vault_name);

    //     let (_, total_amount) = vault.get_deposited_amount();
    //     amount =
    //         if (amount <= total_amount) { amount }
    //         else {
    //             total_amount
    //         };

    //     vault.withdraw_from_aries(&strategy_signer, amount, swap_slippage);

    //     // TODO: emit an event if needed
    // }

    public entry fun borrow_and_deposit(
        sender: &signer,
        vault_name: String,
        borrow_asset: Object<Metadata>,
        amount: u64,
        swap_slippage: u64
    ) {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();
        let vault = strategy.get_vault_mut(vault_name);

        vault.borrow_and_deposit_impl(
            strategy_signer, &borrow_asset, amount, swap_slippage
        );

        // TODO: emit an event if needed
    }

    public entry fun compound_rewards(sender: &signer, vault_name: String) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();
        let vault = strategy.get_vault_mut(vault_name);

        vault.compound_vault_rewards(&strategy_signer);

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
    public fun get_borrowable_amount(
        vault_name: String, asset: Object<Metadata>
    ): u64 {
        let strategy_addr = get_strategy_address();
        let reserve_info = get_reserve_type_info(&asset);
        aries::profile::max_borrow_amount(strategy_addr, &vault_name, reserve_info)
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
        let account_addr = object::object_address(account);
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
        if (!vault.pending_amount.contains(&account_addr)) {
            vault.pending_amount.add(account_addr, 0);
        };
        let pending_amount = vault.pending_amount.borrow_mut(&account_addr);
        *pending_amount = *pending_amount + amount;

        let vault_addr = get_vault_address(vault_name);
        let account_data = get_account_data_for_vault(account, vault_addr);
        let vault_asset = account_data.borrow_mut(&vault_addr);

        vault_asset.available_amount = vault_asset.available_amount + amount;
        wallet_account::set_strategy_data(account, account_data);

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
        assert!(extra_data.length() > 0);

        // TODO: check rate limit

        let vault_name = from_bcs::to_string(*extra_data.borrow(0));
        let swap_slippage = from_bcs::to_u64(*extra_data.borrow(1));
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = &strategy.get_account_signer();

        let vault_addr = get_vault_address(vault_name);
        let account_data = get_account_data_for_vault(account, vault_addr);
        let vault_asset = account_data.borrow_mut(&vault_addr);

        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);
        assert!(&vault.asset == asset);

        let deposited_amount = amount;
        if (amount > vault_asset.available_amount) {
            vault.compound_vault_rewards(strategy_signer);

            let reserve_type = get_reserve_type_info(asset);
            let acc_deposit_shares =
                vault.get_deposit_shares_from_vault_shares(vault_asset.vault_shares);
            let withdraw_amount =
                if (amount == U64_MAX) {
                    aries::reserve::get_underlying_amount_from_lp_amount(
                        reserve_type, acc_deposit_shares
                    )
                } else {
                    let withdraw_amount = amount - vault_asset.available_amount;
                    let shares =
                        aries::reserve::get_lp_amount_from_underlying_amount(
                            reserve_type, withdraw_amount
                        );
                    assert!(shares <= acc_deposit_shares);

                    withdraw_amount
                };
            let (total_deposit_shares, _) = vault.get_deposited_amount();
            let (amount, burned_shares) =
                vault.withdraw_from_aries(strategy_signer, withdraw_amount, swap_slippage);
            vault_asset.available_amount = vault_asset.available_amount + amount;
            let dep_amount =
                math64::mul_div(
                    vault_asset.deposited_amount, burned_shares, acc_deposit_shares
                );
            vault_asset.deposited_amount =
                if (vault_asset.deposited_amount > dep_amount) {
                    vault_asset.deposited_amount - dep_amount
                } else { 0 };
            let burned_vault_shares =
                vault.total_shares * (burned_shares as u128)
                    / (total_deposit_shares as u128);
            vault_asset.vault_shares = vault_asset.vault_shares - burned_vault_shares;
            vault.total_shares = vault.total_shares - burned_vault_shares;
            deposited_amount = deposited_amount + dep_amount;
        };
        assert!(vault_asset.available_amount >= amount);

        let vault = strategy.get_vault_mut(vault_name);
        let account_addr = object::object_address(account);
        primary_fungible_store::transfer(
            strategy_signer,
            vault.asset,
            account_addr,
            amount
        );
        vault_asset.available_amount = vault_asset.available_amount - amount;
        vault_asset.deposited_amount =
            if (vault_asset.deposited_amount > deposited_amount) {
                vault_asset.deposited_amount - deposited_amount
            } else { 0 };

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

    fun get_account_data_for_vault(
        account: &Object<WalletAccount>, vault_addr: address
    ): OrderedMap<address, VaultAsset> {
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

        if (!account_data.contains(&vault_addr)) {
            account_data.add(
                vault_addr,
                VaultAsset { deposited_amount: 0, available_amount: 0, vault_shares: 0 }
            )
        };

        account_data
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
    /// Return received amount and burned shares
    fun withdraw_from_aries(
        self: &mut Vault,
        strategy_signer: &signer,
        amount: u64,
        swap_slippage: u64
    ): (u64, u64) {
        let avail_amount = self.get_available_withdraw_amount();
        let (borrow_asset_opt, borrow_shares, loan_amount) = self.get_loan();
        // repay until enough amount to withdraw
        while (avail_amount < amount && borrow_shares > 0) {
            self.withdraw_from_aries(strategy_signer, avail_amount, swap_slippage);

            let borrow_asset =
                object::address_to_object<Metadata>(borrow_asset_opt.extract());
            let est_repay_amount =
                estimate_repay_amount(
                    &self.asset,
                    &borrow_asset,
                    avail_amount,
                    swap_slippage
                );
            let repay_amount =
                math64::min(
                    est_repay_amount,
                    aries::decimal::ceil_u64(aries::decimal::from_scaled_val(loan_amount))
                );
            self.repay_aries(
                strategy_signer, &borrow_asset, repay_amount, swap_slippage
            );

            (borrow_asset_opt, borrow_shares, loan_amount) = self.get_loan();
            avail_amount = self.get_available_withdraw_amount();
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

    fun get_available_withdraw_amount(self: &Vault): u64 {
        let strategy_addr = get_strategy_address();
        let avail_power =
            aries::profile::available_borrowing_power(strategy_addr, &self.name);
        let price = get_asset_price(&self.asset);
        let amount = aries::decimal::as_u64(aries::decimal::div(avail_power, price));

        amount - amount * 5 / 100 // 95% of available power
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

    /// Returns amount, shares and loan amount
    fun borrow_from_aries(
        self: &mut Vault,
        strategy_signer: &signer,
        asset: &Object<Metadata>,
        amount: u64
    ): (u64, u128, u128) {
        assert!(asset != &self.asset);
        let borrowable_amount = get_borrowable_amount(self.name, *asset);
        assert!(borrowable_amount > amount);

        let (shares_before, loan_amount_before) = self.get_loan_amount(asset);
        let amount =
            withdraw_from_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        let (shares_after, loan_amount_after) = self.get_loan_amount(asset);
        assert!(loan_amount_after >= shares_after);
        assert!(shares_after >= shares_before);

        let shares = shares_before - shares_after;
        let loan_amount = loan_amount_after - loan_amount_before;
        let borrowed_amount = self.get_borrow_asset_mut(asset);
        *borrowed_amount = *borrowed_amount + amount;

        (amount, shares, loan_amount)
    }

    fun borrow_and_deposit_impl(
        self: &mut Vault,
        strategy_signer: &signer,
        asset: &Object<Metadata>,
        amount: u64,
        swap_slippage: u64
    ) {
        self.borrow_from_aries(strategy_signer, asset, amount);
        let borrowed_amount = self.get_borrow_asset(asset);
        assert!(borrowed_amount > 0);
        // we will swap all borrowed amount
        let (_, amount_out) =
            self.swap_from_borrow_asset(
                strategy_signer, asset, borrowed_amount, swap_slippage
            );
        self.deposit_to_aries(strategy_signer, amount_out);
    }

    /// Repays borrowed asset to Aries. Requires sufficient available amount.
    /// Returns actual amount, remaining borrow shares and loan amount
    fun repay_aries(
        self: &mut Vault,
        strategy_signer: &signer,
        asset: &Object<Metadata>,
        amount: u64,
        swap_slippage: u64
    ): (u64, u128, u128) {
        assert!(asset != &self.asset);
        let (shares, loan_amount) = self.get_loan_amount(asset);
        let amount =
            if (aries::decimal::raw(aries::decimal::from_u64(amount)) <= loan_amount) {
                amount
            } else {
                aries::decimal::ceil_u64(
                    aries::reserve::get_borrow_amount_from_share_dec(
                        get_reserve_type_info(asset),
                        aries::decimal::from_scaled_val(shares)
                    )
                )
            };

        let avail_amount = self.get_borrow_asset(asset);
        if (amount > avail_amount) {
            let amount_in =
                estimate_swap_amount_to_repay(
                    &self.asset,
                    asset,
                    amount - avail_amount,
                    swap_slippage
                );
            if (amount_in > 0) {
                assert!(amount_in <= self.available_amount);
                self.swap_to_borrow_asset(
                    strategy_signer, asset, amount_in, swap_slippage
                );
            }
        };

        let (shares_before, _) = self.get_loan_amount(asset);
        assert!(shares_before > 0);
        let amount =
            deposit_to_aries_impl(
                strategy_signer,
                *self.name.bytes(),
                &self.asset,
                amount
            );
        let (shares_after, loan_amount_after) = self.get_loan_amount(asset);
        let avail_amount = self.get_borrow_asset_mut(asset);
        *avail_amount = *avail_amount - amount;

        (amount, shares_after, loan_amount_after)
    }

    /// Returns amaount of swapped vault asset and received borrow asset
    fun swap_to_borrow_asset(
        self: &mut Vault,
        strategy_signer: &signer,
        asset: &Object<Metadata>,
        amount: u64,
        slippage: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                &self.asset,
                asset,
                amount,
                slippage,
                true
            );
        self.available_amount = self.available_amount - amount_in;

        let avail_amount = self.get_borrow_asset_mut(asset);
        *avail_amount = *avail_amount + amount_out;

        (amount_in, amount_out)
    }

    /// Returns amaount of swapped borrow asset and received vault asset
    fun swap_from_borrow_asset(
        self: &mut Vault,
        strategy_signer: &signer,
        asset: &Object<Metadata>,
        amount: u64,
        slippage: u64
    ): (u64, u64) {
        let (amount_in, amount_out) =
            swap_with_hyperion(
                strategy_signer,
                asset,
                &self.asset,
                amount,
                slippage,
                false
            );
        self.available_amount = self.available_amount + amount_out;

        let avail_amount = self.get_borrow_asset_mut(asset);
        *avail_amount = *avail_amount - amount_in;

        (amount_in, amount_out)
    }

    fun estimate_swap_amount_to_repay(
        vault_asset: &Object<Metadata>,
        borrow_asset: &Object<Metadata>,
        repay_amount: u64,
        slippage: u64
    ): u64 {
        let (_, pool) = get_hyperion_pool(vault_asset, borrow_asset);
        let (amount_in, _) =
            hyperion::pool_v3::get_amount_in(pool, *borrow_asset, repay_amount);

        amount_in + amount_in * slippage / 10000
    }

    fun estimate_repay_amount(
        vault_asset: &Object<Metadata>,
        borrow_asset: &Object<Metadata>,
        vault_asset_amount: u64,
        slippage: u64
    ): u64 {
        let (_, pool) = get_hyperion_pool(vault_asset, borrow_asset);
        let (amount_out, _) =
            hyperion::pool_v3::get_amount_out(pool, *borrow_asset, vault_asset_amount);

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

    fun get_borrow_asset(self: &Vault, asset: &Object<Metadata>): u64 {
        let addr = object::object_address(asset);
        if (self.borrow_assets.contains(&addr)) {
            *self.borrow_assets.borrow(&addr)
        } else { 0 }
    }

    fun get_borrow_asset_mut(self: &mut Vault, asset: &Object<Metadata>): &mut u64 {
        let addr = object::object_address(asset);
        if (!self.borrow_assets.contains(&addr)) {
            self.borrow_assets.add(addr, 0);
        };

        self.borrow_assets.borrow_mut(&addr)
    }

    fun get_deposit_shares_from_vault_shares(
        self: &Vault, vault_shares: u128
    ): u64 {
        let (deposit_shares, _) = self.get_deposited_amount();

        if (self.total_shares == 0) {
            deposit_shares
        } else {
            (vault_shares * (deposit_shares as u128) / self.total_shares) as u64
        }
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
    fun get_loan_amount(self: &Vault, asset: &Object<Metadata>): (u128, u128) {
        let strategy_addr = get_strategy_address();

        let asset_addr = object::object_address(asset);
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

    /// Returns the first loan if exists
    fun get_loan(self: &Vault): (Option<address>, u128, u128) {
        if (self.borrow_assets.is_empty()) {
            return (option::none(), 0, 0);
        };

        let (k, _) = self.borrow_assets.borrow_front();
        while (true) {
            let (shares, amount) =
                self.get_loan_amount(&object::address_to_object<Metadata>(*k));
            if (shares > 0) {
                return (option::some(*k), shares, amount);
            };

            let next = self.borrow_assets.next_key(k);
            if (next.is_none()) {
                return (option::none(), 0, 0);
            };

            k = next.borrow();
        };

        (option::none(), 0, 0)
    }

    fun compound_vault_rewards(
        self: &mut Vault, strategy_signer: &signer
    ): u64 {
        let asset = self.asset;
        self.claim_rewards(strategy_signer);

        // NOTE: only handle APT reward for now
        let apt_amount = self.get_reward_mut(APT_FA_ADDRESS);
        if (*apt_amount < 100_000_000) { // 1APT
            return 0;
        };

        let apt_reward = object::address_to_object<Metadata>(APT_FA_ADDRESS);
        let (in_amount, out_amount) =
            swap_with_hyperion(
                strategy_signer,
                &apt_reward,
                &asset,
                *apt_amount,
                50,
                false
            );
        *apt_amount = *apt_amount - in_amount;

        if (out_amount > 0) {
            self.available_amount = self.available_amount + out_amount;
            self.deposit_to_aries(strategy_signer, out_amount);
        };

        out_amount
    }

    fun claim_rewards(self: &mut Vault, strategy_signer: &signer) {
        let strategy_addr = get_strategy_address();

        // TODO: handle other rewards
        let reward = object::address_to_object<Metadata>(APT_FA_ADDRESS);
        let balance_before = primary_fungible_store::balance(strategy_addr, reward);
        aries::wrapped_controller::claim_rewards<AptosCoin>(strategy_signer, self.name);
        let balance_after = primary_fungible_store::balance(strategy_addr, reward);

        let amount =
            if (balance_after > balance_before) {
                balance_after - balance_before
            } else { 0 };

        if (amount > 0) {
            let reward_amount = self.get_reward_mut(APT_FA_ADDRESS);
            *reward_amount = *reward_amount + amount;
        }
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

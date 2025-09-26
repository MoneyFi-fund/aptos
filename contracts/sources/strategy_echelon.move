module moneyfi::strategy_echelon {
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use aptos_std::math64;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::error;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::coin;

    use lending::farming;
    use lending::scripts::{Self, Notacoin};
    use lending::lending::{Self, Market};
    use thala_lsd::staking::ThalaAPT;
    use fixed_point64::fixed_point64::{Self, FixedPoint64};

    use moneyfi::access_control;
    use moneyfi::storage;
    use moneyfi::vault as moneyfi_vault;
    use moneyfi::wallet_account::{Self, WalletAccount};

    friend moneyfi::strategy_echelon_tapp;

    const STRATEGY_ACCOUNT_SEED: vector<u8> = b"strategy_echelon::STRATEGY_ACCOUNT";

    const U64_MAX: u64 = 18446744073709551615;
    const HEALTH_FACTOR_DENOMINATOR: u64 = 10000;
    const SHARE_DECIMALS: u64 = 8;

    const E_VAULT_EXISTS: u64 = 1;
    const E_EXCEED_CAPACITY: u64 = 2;
    const E_UNSUPPORTED_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;
    const E_VAULT_NOT_EXISTS: u64 = 5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Strategy has key {
        extend_ref: ExtendRef,
        vaults: OrderedMap<String, Object<Vault>> // vault name => object vault
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Vault has key {
        name: String,
        extend_ref: ExtendRef,
        market: Object<Market>,
        asset: Object<Metadata>,
        borrow_market: Object<Market>,
        deposit_cap: u64,
        // accumulated deposited amount
        total_deposited_amount: u128,
        // accumulated withdrawn amount
        total_withdrawn_amount: u128,
        // unused amount, includes: pending deposited amount, dust when counpound reward, swap assets
        available_amount: u64,
        rewards: OrderedMap<address, u64>,
        // amount deposited from wallet account but not yet deposited to Aries
        pending_amount: OrderedMap<address, u64>,
        // shares minted by vault for wallet account
        total_shares: u128,
        // config health factor for borrow
        health_factor: u64,
        paused: bool
    }

    struct VaultData has copy, store, drop {
        name: String,
        asset: Object<Metadata>,
        borrow_asset: Object<Metadata>,
        deposit_cap: u64,
        total_deposited_amount: u128,
        total_withdrawn_amount: u128,
        available_amount: u64,
        pending_amount: OrderedMap<address, u64>,
        health_factor: u64,
        paused: bool
    }

    struct RewardInfo has key {
        supply_reward_id: u64,
        borrow_reward_id: u64
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
        name: String,
        asset: address,
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
        market: Object<Market>,
        asset: Object<Metadata>,
        borrow_market: Object<Market>,
        reward: vector<address>, // reward token addresses
        supply_reward_id: u64,
        borrow_reward_id: u64,
        health_factor: u64
    ) acquires Strategy {
        access_control::must_be_service_account(sender);
        let vault_addr = storage::get_child_object_address(*name.bytes());
        // unsupported borrow other asset in this version
        assert!(market == borrow_market, error::invalid_argument(E_UNSUPPORTED_ASSET));

        assert!(
            !exists<Vault>(vault_addr),
            error::already_exists(E_VAULT_EXISTS)
        );
        let reward_map = ordered_map::new();
        vector::for_each(
            reward,
            |reward_addr| {
                ordered_map::add(&mut reward_map, reward_addr, 0);
            }
        );
        let extend_ref = storage::create_child_object_with_phantom_owner(*name.bytes());
        let vault_signer = object::generate_signer_for_extending(&extend_ref);
        move_to(
            &vault_signer,
            Vault {
                name,
                extend_ref,
                market,
                asset,
                borrow_market,
                deposit_cap: U64_MAX,
                total_deposited_amount: 0,
                total_withdrawn_amount: 0,
                available_amount: 0,
                rewards: reward_map,
                pending_amount: ordered_map::new(),
                total_shares: 0,
                health_factor,
                paused: false
            }
        );
        move_to(
            &vault_signer,
            RewardInfo { supply_reward_id, borrow_reward_id }
        );
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        ordered_map::add(
            &mut strategy.vaults, name, object::address_to_object<Vault>(vault_addr)
        );
        event::emit(
            VaultCreatedEvent {
                name,
                asset: object::object_address(&asset),
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun config_vault(
        sender: &signer,
        name: String,
        emode: Option<u8>,
        deposit_cap: u64,
        new_rewards: vector<address>,
        health_factor: u64,
        paused: bool
    ) acquires Strategy, Vault {
        access_control::must_be_service_account(sender);
        let object_vault = get_vault_object(name);
        let vault = get_vault_mut(&object_vault);
        let vault_signer = vault.get_vault_signer();

        vault.deposit_cap = deposit_cap;
        vault.paused = paused;
        vault.health_factor = health_factor;

        if (option::is_some(&emode)) {
            let emode = option::borrow(&emode);
            lending::user_enter_efficiency_mode(&vault_signer, *emode);
        } else {
            lending::user_quit_efficiency_mode(&vault_signer);
        };
        if (!new_rewards.is_empty()) {
            vector::for_each(
                new_rewards,
                |reward| {
                    ordered_map::add(&mut vault.rewards, reward, 0);
                }
            )
        };
    }

    public fun estimate_repay_amount_from_withdraw_amount(
        name: String, withdraw_amount: u64
    ): u64 acquires Vault, Strategy {
        let vault = get_vault_data(&get_vault_object(name));
        let vault_addr = vault_address(vault.name);
        vault.estimate_repay_amount_from_withdraw_amount_inline(
            vault_addr, withdraw_amount
        )
    }

    public fun estimate_repay_amount_from_account_withdraw_amount(
        name: String, wallet_id: vector<u8>, withdraw_amount: u64
    ): u64 acquires Vault, Strategy {
        let vault = get_vault_data(&get_vault_object(name));
        let vault_addr = vault_address(vault.name);

        // Get account data
        let account = &wallet_account::get_wallet_account(wallet_id);
        let account_data = get_account_data(account);
        let account_vault_data = account_data.get_account_data_for_vault(vault_addr);

        // Get pending amount for this account
        let pending_amount = vault.get_pending_amount(account);

        if (withdraw_amount <= pending_amount) {
            // If withdrawing only from pending amount, no repayment needed
            return 0;
        };

        // Calculate how much needs to be withdrawn from deposited amount
        let withdraw_from_deposited = withdraw_amount - pending_amount;

        // Get total deposited amounts and shares
        let (total_deposit_shares, _) = vault.get_deposited_amount();

        // Convert withdraw amount to deposit shares
        let deposit_shares =
            lending::coins_to_shares(vault.market, withdraw_from_deposited);

        // Calculate vault shares needed
        let vault_shares =
            vault.get_vault_shares_from_deposit_shares(
                deposit_shares, total_deposit_shares
            );

        // Check if account has sufficient vault shares
        if (vault_shares > account_vault_data.vault_shares) {
            vault_shares = account_vault_data.vault_shares;
            deposit_shares = vault.get_deposit_shares_from_vault_shares(
                vault_shares, total_deposit_shares
            );
            withdraw_from_deposited =
                if (deposit_shares > 0) {
                    lending::shares_to_coins(vault.market, deposit_shares)
                } else { 0 };
        };

        // If no actual withdrawal from deposited amount, no repayment needed
        if (withdraw_from_deposited == 0) {
            return 0;
        };

        // Use the existing estimate function for the actual withdrawal amount
        vault.estimate_repay_amount_from_withdraw_amount_inline(
            vault_addr, withdraw_from_deposited
        )
    }

    #[view]
    public fun get_strategy_address(): address {
        storage::get_child_object_address(STRATEGY_ACCOUNT_SEED)
    }

    #[view]
    public fun get_vaults(): (vector<address>, vector<String>) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        let addresses = vector::empty<address>();
        let names = vector::empty<String>();
        strategy.vaults.for_each_ref(|k, v| {
            vector::push_back(&mut addresses, object::object_address(v));
            vector::push_back(&mut names, *k);
        });

        (addresses, names)
    }

    #[view]
    public fun get_vault(name: String): (address, VaultData) acquires Strategy, Vault {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        assert!(
            ordered_map::contains(&strategy.vaults, &name),
            error::not_found(E_VAULT_NOT_EXISTS)
        );
        let vault_addr = vault_address(name);
        let vault = get_vault_data(&get_vault_object(name));
        (vault_addr, VaultData{
            name: vault.name,
            asset: vault.asset,
            borrow_asset: lending::market_asset_metadata(vault.borrow_market),
            deposit_cap: vault.deposit_cap,
            total_deposited_amount: vault.total_deposited_amount,
            total_withdrawn_amount: vault.total_withdrawn_amount,
            available_amount: vault.available_amount,
            pending_amount: vault.pending_amount,
            health_factor: vault.health_factor,
            paused: vault.paused
        })
    }

    // Returns (current_tvl, total_deposited, total_withdrawn)
    #[view]
    public fun get_strategy_stats(asset: Object<Metadata>): (u128, u128, u128) acquires Strategy, Vault {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);

        let total_deposited = 0;
        let total_withdrawn = 0;
        let current_tvl = 0;
        strategy.vaults.for_each_ref(|_, v| {
            let vault = get_vault_data(v);
            if (&vault.asset == &asset) {
                total_deposited = total_deposited + vault.total_deposited_amount;
                total_withdrawn = total_withdrawn + vault.total_withdrawn_amount;
                let borrow_tvl = {
                    let loan_amount = vault.get_loan_amount();
                    let amount_out =
                        if (loan_amount > 0) {
                            get_amount_out(
                                &lending::market_asset_metadata(vault.borrow_market),
                                &vault.asset,
                                loan_amount
                            )
                        } else { 0 };
                    amount_out as u128
                };
                let (_, asset_amount) = vault.get_deposited_amount();
                current_tvl = current_tvl + (asset_amount as u128) + borrow_tvl;
            };
        });

        (current_tvl, total_deposited, total_withdrawn)
    }

    #[view]
    public fun vault_address(name: String): address acquires Strategy {
        object::object_address(&get_vault_object(name))
    }

    #[view]
    public fun vault_asset(name: String): Object<Metadata> acquires Strategy, Vault {
        let vault = get_vault_data(&get_vault_object(name));
        vault.asset
    }

    #[view]
    public fun vault_borrow_asset(name: String): Object<Metadata> acquires Strategy, Vault {
        let vault = get_vault_data(&get_vault_object(name));
        lending::market_asset_metadata(vault.borrow_market)
    }

    #[view]
    public fun max_borrowable_amount(name: String): u64 acquires Strategy, Vault {
        let vault = get_vault_data(&get_vault_object(name));
        vault.borrowable_amount_given_health_factor(vault.health_factor)
    }

    #[view]
    public fun vault_borrow_amount(name: String): u64 acquires Strategy, Vault {
        let vault = get_vault_data(&get_vault_object(name));
        vault.get_loan_amount()
    }

    /// deposit fund from wallet account to strategy vault
    public(friend) fun deposit(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64
    ) acquires Strategy, Vault {
        assert!(amount > 0);
        access_control::must_be_service_account(sender);
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();
        let object_vault = get_vault_object(vault_name);
        let vault = get_vault_mut(&object_vault);
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
        primary_fungible_store::transfer(
            &strategy_signer,
            vault.asset,
            object::object_address(&object_vault),
            amount
        );
        vault.total_deposited_amount = vault.total_deposited_amount + (amount as u128);
        vault.available_amount = vault.available_amount + amount;
        vault.update_pending_amount(&account, amount, 0);
    }

    /// Withdraw fund from strategy vault to wallet account
    /// Pass amount = U64_MAX to withdraw all
    public(friend) fun withdraw(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64,
        gas_fee: u64,
        hook_data: vector<u8>
    ) acquires Strategy, Vault, RewardInfo {
        assert!(amount > 0);
        access_control::must_be_service_account(sender);
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();

        let object_vault = get_vault_object(vault_name);
        let vault = get_vault_mut(&object_vault);
        let vault_addr = vault_address(vault.name);
        assert!(!vault.paused);

        let account = &wallet_account::get_wallet_account(wallet_id);
        let account_data = get_account_data(account);
        let account_vault_data = account_data.get_account_data_for_vault(vault_addr);

        let deposited_amount = amount;
        let pending_amount = vault.get_pending_amount(account);
        if (amount > pending_amount) {
            // need compound tapp reward first if borrow and deposit to tapp
            vault.compound_vault_rewards();
            let withdraw_amount = amount - pending_amount;
            amount = pending_amount;
            deposited_amount = amount;
            let (total_deposit_shares, _) = vault.get_deposited_amount();
            let deposit_shares = lending::coins_to_shares(vault.market, withdraw_amount);
            let vault_shares =
                vault.get_vault_shares_from_deposit_shares(
                    deposit_shares, total_deposit_shares
                );
            if (vault_shares > account_vault_data.vault_shares) {
                vault_shares = account_vault_data.vault_shares;
                deposit_shares = vault.get_deposit_shares_from_vault_shares(
                    vault_shares, total_deposit_shares
                );
                withdraw_amount =
                    if (deposit_shares > 0) {
                        lending::shares_to_coins(vault.market, deposit_shares)
                    } else { 0 };
            };
            if (vault_shares > 0 && withdraw_amount > 0) {
                let (withdrawn_amount, _, _, _) =
                    vault.withdraw_from_echelon(withdraw_amount);

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

                vault.total_shares =
                    if (vault.total_shares > vault_shares) {
                        vault.total_shares - vault_shares
                    } else { 0 };

                account_vault_data.vault_shares =
                    if (account_vault_data.vault_shares > vault_shares) {
                        account_vault_data.vault_shares - vault_shares
                    } else { 0 };

                deposited_amount = deposited_amount + dep_amount;
                amount = amount + withdrawn_amount;
                vault.update_pending_amount(account, withdrawn_amount, 0);
            }
        };
        let account_addr = object::object_address(account);
        primary_fungible_store::transfer(
            &vault.get_vault_signer(),
            vault.asset,
            account_addr,
            amount
        );
        vault.update_pending_amount(account, 0, amount);
        vault.available_amount = vault.available_amount - amount;
        vault.total_withdrawn_amount = vault.total_withdrawn_amount + (amount as u128);

        wallet_account::set_strategy_data(account, account_data);

        moneyfi_vault::withdrawn_from_strategy_with_hook_data<Strategy>(
            &strategy_signer,
            wallet_id,
            vault.asset,
            deposited_amount,
            amount,
            0,
            gas_fee,
            hook_data
        );
    }

    /// Deposits fund from vault to Echelon
    /// Pass amount = U64_MAX to deposit all pending amount
    public(friend) fun vault_deposit_echelon(
        sender: &signer, vault_name: String, amount: u64
    ) acquires Strategy, Vault, RewardInfo {
        assert!(amount > 0);
        access_control::must_be_service_account(sender);
        let object_vault = get_vault_object(vault_name);
        let vault = get_vault_mut(&object_vault);
        assert!(!vault.paused);
        // need compound tapp reward first if borrow and deposit to tapp
        vault.compound_vault_rewards();

        let total_pending_amount = vault.get_total_pending_amount();
        if (amount > total_pending_amount) {
            amount = total_pending_amount;
        };

        let (deposited_amount, deposited_shares, total_deposit_shares) =
            vault.deposit_to_echelon(amount);

        let vault_shares = vault.mint_vault_shares(deposited_shares, total_deposit_shares);

        vault.divide_deposited_amount(
            deposited_amount, total_pending_amount, vault_shares
        );

        if (deposited_amount == total_pending_amount) {
            vault.pending_amount = ordered_map::new();
        };
    }

    fun divide_deposited_amount(
        self: &mut Vault,
        deposited_amount: u64,
        total_pending_amount: u64,
        vault_shares: u128
    ) acquires Strategy {
        let vault_addr = vault_address(self.name);

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

    // Return actual borrowed amounts
    // pass amount = U64_MAX to borrow all available borrow amounts
    public(friend) fun borrow(
        sender: &signer, name: String, borrow_amount: u64
    ): u64 acquires Strategy, Vault, RewardInfo {
        access_control::must_be_service_account(sender);
        let vault = get_vault_mut(&get_vault_object(name));
        assert!(!vault.paused);
        vault.compound_vault_rewards();
        let avail_borrow_amount =
            vault.borrowable_amount_given_health_factor(vault.health_factor);
        let amount = math64::min(borrow_amount, avail_borrow_amount);
        let actual_borrow_amount =
            if (amount > 0) {
                borrow_from_echelon_impl(
                    &vault.get_vault_signer(),
                    &vault.borrow_market,
                    &lending::market_asset_metadata(vault.borrow_market),
                    amount
                )
            } else { 0 };
        actual_borrow_amount
    }

    // Return actual repaid amounts
    // pass amount = U64_MAX to repay all
    public(friend) fun repay(
        sender: &signer, name: String, repay_amount: u64
    ): u64 acquires Strategy, Vault, RewardInfo {
        access_control::must_be_service_account(sender);
        let vault = get_vault_mut(&get_vault_object(name));
        let vault_signer = vault.get_vault_signer();
        assert!(!vault.paused);
        vault.compound_vault_rewards();
        let (actual_repay_amount, _) = vault.repay_echelon(&vault_signer, repay_amount);
        actual_repay_amount
    }

    // Compound rewards of colab protocol
    // Rewards has been swaped to asset first
    public(friend) fun compound_rewards(name: String, amount: u64) acquires Strategy, Vault, RewardInfo {
        let vault = get_vault_mut(&get_vault_object(name));
        vault.compound_vault_rewards();
        if (amount > 0) {
            vault.deposit_to_echelon(amount);
        };
    }

    public(friend) fun get_signer(name: String): signer acquires Strategy, Vault {
        let vault = get_vault_data(&get_vault_object(name));
        vault.get_vault_signer()
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

    /// Return actual amount and shares, total shares before deposit
    fun deposit_to_echelon(self: &mut Vault, amount: u64): (u64, u64, u64) acquires Strategy {
        let vault_signer = self.get_vault_signer();
        let (share_before, _) = self.get_deposited_amount();
        let actual_deposit_amount =
            deposit_to_echelon_impl(
                &vault_signer,
                &self.market,
                &self.asset,
                amount
            );
        let (share_after, _) = self.get_deposited_amount();
        assert!(share_after >= share_before);
        assert!(actual_deposit_amount <= amount);

        let shares = share_after - share_before;
        self.available_amount = self.available_amount - actual_deposit_amount;

        (actual_deposit_amount, shares, share_before)
    }

    /// Withdraw asset from Echelon back to vault
    /// Assumes vault has been compounded
    /// Return received amount, burned shares, total shares before withdraw, repaied_amount
    fun withdraw_from_echelon(
        self: &mut Vault, amount: u64
    ): (u64, u64, u64, u64) acquires Strategy, RewardInfo {
        let vault_signer = self.get_vault_signer();
        let loan_amount = self.get_loan_amount();
        let repaid_amount = 0;
        if (loan_amount > 0) {
            let repay_amount =
                self.estimate_repay_amount_from_withdraw_amount_inline(
                    signer::address_of(&vault_signer), amount
                );
            if (repay_amount > 0) {
                let (_repaid_amount, _) = self.repay_echelon(&vault_signer, repay_amount);
                repaid_amount = _repaid_amount;
            }
        };
        let (shares_before, _) = self.get_deposited_amount();
        let actual_withdraw_amount =
            withdraw_from_echelon_impl(
                &vault_signer,
                &self.market,
                &self.asset,
                amount
            );
        let (shares_after, _) = self.get_deposited_amount();
        assert!(shares_before >= shares_after);
        let shares = shares_before - shares_after;
        self.available_amount = self.available_amount + amount;

        (actual_withdraw_amount, shares, shares_before, repaid_amount)
    }

    // Return actual repaid amount, swapped amount
    fun repay_echelon(
        self: &mut Vault, vault_signer: &signer, repay_amount: u64
    ): (u64, u64) acquires Strategy, RewardInfo {
        assert!(self.is_compound_rewards());
        let pending_borrow_amount =
            if (self.market == self.borrow_market) {
                let balance =
                    primary_fungible_store::balance(
                        signer::address_of(vault_signer), self.asset
                    );
                let avail_borrow_amount = balance - self.get_total_pending_amount();
                avail_borrow_amount
            } else {
                primary_fungible_store::balance(
                    signer::address_of(vault_signer),
                    lending::market_asset_metadata(self.borrow_market)
                )
            };

        let req_amount =
            if (repay_amount > pending_borrow_amount) {
                repay_amount - pending_borrow_amount
            } else { 0 };

        let swapped_amount =
            if (req_amount > 0) {
                let amount_in =
                    get_amount_in(
                        &self.asset,
                        &lending::market_asset_metadata(self.borrow_market),
                        req_amount
                    );
                math64::ceil_div(amount_in * (10000 + 50), 10000)
            } else { 0 };
        let actual_withdraw_amount =
            withdraw_from_echelon_impl(
                vault_signer,
                &self.market,
                &self.asset,
                swapped_amount
            );
        assert!(actual_withdraw_amount >= swapped_amount);
        if (swapped_amount > 0) {
            let amount_out =
                swap_with_hyperion(
                    vault_signer,
                    &lending::market_asset_metadata(self.borrow_market),
                    &self.asset,
                    swapped_amount
                );
            assert!(amount_out >= req_amount);
        };
        let actual_repay_amount =
            repay_to_echelon_impl(
                vault_signer,
                &self.borrow_market,
                &lending::market_asset_metadata(self.borrow_market),
                repay_amount
            );
        assert!(actual_repay_amount <= repay_amount);
        let avail_amount =
            primary_fungible_store::balance(
                signer::address_of(vault_signer), self.asset
            ) - self.get_total_pending_amount();
        if (avail_amount > 0) {
            self.available_amount = self.available_amount + avail_amount;
        };
        self.compound_vault_rewards();
        (actual_repay_amount, swapped_amount)
    }

    // return actual deposited amount
    fun deposit_to_echelon_impl(
        caller: &signer,
        market: &Object<Market>,
        asset: &Object<Metadata>,
        amount: u64
    ): u64 {
        let caller_addr = signer::address_of(caller);
        let balance_before = primary_fungible_store::balance(caller_addr, *asset);
        scripts::supply_fa(caller, *market, amount);

        let balance_after = primary_fungible_store::balance(caller_addr, *asset);

        assert!(balance_before >= balance_after);
        balance_before - balance_after
    }

    // Return actual withdrawn amount
    fun withdraw_from_echelon_impl(
        caller: &signer,
        market: &Object<Market>,
        asset: &Object<Metadata>,
        amount: u64
    ): u64 {
        let caller_addr = signer::address_of(caller);
        let balance_before = primary_fungible_store::balance(caller_addr, *asset);
        let shares = lending::coins_to_shares(*market, amount);
        if (shares == 0) {
            return 0;
        };
        if (shares >= lending::account_shares(caller_addr, *market)) {
            scripts::withdraw_all_fa(caller, *market);
        } else {
            scripts::withdraw_fa(caller, *market, shares);
        };
        let balance_after = primary_fungible_store::balance(caller_addr, *asset);

        assert!(balance_after >= balance_before);
        balance_after - balance_before
    }

    // Return actual borrowed amount
    fun borrow_from_echelon_impl(
        caller: &signer,
        market: &Object<Market>,
        asset: &Object<Metadata>,
        amount: u64
    ): u64 {
        let caller_addr = signer::address_of(caller);
        let balance_before = primary_fungible_store::balance(caller_addr, *asset);
        scripts::borrow_fa(caller, *market, amount);
        let balance_after = primary_fungible_store::balance(caller_addr, *asset);

        assert!(balance_after >= balance_before);
        balance_after - balance_before
    }

    // Return actual repaid amount
    fun repay_to_echelon_impl(
        caller: &signer,
        market: &Object<Market>,
        asset: &Object<Metadata>,
        amount: u64
    ): u64 {
        let caller_addr = signer::address_of(caller);
        let balance_before = primary_fungible_store::balance(caller_addr, *asset);
        if (amount == 0) {
            return 0;
        };
        if (amount >= lending::account_liability(caller_addr, *market)) {
            scripts::repay_all_fa(caller, *market);
        } else {
            scripts::repay_fa(caller, *market, amount);
        };
        let balance_after = primary_fungible_store::balance(caller_addr, *asset);

        assert!(balance_before >= balance_after);
        balance_before - balance_after
    }

    fun get_vault_object(name: String): Object<Vault> acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global<Strategy>(strategy_addr);
        assert!(ordered_map::contains(&strategy.vaults, &name));

        let vault_object = ordered_map::borrow(&strategy.vaults, &name);
        *vault_object
    }

    fun get_account_signer(self: &Strategy): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    fun get_vault_signer(self: &Vault): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    inline fun get_vault_mut(vault: &Object<Vault>): &mut Vault acquires Vault {
        borrow_global_mut<Vault>(object::object_address(vault))
    }

    inline fun get_vault_data(vault: &Object<Vault>): &Vault acquires Vault {
        borrow_global<Vault>(object::object_address(vault))
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
        self: &AccountData, vault: &Object<Vault>
    ): (u64, u128) {
        let vault_addr = object::object_address(vault);
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

    fun get_avail_amount_without_pending_amount(self: &Vault): u64 {
        self.available_amount - self.get_total_pending_amount()
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

    fun get_total_pending_amount(self: &Vault): u64 {
        let amount = 0;
        self.pending_amount.for_each_ref(|_, v| {
            amount = amount + *v;
        });

        amount
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

    /// Returns shares and current asset amount
    fun get_deposited_amount(self: &Vault): (u64, u64) acquires Strategy {
        let vault_addr = vault_address(self.name);
        let shares = lending::account_shares(vault_addr, self.market);
        let asset_amount = lending::account_coins(vault_addr, self.market);
        (shares, asset_amount)
    }

    /// Returns current loan
    fun get_loan_amount(self: &Vault): u64 acquires Strategy {
        let vault_addr = vault_address(self.name);
        lending::account_liability(vault_addr, self.borrow_market)
    }

    fun estimate_repay_amount_from_withdraw_amount_inline(
        self: &Vault, vault_addr: address, withdraw_amount: u64
    ): u64 acquires Strategy {
        let loan_amount = self.get_loan_amount();
        if (loan_amount == 0 || withdraw_amount == 0) {
            return 0;
        };
        let (_, deposited_amount) = self.get_deposited_amount();
        if (withdraw_amount >= deposited_amount) {
            return loan_amount;
        };
        let max_borrow_after_withdraw =
            calc_borrow_amount(
                deposited_amount - withdraw_amount,
                lending::market_asset_mantissa(self.market),
                lending::asset_price(self.market),
                lending::account_market_collateral_factor_bps(vault_addr, self.market),
                lending::market_asset_mantissa(self.borrow_market),
                lending::asset_price(self.borrow_market),
                self.health_factor
            );
        if (max_borrow_after_withdraw >= loan_amount) { 0 }
        else {
            loan_amount - max_borrow_after_withdraw + 1
        }
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

    fun compound_vault_rewards(self: &mut Vault): u64 acquires Strategy, RewardInfo {
        let asset = self.asset;
        self.claim_rewards();
        let asset_amount: u64 = 0;
        let vault_signer = self.get_vault_signer();
        vector::for_each(
            self.rewards.keys(),
            |reward_addr| {
                let reward_amount = self.get_reward_mut(reward_addr);
                if (reward_addr == object::object_address(&asset)) {
                    asset_amount = asset_amount + *reward_amount;
                } else {
                    asset_amount =
                        asset_amount
                            + swap_with_hyperion(
                                &vault_signer,
                                &asset,
                                &object::address_to_object<Metadata>(reward_addr),
                                *reward_amount
                            )
                };
                *reward_amount = 0;
            }
        );
        if (asset_amount > 0) {
            self.deposit_to_echelon(asset_amount);
        };

        // deposit all avail amount to echelon
        let avail_amount = self.get_avail_amount_without_pending_amount();
        if (avail_amount > 0) {
            self.deposit_to_echelon(avail_amount);
        };

        asset_amount
    }

    fun is_compound_rewards(self: &Vault): bool acquires Strategy, RewardInfo {
        let (_, _, claimable_amounts) = self.claimable_rewards();
        let min_amount = 1_000_000;

        let all_below_threshold = {
            let i = 0;
            let len = vector::length(&claimable_amounts);
            let ok = true;
            while (i < len) {
                let claimable_amount = *vector::borrow(&claimable_amounts, i);
                if (claimable_amount >= min_amount) {
                    ok = false;
                    break;
                };
                i = i + 1;
            };
            ok
        };

        let all_rewards_zero = {
            let ok = true;
            self.rewards.for_each_ref(|_, reward_amount| {
                if (*reward_amount > 0) {
                    ok = false;
                };
            });
            ok
        };

        let all_avail_amount_zero = {
            let ok = true;
            if (self.get_avail_amount_without_pending_amount() > 0) {
                ok = false;
            };
            ok
        };

        (all_below_threshold
            && all_rewards_zero
            && all_avail_amount_zero)
    }

    fun claim_rewards(self: &mut Vault) acquires Strategy, RewardInfo {
        let min_amount = 1_000_000;
        //get claimable rewards
        let (reward_tokens, farming_ids, claimable_amounts) = self.claimable_rewards();
        let vault_signer = self.get_vault_signer();
        while (reward_tokens.length() > 0) {
            let reward_token = vector::pop_back(&mut reward_tokens);
            let farming_id = vector::pop_back(&mut farming_ids);
            let claimable_amount = vector::pop_back(&mut claimable_amounts);
            if (claimable_amount >= min_amount) {
                let token_addr = object::object_address(&reward_token);
                let balance_before =
                    primary_fungible_store::balance(
                        signer::address_of(&vault_signer), reward_token
                    );
                scripts::claim_reward_fa(&vault_signer, reward_token, farming_id);
                let balance_after =
                    primary_fungible_store::balance(
                        signer::address_of(&vault_signer), reward_token
                    );
                let claimed_amount =
                    if (balance_after > balance_before) {
                        balance_after - balance_before
                    } else { 0 };
                if (claimed_amount > 0) {
                    let reward_amount = self.get_reward_mut(token_addr);
                    *reward_amount = *reward_amount + claimed_amount;
                }
            };
        }
    }

    fun claimable_rewards(
        self: &Vault
    ): (vector<Object<Metadata>>, vector<String>, vector<u64>) acquires Strategy, RewardInfo {
        let vault_addr = vault_address(self.name);
        let reward_info = borrow_global<RewardInfo>(vault_addr);
        let reward_tokens = vector::empty<Object<Metadata>>();
        let farming_identifiers = vector::empty<String>();
        let claimable_amounts = vector::empty<u64>();
        self.rewards.for_each_ref(
            |reward_addr, _| {
                let reward_metadata = object::address_to_object<Metadata>(*reward_addr);
                let token_name = fungible_asset::name(reward_metadata);
                //supply reward
                let supply_farming_id =
                    farming::farming_identifier(
                        object::object_address(&self.market), reward_info.supply_reward_id
                    );
                let claimable_amount =
                    farming::claimable_reward_amount(
                        vault_addr, token_name, supply_farming_id
                    );
                if (claimable_amount > 0) {
                    vector::push_back(&mut reward_tokens, reward_metadata);
                    vector::push_back(&mut farming_identifiers, supply_farming_id);
                    vector::push_back(&mut claimable_amounts, claimable_amount);
                };
                //borrow reward
                if (self.get_loan_amount() > 0) {
                    let borrow_farming_id =
                        farming::farming_identifier(
                            object::object_address(&self.borrow_market),
                            reward_info.borrow_reward_id
                        );
                    let claimable_amount =
                        farming::claimable_reward_amount(
                            vault_addr, token_name, borrow_farming_id
                        );
                    if (claimable_amount > 0) {
                        vector::push_back(&mut reward_tokens, reward_metadata);
                        vector::push_back(&mut farming_identifiers, borrow_farming_id);
                        vector::push_back(&mut claimable_amounts, claimable_amount);
                    }
                };
            }
        );
        (reward_tokens, farming_identifiers, claimable_amounts)
    }

    fun get_amount_out_claimable_reward_to_asset(self: &Vault): u64 acquires Strategy, RewardInfo {
        let asset = self.asset;
        let total_amount = 0;
        let (reward_tokens, _, claimable_amounts) = self.claimable_rewards();
        while (reward_tokens.length() > 0) {
            let reward_token = vector::pop_back(&mut reward_tokens);
            let claimable_amount = vector::pop_back(&mut claimable_amounts);
            if (claimable_amount > 0) {
                if (object::object_address(&reward_token)
                    == object::object_address(&asset)) {
                    total_amount = total_amount + claimable_amount;
                } else {
                    total_amount =
                        total_amount
                            + hyperion::router_v3::get_batch_amount_out(
                                get_path(&asset, &reward_token),
                                claimable_amount,
                                *option::borrow(&coin::paired_metadata<ThalaAPT>()),
                                asset
                            );
                };
            };
        };
        total_amount
    }

    /// Swap ThalaAPT reward to USDT/USDC using Hyperion
    /// Returns the amount of USDT/USDC received
    fun swap_with_hyperion(
        caller: &signer,
        to: &Object<Metadata>,
        from: &Object<Metadata>,
        amount: u64
    ): u64 {
        if (object::object_address(to) == object::object_address(from)) {
            return amount;
        };
        let caller_addr = signer::address_of(caller);
        let thala_apt_metadata = coin::paired_metadata<ThalaAPT>();
        let reward_path = get_path(to, from);
        let balance_before = primary_fungible_store::balance(caller_addr, *to);
        let amount_out =
            hyperion::router_v3::get_batch_amount_out(reward_path, amount, *from, *to);
        let amount_out_min = math64::mul_div(amount_out, 98, 100); //slippage 2%
        if (*from == *option::borrow(&thala_apt_metadata)) {
            hyperion::router_v3::swap_batch_coin_entry<ThalaAPT>(
                caller,
                reward_path,
                *from,
                *to,
                amount,
                amount_out_min,
                caller_addr
            );
        } else {
            hyperion::router_v3::swap_batch(
                caller,
                reward_path,
                *from,
                *to,
                amount,
                amount_out_min,
                caller_addr
            );
        };

        let balance_after = primary_fungible_store::balance(caller_addr, *to);

        balance_after - balance_before
    }

    fun get_amount_out(
        to: &Object<Metadata>, from: &Object<Metadata>, amount: u64
    ): u64 {
        if (object::object_address(to) == object::object_address(from)) {
            return amount;
        };
        if (amount == 0) {
            return 0;
        };
        let path = get_path(to, from);
        hyperion::router_v3::get_batch_amount_out(path, amount, *from, *to)
    }

    fun get_amount_in(
        to: &Object<Metadata>, from: &Object<Metadata>, amount: u64
    ): u64 {
        if (object::object_address(to) == object::object_address(from)) {
            return amount;
        };
        if (amount == 0) {
            return 0;
        };
        let path = get_path(to, from);
        hyperion::router_v3::get_batch_amount_in(path, amount, *from, *to)
    }

    fun get_path(to: &Object<Metadata>, from: &Object<Metadata>): vector<address> {
        if (object::object_address(to) == object::object_address(from)) {
            return vector::empty<address>()
        };
        if (object::object_address(to) == @usdc) {
            let lp_path: vector<address> = vector[
                @0x692ba87730279862aa1a93b5fef9a175ea0cccc1f29dfc84d3ec7fbe1561aef3,
                @0x925660b8618394809f89f8002e2926600c775221f43bf1919782b297a79400d8
            ];
            lp_path
        } else if (object::object_address(to) == @usdt) {
            let lp_path: vector<address> = vector[
                @0x692ba87730279862aa1a93b5fef9a175ea0cccc1f29dfc84d3ec7fbe1561aef3,
                @0x925660b8618394809f89f8002e2926600c775221f43bf1919782b297a79400d8,
                @0xd3894aca06d5f42b27c89e6f448114b3ed6a1ba07f992a58b2126c71dd83c127
            ];
            lp_path
        } else if (object::object_address(from) == @usdc
            || object::object_address(from) == @usdt) {
            let lp_path: vector<address> = vector[
                @0xd3894aca06d5f42b27c89e6f448114b3ed6a1ba07f992a58b2126c71dd83c127
            ];
            lp_path
        } else {
            vector::empty<address>()
        }
    }

    fun borrowable_amount_given_health_factor(
        self: &Vault, health_factor: u64
    ): u64 acquires Strategy {
        assert!(health_factor > HEALTH_FACTOR_DENOMINATOR, error::invalid_argument(4));
        let vault_addr = vault_address(self.name);
        let total_deposit = lending::account_coins(vault_addr, self.market);
        let total_borrow = lending::account_liability(vault_addr, self.borrow_market);
        if (total_deposit == 0) {
            return 0;
        };
        let max_borrow =
            calc_borrow_amount(
                total_deposit,
                lending::market_asset_mantissa(self.market),
                lending::asset_price(self.market),
                lending::account_market_collateral_factor_bps(vault_addr, self.market),
                lending::market_asset_mantissa(self.borrow_market),
                lending::asset_price(self.borrow_market),
                health_factor
            );
        if (max_borrow <= total_borrow) {
            return 0;
        };
        max_borrow - total_borrow
    }

    fun calc_borrow_amount(
        supply_amount: u64,
        supply_asset_mantissa: u64,
        supply_asset_price: FixedPoint64,
        account_market_collateral_factor_bps: u64,
        borrow_asset_mantissa: u64,
        borrow_asset_price: FixedPoint64,
        health_factor: u64
    ): u64 {
        let v0 = supply_asset_mantissa * health_factor;
        assert!(v0 != 0, error::invalid_argument(4));
        fixed_point64::decode_round_down(
            fixed_point64::div_fp(
                fixed_point64::mul(
                    supply_asset_price,
                    (
                        ((supply_amount as u128)
                            * ((
                                borrow_asset_mantissa
                                    * account_market_collateral_factor_bps
                            ) as u128) / (v0 as u128)) as u64
                    )
                ),
                borrow_asset_price
            )
        )
    }
}

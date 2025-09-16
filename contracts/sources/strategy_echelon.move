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
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::coin;

    use lending::farming;
    use lending::scripts;
    use lending::lending::{Self, Market};
    use thala_lsd::staking::ThalaAPT;
    use fixed_point64::fixed_point64;

    use moneyfi::access_control;
    use moneyfi::storage;
    use moneyfi::vault as moneyfi_vault;
    use moneyfi::wallet_account::{Self, WalletAccount};

    const STRATEGY_ACCOUNT_SEED: vector<u8> = b"strategy_echelon::STRATEGY_ACCOUNT";

    const U64_MAX: u64 = 18446744073709551615;
    const HEALTH_FACTOR_DENOMINATOR: u64 = 10000;
    const SHARE_DECIMALS: u64 = 8;

    const E_VAULT_EXISTS: u64 = 1;
    const E_EXCEED_CAPACITY: u64 = 2;
    const E_UNSUPPORTED_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;

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
        move_to(
            &object::generate_signer_for_extending(&extend_ref),
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
            &object::generate_signer_for_extending(&extend_ref),
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
    ) acquires Strategy {
        access_control::must_be_service_account(sender);
        let object_vault = get_vault(name);
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

    /// deposit fund from wallet account to strategy vault
    public(friend) fun deposit(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64
    ) acquires Strategy {
        //TODO
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
    ) acquires Strategy {
        //TODO
    }

    /// Deposits fund from vault to Echelon
    /// Pass amount = U64_MAX to deposit all pending amount
    public(friend) fun vault_deposit_echelon() {} //TODO

    public(friend) fun borrow_echelon(): u64 {
        0
    } //TODO

    public(friend) fun repay_echelon(): u64 {
        0
    } //TODO

    public(friend) fun compound_rewards() {} //TODO

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

    fun get_strategy_address(): address {
        storage::get_child_object_address(STRATEGY_ACCOUNT_SEED)
    }

    fun get_vault_address(name: String): address acquires Strategy {
        object::object_address(&get_vault(name))
    }

    fun get_vault(name: String): Object<Vault> acquires Strategy {
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

    fun get_vault_mut(vault: &Object<Vault>): &mut Vault {
        borrow_global_mut<Vault>(object::object_address(vault))
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
        self: &mut AccountData, vault: &Object<Vault>
    ): &mut VaultAsset {
        let vault_addr = object::object_address(vault);
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
        let vault_addr = get_vault_address(self.name);
        let shares = lending::account_shares(vault_addr, self.market);
        let asset_amount = lending::account_coins(vault_addr, self.market);
        (shares, asset_amount)
    }

    /// Returns current loan
    fun get_loan_amount(self: &Vault): u64 acquires Strategy {
        let vault_addr = get_vault_address(self.name);
        lending::account_liability(vault_addr, self.borrow_market)
    }

    fun get_vault_shares_from_deposit_shares(
        self: &Vault, deposit_shares: u64, total_deposit_shares: u64
    ): u128 {
        if (total_deposit_shares == 0) {
            (deposit_shares as u128) * math128::pow(10, SHARE_DECIMALS as u128)
        } else {
            (deposit_shares as u128) * self.total_shares
                / (total_deposit_shares as u128)
        }
    }

    fun compound_vault_rewards(
        self: &mut Vault, strategy_signer: &signer, extra_data: vector<vector<u8>>
    ): u64 {
        let asset = self.asset;
        self.claim_rewards(strategy_signer, extra_data);
        let asset_amount: u64 = 0;
        vector::for_each(
            self.rewards.keys(),
            |reward_addr| {
                let reward_amount = self.get_reward_mut(reward_addr);
                if (reward_addr == object::object_address(&asset)) {
                    asset_amount = asset_amount + *reward_amount;
                } else {
                    asset_amount =
                        asset_amount
                            + swap_reward_with_hyperion(
                                strategy_signer,
                                &asset,
                                reward_addr,
                                *reward_amount
                            )
                };
                *reward_amount = 0;
            }
        );
        if (asset_amount > 0) {
            self.deposit_to_aries(strategy_signer, asset_amount);
        };

        asset_amount
    }

    /// Swap APT reward to USDT/USDC using Hyperion
    /// Returns the amount of USDT/USDC received
    fun swap_reward_with_hyperion(
        caller: &signer,
        to: &Object<Metadata>,
        from: address,
        amount: u64
    ): u64 {
        let strategy_addr = get_strategy_address();

        let fee_tier = 1; // 0.05%
        let apt = object::address_to_object<Metadata>(APT_FA_ADDRESS);
        // let (exist, pool_addr) =
        //     hyperion::pool_v3::liquidity_pool_address_safe(apt, *to, fee_tier);
        // assert!(exist, error::permission_denied(E_POOL_NOT_EXIST));
        // let pool =
        //     object::address_to_object<hyperion::pool_v3::LiquidityPoolV3>(pool_addr);

        let pool = hyperion::pool_v3::liquidity_pool(apt, *to, fee_tier);
        let (amount_out, _) = hyperion::pool_v3::get_amount_out(pool, apt, amount);
        amount_out = amount_out - (amount_out * 1 / 1000); // 0.1% slippage

        // ignore price impact
        let sqrt_price_limit =
            if (hyperion::utils::is_sorted(apt, *to)) {
                79226673515401279992447579055 // max sqrt price
            } else {
                04295048016 // min sqrt price
            };

        let balance_before = primary_fungible_store::balance(strategy_addr, *to);
        hyperion::router_v3::exact_input_swap_entry(
            caller,
            fee_tier,
            amount,
            amount_out,
            sqrt_price_limit,
            apt,
            *to,
            strategy_addr,
            timestamp::now_seconds() + 60
        );
        let balance_after = primary_fungible_store::balance(strategy_addr, *to);

        balance_after - balance_before
    }

    fun borrowable_amount_given_health_factor(
        vault: Object<Vault>, health_factor: u64
    ): u64 {
        let vault_addr = object::object_address(&vault);
        let total_deposit = 0; //todo
        //Todo
        0
    }
}

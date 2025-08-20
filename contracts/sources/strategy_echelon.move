module moneyfi::strategy_echelon {
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;
    use std::option;
    use std::string::String;
    use std::bcs::to_bytes;
    use aptos_std::from_bcs;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::error;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::code;

    use lending::farming;
    use lending::scripts;
    use lending::lending::{Self, Market};
    use thala_lsd::staking::ThalaAPT;

    use moneyfi::access_control;
    use moneyfi::storage;
    use moneyfi::wallet_account::{Self, WalletAccount};

    friend moneyfi::strategy;

    const STRATEGY_ACCOUNT_SEED: vector<u8> = b"strategy_echelon::STRATEGY_ACCOUNT";

    const U64_MAX: u64 = 18446744073709551615;

    const E_VAULT_EXISTS: u64 = 1;
    const E_EXCEED_CAPACITY: u64 = 2;
    const E_UNSUPPORTED_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;

    struct Strategy has key {
        extend_ref: ExtendRef,
        vaults: OrderedMap<address, Vault> // market address -> vault
    }

    struct Vault has store, copy {
        market: Object<Market>,
        asset: Object<Metadata>,
        deposit_cap: u64,
        // total shares of the vault
        total_shares: u64,
        // total amount distributed to the vault
        total_amount_distributed: u128,
        // unused amount
        available_amount: u64,
        // accumulated deposited amount
        total_deposited_amount: u128,
        // accumulated withdrawn amount
        total_withdrawn_amount: u128,
        reward_amount: u64,
        rewards: OrderedMap<address, u64>,
        loans: vector<Loan>,
        paused: bool
    }

    struct Loan has store, copy {
        market: Object<Market>,
        amount: u64
    }

    // Track asset of an account in vault
    struct VaultAsset has copy, store, drop {
        shares: u64,
        deposited_amount: u64
    }

    // struct ExtraData {
    //     market: address,
    //     reward_lend_id: u64,
    //     reward_borrow_id: u64,
    // }

    // -- Events
    #[event]
    struct VaultCreatedEvent has drop, store {
        market: Object<Market>,
        asset: Object<Metadata>,
        timestamp: u64
    }

    fun init_module(_sender: &signer) {
        init_strategy_account();
    }

    // -- Entries

    public entry fun create_vault(
        sender: &signer, market: Object<Market>, asset: Object<Metadata>, reward: vector<address>
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let market_addr = object::object_address((&market));
        assert!(
            ordered_map::contains((&strategy.vaults), &market_addr),
            error::already_exists(E_VAULT_EXISTS)
        );

        let strategy_signer = strategy.get_account_signer();
        
        let rewards = if (vector::is_empty(&reward)) {
            ordered_map::new()
        } else {
            let map = ordered_map::new();
            vector::for_each(reward, |addr| {
                ordered_map::add(&mut map, addr, 0);
            });
            map
        };
        ordered_map::add(
            &mut strategy.vaults,
            market_addr,
            Vault {
                market,
                asset,
                deposit_cap: U64_MAX,
                total_shares: 0,
                total_amount_distributed: 0,
                available_amount: 0,
                total_deposited_amount: 0,
                total_withdrawn_amount: 0,
                reward_amount: 0,
                rewards,
                loans: vector[],
                paused: false
            }
        );

        event::emit(
            VaultCreatedEvent { market: market, asset: asset, timestamp: timestamp::now_seconds() }
        );
    }

    public entry fun config_vault(
        sender: &signer,
        market: Object<Market>,
        emode: Option<u8>,
        rewards: vector<address>,// add new rewards
        deposit_cap: u64,
        paused: bool
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();
        let vault = strategy.get_vault_mut_by_market(object::object_address(&market));

        vault.deposit_cap = deposit_cap;
        vault.paused = paused;

        if (option::is_some(&emode)) {
            let emode = option::borrow(&emode);
            if (emode.is_empty()) {
                lending::user_quit_efficiency_mode(&strategy_signer);
            } else {
                lending::user_enter_efficiency_mode(&strategy_signer, *emode);
            }
        };
        if(!rewards.is_empty()){
            vector::for_each(rewards, |reward| {
                ordered_map::add(&mut vault.rewards, reward, 0);
            })
        };
    }

    public entry fun compound_rewards(sender: &signer, extra_data: vector<vector<u8>>) acquires Strategy {
        access_control::must_be_service_account(sender);
        let market = from_bcs::to_address(*extra_data.borrow(0));
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();
        let vault = strategy.get_vault_mut_by_market(market);

        vault.compound_vault_rewards(&strategy_signer, extra_data);
    }

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

    fun get_strategy_address(): address {
        storage::get_child_object_address(STRATEGY_ACCOUNT_SEED)
    }

    fun get_account_signer(self: &Strategy): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    fun get_vault_mut_by_market(self: &mut Strategy, addr: address): &mut Vault {
        assert!(ordered_map::contains(&self.vaults, &addr));

        ordered_map::borrow_mut(&mut self.vaults, &addr)
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
            account_data.add(vault_addr, VaultAsset { deposited_amount: 0, shares: 0 })
        };

        account_data
    }

    fun compound_vault_rewards(
        self: &mut Vault, strategy_signer: &signer, extra_data: vector<vector<u8>>
    ): u64 {
        let asset = self.asset;
        self.claim_rewards(strategy_signer, extra_data);
        let asset_amount: u64 = 0;
        vector::for_each(self.rewards.keys(), |reward_addr| {
            let reward_amount = self.get_reward_mut(reward_addr);
            if (reward_addr == object::object_address(&asset)){
                asset_amount = asset_amount + *reward_amount;
            }else{
                asset_amount = asset_amount + swap_reward_with_hyperion(strategy_signer, &asset, reward_addr, *reward_amount)
            };
            *reward_amount = 0;
        });
        if (asset_amount > 0) {
            self.deposit_to_aries(strategy_signer, asset_amount);
        };

        asset_amount
    }

    /// Swap APT reward to USDT/USDC using Hyperion
    /// Returns the amount of USDT/USDC received
    fun swap_reward_with_hyperion(
        caller: &signer, to: &Object<Metadata>, from: address, amount: u64
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

    fun claim_rewards(self: &mut Vault, strategy_signer: &signer, extra_data: vector<vector<u8>>) {
        let strategy_addr = get_strategy_address();

        // TODO: handle other rewards
        let reward_addrs = ordered_map::keys(&self.rewards);
        vector::for_each(reward_addrs, |reward_addr| {
            let reward_metadata = object::address_to_object<Metadata>(reward_addr);
            let balance_before = primary_fungible_store::balance(strategy_addr, reward_metadata);
            if(reward_metadata != option::destroy_some<Metadata>(coin::paired_metadata<ThalaAPT>())) {
                scripts::claim_reward_fa(
                    strategy_signer, reward_metadata, farming::farming_identifier(object::object_address(&self.market), from_bcs::to_u64(*extra_data.borrow(1)))
                );
                if(!self.loans.is_empty()){
                    scripts::claim_reward_fa(
                    strategy_signer, reward_metadata, farming::farming_identifier(object::object_address(&self.market), from_bcs::to_u64(*extra_data.borrow(2)))
                );
                }
            }else{
                scripts::claim_reward<ThalaAPT>(
                    strategy_signer, farming::farming_identifier(object::object_address(&self.market), from_bcs::to_u64(*extra_data.borrow(1)))
                );
                if(!self.loans.is_empty()){
                    scripts::claim_reward<ThalaAPT>(
                    strategy_signer, farming::farming_identifier(object::object_address(&self.market), from_bcs::to_u64(*extra_data.borrow(2)))
                );
                }
            };
            let balance_after = primary_fungible_store::balance(strategy_addr, reward_metadata);
            let amount = if(balance_after > balance_before){
                balance_after - balance_before
            }else {0};

            if (amount > 0) {
                let reward_amount = self.get_reward_mut(reward_addr);
                *reward_amount = *reward_amount + amount;
            }
        });
    }

    fun get_reward_mut(self: &mut Vault, reward: address): &mut u64 {
        if (!self.rewards.contains(&reward)) {
            self.rewards.add(reward, 0);
        };

        self.rewards.borrow_mut(&reward)
    }
}

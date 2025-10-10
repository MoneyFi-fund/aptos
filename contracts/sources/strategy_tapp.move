module moneyfi::strategy_tapp {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::bcs::to_bytes;
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_std::from_bcs;
    use aptos_std::math128;
    use aptos_std::math64;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::error;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::Metadata;

    use tapp::router;
    use tapp::integration;
    use tapp::hook_factory;
    use tapp::position;
    use stable::stable;
    use views::stable_views;

    use moneyfi::wallet_account::{Self, WalletAccount};
    use dex_contract::router_v3;

    friend moneyfi::strategy;

    // ========== CONSTANTS ==========
    const USDC_ADDRESS: address = @stablecoin;
    const ZERO_ADDRESS: address = @0x0;
    const STRATEGY_ID: u8 = 4;
    const MINIMUM_LIQUIDITY: u128 = 1_000_000_000;
    const APT_FA_ADDRESS: address = @0xa;

    // ========== ERRORS ==========
    const E_TAPP_STRATEGY_DATA_NOT_EXISTS: u64 = 1;
    const E_TAPP_POSITION_NOT_EXISTS: u64 = 2;
    const E_INVALID_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;

    // ========== STRUCTS ==========
    struct StrategyStats has key {
        assets: OrderedMap<Object<Metadata>, AssetStats>
    }

    struct AssetStats has drop, store {
        total_value_locked: u128,
        total_deposited: u128,
        total_withdrawn: u128
    }

    // FOR WALLET ACCOUNTS
    struct TappStrategyData has copy, drop, store {
        strategy_id: u8,
        pools: OrderedMap<address, Position>
    }

    // FOR VAULTS
    struct TappData has key {
        pools: OrderedMap<address, Position>
    }

    public struct Position has copy, drop, store {
        position: address,
        lp_amount: u128,
        asset: Object<Metadata>,
        pair: Object<Metadata>,
        amount: u64
    }

    struct ExtraData has drop, copy, store {
        pool: address,
        withdraw_fee: u64
    }

    public struct PoolAmountPair has copy, drop, store {
        pool_address: address,
        amount: u64
    }

    // ========== INITIALIZATION ==========
    fun init_module(sender: &signer) {
        move_to(
            sender,
            StrategyStats {
                assets: ordered_map::new<Object<Metadata>, AssetStats>()
            }
        );
    }

    // ========================================================================
    // WALLET ACCOUNT FUNCTIONS (UNCHANGED - For backward compatibility)
    // ========================================================================

    public(friend) fun deposit_fund_to_tapp_single(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount_in: u64,
        extra_data: vector<vector<u8>>
    ): (u64, TypeInfo) acquires StrategyStats {
        let extra_data = unpack_extra_data(extra_data);
        let position = create_or_get_exist_position(account, asset, extra_data);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);

        let amount_pair_in = math128::mul_div(amount_in as u128, 1, 1000) as u64;
        let balance_asset_before_swap =
            primary_fungible_store::balance(wallet_address, position.asset);
        let balance_pair_before_swap =
            primary_fungible_store::balance(wallet_address, position.pair);

        router_v3::exact_input_swap_entry(
            &wallet_signer,
            0,
            amount_pair_in,
            0,
            79226673515401279992447579055 - 1,
            position.asset,
            position.pair,
            signer::address_of(&wallet_signer),
            timestamp::now_seconds() + 600
        );

        let actual_amount_asset_swap =
            balance_asset_before_swap
                - primary_fungible_store::balance(wallet_address, position.asset);
        let actual_amount_pair =
            primary_fungible_store::balance(wallet_address, position.pair)
                - balance_pair_before_swap;

        let assets =
            hook_factory::pool_meta_assets(&hook_factory::pool_meta(extra_data.pool));
        let token_a = *vector::borrow(&assets, 0);
        let token_b = *vector::borrow(&assets, 1);

        let amounts = vector::empty<u256>();
        if (object::object_address(asset) == token_a) {
            vector::push_back(
                &mut amounts, (amount_in - actual_amount_asset_swap) as u256
            );
            vector::push_back(&mut amounts, actual_amount_pair as u256);
        } else if (object::object_address(asset) == token_b) {
            vector::push_back(&mut amounts, actual_amount_pair as u256);
            vector::push_back(
                &mut amounts, (amount_in - actual_amount_asset_swap) as u256
            );
        } else {
            assert!(false, error::invalid_argument(E_INVALID_ASSET));
        };

        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&extra_data.pool));
        if (position.position == ZERO_ADDRESS) {
            vector::append(
                &mut payload,
                to_bytes<Option<address>>(&option::none<address>())
            );
        } else {
            vector::append(
                &mut payload,
                to_bytes<Option<address>>(&option::some(position.position))
            );
        };
        vector::append(
            &mut payload,
            to_bytes<vector<u256>>(&amounts)
        );
        let minMintAmount: u256 = 0;
        vector::append(&mut payload, to_bytes<u256>(&minMintAmount));

        let (position_idx, position_addr) =
            integration::add_liquidity(&wallet_signer, payload);

        let actual_amount =
            balance_asset_before_swap
                - primary_fungible_store::balance(wallet_address, position.asset);

        position.position = position_addr;
        position.lp_amount =
            stable_views::position_shares(extra_data.pool, position_idx) as u128;
        position.amount = position.amount + actual_amount;
        strategy_stats_deposit(asset, actual_amount);
        let strategy_data = set_position_data(account, extra_data.pool, position);
        wallet_account::set_strategy_data(account, strategy_data);
        (actual_amount, get_strategy_type())
    }

    public(friend) fun withdraw_fund_from_tapp_single(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount_min: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64, u64, TypeInfo, vector<u8>) acquires StrategyStats {
        let hook_data = get_hook_data(&extra_data);
        let extra_data = unpack_extra_data(extra_data);
        let position = get_position_data(account, extra_data.pool);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);

        let (liquidity_remove, is_full_withdraw) =
            if (amount_min < position.amount) {
                let liquidity =
                    math128::ceil_div(
                        position.lp_amount * (amount_min as u128),
                        (position.amount as u128)
                    );
                (liquidity as u256, false)
            } else {
                (position.lp_amount as u256, true)
            };

        let pair =
            if (object::object_address(asset)
                == object::object_address(&position.asset)) {
                position.pair
            } else if (object::object_address(asset)
                == object::object_address(&position.pair)) {
                position.asset
            } else {
                assert!(false, error::invalid_argument(E_INVALID_ASSET));
                position.asset
            };

        let balance_asset_before = primary_fungible_store::balance(
            wallet_address, *asset
        );
        let balance_pair_before = primary_fungible_store::balance(wallet_address, pair);
        let (active_rewards, _) = get_active_rewards(extra_data.pool, &position);

        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&extra_data.pool));
        vector::append(&mut payload, to_bytes<address>(&position.position));
        let remove_type: u8 = 3;
        vector::append(&mut payload, to_bytes<u8>(&remove_type));
        vector::append(&mut payload, to_bytes<u256>(&liquidity_remove));
        let remove_amounts =
            stable_views::calc_ratio_amounts(extra_data.pool, liquidity_remove);
        let min_amounts = vector::map(
            remove_amounts,
            |amount| { math128::mul_div(amount as u128, 98, 100) as u256 }
        );
        vector::append(
            &mut payload,
            to_bytes<vector<u256>>(&min_amounts)
        );

        router::remove_liquidity(&wallet_signer, payload);

        let pair_amount =
            primary_fungible_store::balance(wallet_address, pair) - balance_pair_before;
        if (pair_amount > 0) {
            router_v3::exact_input_swap_entry(
                &wallet_signer,
                0,
                pair_amount,
                0,
                4295048016 + 1,
                pair,
                *asset,
                signer::address_of(&wallet_signer),
                timestamp::now_seconds() + 600
            );
        };

        vector::for_each(
            active_rewards,
            |reward_token_addr| {
                if (reward_token_addr != object::object_address(asset)) {
                    let reward_balance =
                        primary_fungible_store::balance(
                            wallet_address,
                            object::address_to_object<Metadata>(reward_token_addr)
                        );

                    if (reward_balance > 0) {
                        router_v3::exact_input_swap_entry(
                            &wallet_signer,
                            1,
                            reward_balance,
                            0,
                            4295048016 + 1,
                            object::address_to_object<Metadata>(reward_token_addr),
                            *asset,
                            signer::address_of(&wallet_signer),
                            timestamp::now_seconds() + 600
                        );
                    };
                };
            }
        );

        let balance_asset_after = primary_fungible_store::balance(
            wallet_address, *asset
        );
        let total_withdrawn_amount = balance_asset_after - balance_asset_before;
        let (total_deposited_amount, strategy_data) =
            if (is_full_withdraw) {
                (position.amount, remove_position(account, extra_data.pool))
            } else {
                position.amount = position.amount - amount_min;
                position.lp_amount = position.lp_amount - (liquidity_remove as u128);
                (amount_min, set_position_data(account, extra_data.pool, position))
            };
        wallet_account::set_strategy_data(account, strategy_data);
        strategy_stats_withdraw(asset, total_deposited_amount, total_withdrawn_amount);
        (
            total_deposited_amount,
            total_withdrawn_amount,
            extra_data.withdraw_fee,
            get_strategy_type(),
            hook_data
        )
    }

    // ========================================================================
    // VAULT FUNCTIONS - for vaults to interact with TAPP
    // ========================================================================

    /// Check if vault has TAPP data
    public fun vault_has_tapp_data(vault_addr: address): bool {
        exists<TappData>(vault_addr)
    }

    /// Get vault TAPP data
    public fun get_vault_tapp_data(
        vault_addr: address
    ): OrderedMap<address, Position> acquires TappData {
        if (!exists<TappData>(vault_addr)) {
            return ordered_map::new<address, Position>()
        };
        let tapp_data = borrow_global<TappData>(vault_addr);
        tapp_data.pools
    }

    /// Deposit to TAPP for vault
    public fun deposit_to_tapp_impl(
        caller: &signer,
        asset: &Object<Metadata>,
        pool: address,
        amount_in: u64
    ): u64 acquires TappData {
        let position = vault_create_or_get_exist_position(caller, asset, pool);
        let caller_address = signer::address_of(caller);

        let amount_pair_in =
            math64::max(
                100000,
                math128::mul_div(amount_in as u128, 1, 1000) as u64
            );

        let balance_asset_before_swap =
            primary_fungible_store::balance(caller_address, position.asset);
        let balance_pair_before_swap =
            primary_fungible_store::balance(caller_address, position.pair);

        swap_with_hyperion(
            caller,
            &position.asset,
            &position.pair,
            amount_pair_in,
            false
        );

        let actual_amount_asset_swap =
            balance_asset_before_swap
                - primary_fungible_store::balance(caller_address, position.asset);
        let actual_amount_pair =
            primary_fungible_store::balance(caller_address, position.pair)
                - balance_pair_before_swap;

        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let token_a = *vector::borrow(&assets, 0);
        let token_b = *vector::borrow(&assets, 1);

        let amounts = vector::empty<u256>();
        if (object::object_address(asset) == token_a) {
            vector::push_back(
                &mut amounts, (amount_in - actual_amount_asset_swap) as u256
            );
            vector::push_back(&mut amounts, actual_amount_pair as u256);
        } else if (object::object_address(asset) == token_b) {
            vector::push_back(&mut amounts, actual_amount_pair as u256);
            vector::push_back(
                &mut amounts, (amount_in - actual_amount_asset_swap) as u256
            );
        } else {
            assert!(false, error::invalid_argument(E_INVALID_ASSET));
        };

        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&pool));
        if (position.position == ZERO_ADDRESS) {
            vector::append(
                &mut payload,
                to_bytes<Option<address>>(&option::none<address>())
            );
        } else {
            vector::append(
                &mut payload,
                to_bytes<Option<address>>(&option::some(position.position))
            );
        };
        vector::append(
            &mut payload,
            to_bytes<vector<u256>>(&amounts)
        );
        let minMintAmount: u256 = 0;
        vector::append(&mut payload, to_bytes<u256>(&minMintAmount));

        let (position_idx, position_addr) = integration::add_liquidity(caller, payload);

        let actual_amount =
            balance_asset_before_swap
                - primary_fungible_store::balance(caller_address, position.asset);

        position.position = position_addr;
        position.lp_amount = stable_views::position_shares(pool, position_idx) as u128;
        position.amount = position.amount + actual_amount;
        vault_set_position_data(caller, pool, position);
        actual_amount
    }

    /// Withdraw from TAPP for vault
    public fun withdraw_from_tapp_impl(
        caller: &signer,
        asset: &Object<Metadata>,
        pool: address,
        amount_min: u64
    ): (u64, u64) acquires TappData {
        let position = vault_get_position_data(caller, pool);
        let caller_address = signer::address_of(caller);

        let (liquidity_remove, is_full_withdraw) =
            if (amount_min < position.amount) {
                let liquidity =
                    math128::ceil_div(
                        position.lp_amount * (amount_min as u128),
                        (position.amount as u128)
                    );
                (liquidity as u256, false)
            } else {
                (position.lp_amount as u256, true)
            };

        let pair =
            if (object::object_address(asset)
                == object::object_address(&position.asset)) {
                position.pair
            } else if (object::object_address(asset)
                == object::object_address(&position.pair)) {
                position.asset
            } else {
                assert!(false, error::invalid_argument(E_INVALID_ASSET));
                position.asset
            };

        let balance_asset_before = primary_fungible_store::balance(
            caller_address, *asset
        );
        let balance_pair_before = primary_fungible_store::balance(caller_address, pair);
        let (active_rewards, _) = get_active_rewards(pool, &position);

        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&pool));
        vector::append(&mut payload, to_bytes<address>(&position.position));
        let remove_type: u8 = 3;
        vector::append(&mut payload, to_bytes<u8>(&remove_type));
        vector::append(&mut payload, to_bytes<u256>(&liquidity_remove));
        let remove_amounts = stable_views::calc_ratio_amounts(pool, liquidity_remove);
        let min_amounts = vector::map(
            remove_amounts,
            |amount| { math128::mul_div(amount as u128, 98, 100) as u256 }
        );
        vector::append(
            &mut payload,
            to_bytes<vector<u256>>(&min_amounts)
        );

        router::remove_liquidity(caller, payload);

        let pair_amount =
            primary_fungible_store::balance(caller_address, pair) - balance_pair_before;
        if (pair_amount > 0) {
            swap_with_hyperion(caller, &pair, asset, pair_amount, false);
        };

        vector::for_each(
            active_rewards,
            |reward_token_addr| {
                if (reward_token_addr != object::object_address(asset)) {
                    let reward_balance =
                        primary_fungible_store::balance(
                            caller_address,
                            object::address_to_object<Metadata>(reward_token_addr)
                        );
                    if (reward_balance > 0) {
                        swap_with_hyperion(
                            caller,
                            &object::address_to_object<Metadata>(reward_token_addr),
                            asset,
                            reward_balance,
                            false
                        );
                    };
                };
            }
        );

        let balance_asset_after = primary_fungible_store::balance(
            caller_address, *asset
        );
        let total_withdrawn_amount = balance_asset_after - balance_asset_before;

        let total_deposited_amount =
            if (is_full_withdraw) {
                let amount = position.amount;
                vault_remove_position(caller, pool);
                amount
            } else {
                position.amount = position.amount - amount_min;
                position.lp_amount = position.lp_amount - (liquidity_remove as u128);
                vault_set_position_data(caller, pool, position);
                amount_min
            };

        (total_deposited_amount, total_withdrawn_amount)
    }

    /// Claim TAPP reward for vault
    public fun claim_tapp_reward(
        caller: &signer, asset: Object<Metadata>, pool: address
    ): u64 acquires TappData {
        let tapp_data = vault_ensure_tapp_data(caller);
        if (!vault_exists_tapp_position(tapp_data, pool)) {
            return 0
        };

        let position = vault_get_position_data(caller, pool);
        let caller_addr = signer::address_of(caller);

        if (position.position == ZERO_ADDRESS) {
            return 0
        };

        let minimal_liquidity =
            math128::min(
                MINIMUM_LIQUIDITY,
                math128::ceil_div(position.lp_amount, 10000)
            );
        let liquidity_to_remove = (position.lp_amount - minimal_liquidity) as u256;

        if (liquidity_to_remove == 0) {
            return 0
        };

        let (active_rewards, _) = get_active_rewards(pool, &position);
        if (active_rewards.is_empty()) {
            return 0
        };

        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let token_a = object::address_to_object<Metadata>(*vector::borrow(&assets, 0));
        let token_b = object::address_to_object<Metadata>(*vector::borrow(&assets, 1));

        let balance_a_before = primary_fungible_store::balance(caller_addr, token_a);
        let balance_b_before = primary_fungible_store::balance(caller_addr, token_b);

        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&pool));
        vector::append(&mut payload, to_bytes<address>(&position.position));
        let remove_type: u8 = 3;
        vector::append(&mut payload, to_bytes<u8>(&remove_type));
        vector::append(&mut payload, to_bytes<u256>(&liquidity_to_remove));
        let remove_amounts = stable_views::calc_ratio_amounts(pool, liquidity_to_remove);
        let min_amounts = vector::map(
            remove_amounts,
            |amount| { math128::mul_div(amount as u128, 98, 100) as u256 }
        );
        vector::append(
            &mut payload,
            to_bytes<vector<u256>>(&min_amounts)
        );

        router::remove_liquidity(caller, payload);

        let amount_a =
            primary_fungible_store::balance(caller_addr, token_a) - balance_a_before;
        let amount_b =
            primary_fungible_store::balance(caller_addr, token_b) - balance_b_before;

        let amounts = vector::empty<u256>();
        vector::push_back(&mut amounts, amount_a as u256);
        vector::push_back(&mut amounts, amount_b as u256);

        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&pool));
        vector::append(
            &mut payload,
            to_bytes<Option<address>>(&option::some(position.position))
        );
        vector::append(
            &mut payload,
            to_bytes<vector<u256>>(&amounts)
        );
        let minMintAmount: u256 = 0;
        vector::append(&mut payload, to_bytes<u256>(&minMintAmount));

        let (position_idx, position_addr) = integration::add_liquidity(caller, payload);
        assert!(position.position == position_addr);

        let balance_before = primary_fungible_store::balance(caller_addr, asset);

        vector::for_each(
            active_rewards,
            |reward_token_addr| {
                if (reward_token_addr != object::object_address(&asset)) {
                    let reward_balance =
                        primary_fungible_store::balance(
                            caller_addr,
                            object::address_to_object<Metadata>(reward_token_addr)
                        );
                    if (reward_balance > 0) {
                        swap_with_hyperion(
                            caller,
                            &object::address_to_object<Metadata>(reward_token_addr),
                            &asset,
                            reward_balance,
                            false
                        );
                    };
                };
            }
        );

        position.lp_amount = stable_views::position_shares(pool, position_idx) as u128;
        vault_set_position_data(caller, pool, position);

        primary_fungible_store::balance(caller_addr, asset) - balance_before
    }

    /// Get estimate withdrawable amount for vault
    public fun get_estimate_withdrawable_amount_to_asset(
        vault_addr: address, asset: &Object<Metadata>
    ): u64 acquires TappData {
        if (!exists<TappData>(vault_addr)) {
            return 0
        };
        let tapp_data = borrow_global<TappData>(vault_addr);
        let total_amount = 0;
        tapp_data.pools.for_each_ref(
            |pool, position| {
                let amount = get_estimate_withdrawable_amount(*pool, position, asset);
                total_amount = total_amount + amount;
            }
        );
        total_amount
    }

    /// Collect pool amounts for batch withdrawal
    public fun collect_pool_amounts(
        tapp_data: &OrderedMap<address, Position>
    ): vector<PoolAmountPair> {
        let pool_amounts = vector::empty<PoolAmountPair>();
        tapp_data.for_each_ref(
            |pool, position| {
                if (position.amount > 0) {
                    vector::push_back(
                        &mut pool_amounts,
                        PoolAmountPair { pool_address: *pool, amount: position.amount }
                    );
                };
            }
        );
        pool_amounts
    }

    /// Sort pools by amount (ascending)
    public fun sort_pools_by_amount_asc(
        pool_amounts: &mut vector<PoolAmountPair>
    ) {
        let len = vector::length(pool_amounts);
        if (len <= 1) return;

        let i = 0;
        while (i < len) {
            let j = 0;
            while (j < len - 1 - i) {
                let amount1 = vector::borrow(pool_amounts, j).amount;
                let amount2 = vector::borrow(pool_amounts, j + 1).amount;
                if (amount1 > amount2) {
                    vector::swap(pool_amounts, j, j + 1);
                };
                j = j + 1;
            };
            i = i + 1;
        };
    }

    /// Withdraw from pools sequentially
    public fun withdraw_from_pools_sequential(
        caller: &signer,
        asset: &Object<Metadata>,
        pool_amounts: &vector<PoolAmountPair>,
        target_amount: u64,
        withdraw_all: bool
    ): u64 acquires TappData {
        let total_withdrawn = 0;
        let remaining_needed = target_amount;
        let i = 0;
        let len = vector::length(pool_amounts);

        while (i < len && (withdraw_all || total_withdrawn < target_amount)) {
            let pair = vector::borrow(pool_amounts, i);
            let withdraw_from_this_pool =
                if (withdraw_all) {
                    pair.amount
                } else {
                    math64::min(remaining_needed, pair.amount)
                };

            if (withdraw_from_this_pool > 0) {
                let (_, actual_withdrawn) =
                    withdraw_from_tapp_impl(
                        caller,
                        asset,
                        pair.pool_address,
                        withdraw_from_this_pool
                    );

                total_withdrawn = total_withdrawn + actual_withdrawn;
                if (!withdraw_all) {
                    remaining_needed =
                        if (remaining_needed > actual_withdrawn) {
                            remaining_needed - actual_withdrawn
                        } else { 0 };
                };
            };
            i = i + 1;
        };

        total_withdrawn
    }

    /// Get amount out for swaps
    public fun get_amount_out(
        from: &Object<Metadata>, to: &Object<Metadata>, amount_in: u64
    ): u64 {
        if (amount_in == 0) return 0;
        if (object::object_address(from) == object::object_address(to))
            return amount_in;

        let (pool, _, _) = get_hyperion_pool(from, to);
        let (amount_out, _) = hyperion::pool_v3::get_amount_out(pool, *from, amount_in);
        amount_out
    }

    /// Swap with Hyperion
    public fun swap_with_hyperion(
        caller: &signer,
        from: &Object<Metadata>,
        to: &Object<Metadata>,
        amount: u64,
        exact_out: bool
    ): (u64, u64) {
        let caller_addr = signer::address_of(caller);
        let (pool, fee_tier, slippage) = get_hyperion_pool(from, to);

        let (amount_in, amount_out) =
            if (exact_out) {
                let (amt_in, _) = hyperion::pool_v3::get_amount_in(pool, *from, amount);
                let amt_in = math64::mul_div(amt_in, 10000 + slippage, 10000);
                (amt_in, amount)
            } else {
                let (amt_out, _) = hyperion::pool_v3::get_amount_out(pool, *from, amount);
                let amt_out = math64::mul_div(amt_out, 10000 - slippage, 10000);
                (amount, amt_out)
            };

        let sqrt_price_limit =
            if (hyperion::utils::is_sorted(*from, *to)) {
                04295048016
            } else {
                79226673515401279992447579055
            };

        let balance_in_before = primary_fungible_store::balance(caller_addr, *from);
        let balance_out_before = primary_fungible_store::balance(caller_addr, *to);

        if (exact_out) {
            hyperion::router_v3::exact_output_swap_entry(
                caller,
                fee_tier,
                amount_in,
                amount_out,
                sqrt_price_limit,
                *from,
                *to,
                caller_addr,
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
                caller_addr,
                timestamp::now_seconds() + 60
            );
        };

        let balance_in_after = primary_fungible_store::balance(caller_addr, *from);
        let balance_out_after = primary_fungible_store::balance(caller_addr, *to);

        (balance_in_before - balance_in_after, balance_out_after - balance_out_before)
    }

    // ========================================================================
    // SHARED HELPER FUNCTIONS
    // ========================================================================

    fun get_active_rewards(pool: address, position: &Position): (vector<address>, vector<u64>) {
        let active_reward = vector::empty<address>();
        let active_reward_amount = vector::empty<u64>();

        let rewards =
            stable::calculate_pending_rewards(
                pool,
                position::position_idx(&position::position_meta(position.position))
            );

        vector::for_each_ref(
            &rewards,
            |reward| {
                let token_addr = stable::campaign_reward_token(reward);
                let amount = stable::campaign_reward_amount(reward);
                if (amount > 0) {
                    let (found, index) = vector::index_of(&active_reward, &token_addr);
                    if (found) {
                        let existing_amount = vector::borrow_mut(
                            &mut active_reward_amount, index
                        );
                        *existing_amount = *existing_amount + amount;
                    } else {
                        vector::push_back(&mut active_reward, token_addr);
                        vector::push_back(&mut active_reward_amount, amount);
                    };
                };
            }
        );

        (active_reward, active_reward_amount)
    }

    fun get_estimate_withdrawable_amount(
        pool: address, position: &Position, asset: &Object<Metadata>
    ): u64 {
        if (position.lp_amount == 0) return 0;

        let (active_rewards, reward_amounts) = get_active_rewards(pool, position);
        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let amounts = stable_views::calc_ratio_amounts(pool, position.lp_amount as u256);

        let total_amount = 0;
        let i = 0;
        while (i < vector::length(&assets)) {
            let token_addr = *vector::borrow(&assets, i);
            let amount = *vector::borrow(&amounts, i) as u64;
            if (token_addr == object::object_address(asset)) {
                total_amount = total_amount + amount;
            } else {
                let amount_out =
                    get_amount_out(
                        &object::address_to_object<Metadata>(token_addr),
                        asset,
                        amount
                    );
                total_amount = total_amount + amount_out;
            };
            i = i + 1;
        };

        let j = 0;
        while (j < vector::length(&active_rewards)) {
            let reward_token_addr = *vector::borrow(&active_rewards, j);
            let reward_amount = *vector::borrow(&reward_amounts, j);
            if (reward_token_addr == object::object_address(asset)) {
                total_amount = total_amount + reward_amount;
            } else {
                let amount_out =
                    get_amount_out(
                        &object::address_to_object<Metadata>(reward_token_addr),
                        asset,
                        reward_amount
                    );
                total_amount = total_amount + amount_out;
            };
            j = j + 1;
        };

        total_amount
    }

    fun get_hyperion_pool(
        asset_0: &Object<Metadata>, asset_1: &Object<Metadata>
    ): (Object<hyperion::pool_v3::LiquidityPoolV3>, u8, u64) {
        assert!(
            object::object_address(asset_0) != object::object_address(asset_1),
            error::invalid_argument(E_INVALID_ASSET)
        );

        let addr_0 = object::object_address(asset_0);
        let addr_1 = object::object_address(asset_1);
        let (fee_tier, slippage) =
            if (addr_0 == APT_FA_ADDRESS || addr_1 == APT_FA_ADDRESS) {
                (1, 100)
            } else {
                (0, 50)
            };

        let (exist, pool_addr) =
            hyperion::pool_v3::liquidity_pool_address_safe(*asset_0, *asset_1, fee_tier);
        assert!(exist, error::permission_denied(E_POOL_NOT_EXIST));

        let pool =
            object::address_to_object<hyperion::pool_v3::LiquidityPoolV3>(pool_addr);
        (pool, fee_tier, slippage)
    }

    fun create_new_position(asset: &Object<Metadata>, pool: address): Position {
        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let token_a = *vector::borrow(&assets, 0);
        let token_b = *vector::borrow(&assets, 1);

        let pair =
            if (token_a == object::object_address(asset)) {
                token_b
            } else if (token_b == object::object_address(asset)) {
                token_a
            } else {
                assert!(false, error::invalid_argument(E_INVALID_ASSET));
                token_a
            };

        Position {
            position: ZERO_ADDRESS,
            lp_amount: 0,
            asset: *asset,
            pair: object::address_to_object<Metadata>(pair),
            amount: 0
        }
    }

    fun strategy_stats_deposit(asset: &Object<Metadata>, amount: u64) acquires StrategyStats {
        let stats = borrow_global_mut<StrategyStats>(@moneyfi);
        if (ordered_map::contains(&stats.assets, asset)) {
            let asset_stats = ordered_map::borrow_mut(&mut stats.assets, asset);
            asset_stats.total_value_locked =
                asset_stats.total_value_locked + (amount as u128);
            asset_stats.total_deposited = asset_stats.total_deposited
                + (amount as u128);
        } else {
            let new_asset_stats = AssetStats {
                total_value_locked: (amount as u128),
                total_deposited: (amount as u128),
                total_withdrawn: 0
            };
            ordered_map::upsert(&mut stats.assets, *asset, new_asset_stats);
        };
    }

    fun strategy_stats_withdraw(
        asset: &Object<Metadata>, deposit_amount: u64, withdraw_amount: u64
    ) acquires StrategyStats {
        let stats = borrow_global_mut<StrategyStats>(@moneyfi);
        if (ordered_map::contains(&stats.assets, asset)) {
            let asset_stats = ordered_map::borrow_mut(&mut stats.assets, asset);
            asset_stats.total_value_locked =
                asset_stats.total_value_locked - (deposit_amount as u128);
            asset_stats.total_withdrawn =
                asset_stats.total_withdrawn + (withdraw_amount as u128);
        } else {
            assert!(false, error::not_found(E_TAPP_POSITION_NOT_EXISTS));
        };
    }

    fun unpack_extra_data(extra_data: vector<vector<u8>>): ExtraData {
        ExtraData {
            pool: from_bcs::to_address(*vector::borrow(&extra_data, 0)),
            withdraw_fee: from_bcs::to_u64(*vector::borrow(&extra_data, 1))
        }
    }

    fun get_hook_data(extra_data: &vector<vector<u8>>): vector<u8> {
        *vector::borrow(extra_data, vector::length(extra_data) - 1)
    }

    fun get_strategy_type(): TypeInfo {
        type_info::type_of<TappStrategyData>()
    }

    // ========================================================================
    // WALLET ACCOUNT POSITION MANAGEMENT
    // ========================================================================

    fun ensure_tapp_strategy_data(account: &Object<WalletAccount>): TappStrategyData {
        if (!exists_tapp_strategy_data(account)) {
            let strategy_data = TappStrategyData {
                strategy_id: STRATEGY_ID,
                pools: ordered_map::new<address, Position>()
            };
            wallet_account::set_strategy_data<TappStrategyData>(account, strategy_data);
        };
        wallet_account::get_strategy_data<TappStrategyData>(account)
    }

    fun exists_tapp_strategy_data(account: &Object<WalletAccount>): bool {
        wallet_account::strategy_data_exists<TappStrategyData>(account)
    }

    fun exists_tapp_position(
        account: &Object<WalletAccount>, pool: address
    ): bool {
        assert!(
            exists_tapp_strategy_data(account),
            error::not_found(E_TAPP_STRATEGY_DATA_NOT_EXISTS)
        );
        let strategy_data = ensure_tapp_strategy_data(account);
        ordered_map::contains(&strategy_data.pools, &pool)
    }

    fun set_position_data(
        account: &Object<WalletAccount>, pool: address, position: Position
    ): TappStrategyData {
        let strategy_data = ensure_tapp_strategy_data(account);
        ordered_map::upsert(&mut strategy_data.pools, pool, position);
        strategy_data
    }

    fun create_or_get_exist_position(
        account: &Object<WalletAccount>, asset: &Object<Metadata>, extra_data: ExtraData
    ): Position {
        let strategy_data = ensure_tapp_strategy_data(account);
        if (exists_tapp_position(account, extra_data.pool)) {
            let position = ordered_map::borrow(&strategy_data.pools, &extra_data.pool);
            *position
        } else {
            create_new_position(asset, extra_data.pool)
        }
    }

    fun remove_position(account: &Object<WalletAccount>, pool: address): TappStrategyData {
        let strategy_data = ensure_tapp_strategy_data(account);
        ordered_map::remove(&mut strategy_data.pools, &pool);
        strategy_data
    }

    fun get_position_data(
        account: &Object<WalletAccount>, pool: address
    ): Position {
        assert!(
            exists_tapp_position(account, pool),
            error::not_found(E_TAPP_POSITION_NOT_EXISTS)
        );
        let strategy_data = ensure_tapp_strategy_data(account);
        let position = ordered_map::borrow(&strategy_data.pools, &pool);
        *position
    }

    // ========================================================================
    // VAULT POSITION MANAGEMENT
    // ========================================================================

    inline fun vault_ensure_tapp_data(caller: &signer): &TappData acquires TappData {
        let caller_address = signer::address_of(caller);
        if (!exists<TappData>(caller_address)) {
            move_to(
                caller,
                TappData {
                    pools: ordered_map::new<address, Position>()
                }
            );
        };
        borrow_global<TappData>(caller_address)
    }

    fun vault_exists_tapp_position(tapp_data: &TappData, pool: address): bool {
        ordered_map::contains(&tapp_data.pools, &pool)
    }

    fun vault_create_or_get_exist_position(
        caller: &signer, asset: &Object<Metadata>, pool: address
    ): Position acquires TappData {
        let tapp_data = vault_ensure_tapp_data(caller);
        if (vault_exists_tapp_position(tapp_data, pool)) {
            *ordered_map::borrow(&tapp_data.pools, &pool)
        } else {
            create_new_position(asset, pool)
        }
    }

    fun vault_get_position_data(caller: &signer, pool: address): Position acquires TappData {
        let tapp_data = vault_ensure_tapp_data(caller);
        assert!(
            vault_exists_tapp_position(tapp_data, pool),
            error::not_found(E_TAPP_POSITION_NOT_EXISTS)
        );
        *ordered_map::borrow(&tapp_data.pools, &pool)
    }

    fun vault_set_position_data(
        caller: &signer, pool: address, position: Position
    ) acquires TappData {
        let caller_address = signer::address_of(caller);
        let tapp_data = borrow_global_mut<TappData>(caller_address);
        ordered_map::upsert(&mut tapp_data.pools, pool, position);
    }

    fun vault_remove_position(caller: &signer, pool: address) acquires TappData {
        let caller_address = signer::address_of(caller);
        let tapp_data = borrow_global_mut<TappData>(caller_address);
        ordered_map::remove(&mut tapp_data.pools, &pool);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    #[view]
    public fun get_strategy_stats(asset: Object<Metadata>): (u128, u128, u128) acquires StrategyStats {
        let stats = borrow_global<StrategyStats>(@moneyfi);
        if (ordered_map::contains(&stats.assets, &asset)) {
            let asset_stats = ordered_map::borrow(&stats.assets, &asset);
            (
                asset_stats.total_value_locked,
                asset_stats.total_deposited,
                asset_stats.total_withdrawn
            )
        } else {
            (0, 0, 0)
        }
    }

    #[view]
    public fun get_user_strategy_data(wallet_id: vector<u8>): TappStrategyData {
        let account = wallet_account::get_wallet_account(wallet_id);
        assert!(
            exists_tapp_strategy_data(&account),
            error::not_found(E_TAPP_STRATEGY_DATA_NOT_EXISTS)
        );
        wallet_account::get_strategy_data<TappStrategyData>(&account)
    }

    #[view]
    public fun get_user_asset_allocation(wallet_id: vector<u8>):
        (vector<address>, vector<u64>) {
        let account = &wallet_account::get_wallet_account(wallet_id);
        if (!exists_tapp_strategy_data(account)) {
            return (vector::empty<address>(), vector::empty<u64>())
        };

        let strategy_data = ensure_tapp_strategy_data(account);
        let pools = ordered_map::keys<address, Position>(&strategy_data.pools);
        let assets = vector::empty<address>();
        let amounts = vector::empty<u64>();

        let i = 0;
        let len = vector::length(&pools);
        while (i < len) {
            let pool_address = *vector::borrow(&pools, i);
            let position =
                ordered_map::borrow<address, Position>(
                    &strategy_data.pools, &pool_address
                );
            let pool_assets =
                hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool_address));
            let pool_amounts_u256 =
                stable_views::calc_ratio_amounts(pool_address, position.lp_amount as u256);

            let j = 0;
            let asset_len = vector::length(&pool_amounts_u256);
            while (j < asset_len) {
                let amount_u256 = *vector::borrow(&pool_amounts_u256, j);
                let amount_u64 = (amount_u256 as u64);
                let asset = *vector::borrow(&pool_assets, j);

                vector::push_back(&mut assets, asset);
                vector::push_back(&mut amounts, amount_u64);
                j = j + 1;
            };
            i = i + 1;
        };

        (assets, amounts)
    }

    #[view]
    public fun pack_extra_data(pool: address, withdraw_fee: u64): vector<vector<u8>> {
        let extra_data = vector::singleton<vector<u8>>(to_bytes<address>(&pool));
        vector::push_back(&mut extra_data, to_bytes<u64>(&withdraw_fee));
        extra_data
    }

    #[view]
    public fun get_profit(wallet_id: vector<u8>): u64 {
        let account = wallet_account::get_wallet_account(wallet_id);
        if (!exists_tapp_strategy_data(&account)) {
            return 0
        };

        let strategy_data = wallet_account::get_strategy_data<TappStrategyData>(&account);
        let total_profit: u64 = 0;
        let pools = ordered_map::keys<address, Position>(&strategy_data.pools);
        let i = 0;
        let pools_len = vector::length(&pools);

        while (i < pools_len) {
            let pool_address = *vector::borrow(&pools, i);
            let position =
                ordered_map::borrow<address, Position>(
                    &strategy_data.pools, &pool_address
                );
            let profit = get_pending_rewards_and_fees_usdc(pool_address, *position);
            total_profit = total_profit + profit;
            i = i + 1;
        };

        total_profit
    }

    fun get_pending_rewards_and_fees_usdc(
        pool: address, position: Position
    ): u64 {
        if (position.lp_amount == 0) {
            return 0
        };

        let stablecoin_metadata = object::address_to_object<Metadata>(USDC_ADDRESS);
        let (active_rewards, reward_amounts) = get_active_rewards(pool, &position);
        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let amounts = stable_views::calc_ratio_amounts(pool, position.lp_amount as u256);

        let lp_path: vector<address> = vector[
            @0xd3894aca06d5f42b27c89e6f448114b3ed6a1ba07f992a58b2126c71dd83c127
        ];

        let position_amount_usdc =
            if (object::object_address(&position.asset)
                == object::object_address(&stablecoin_metadata)) {
                position.amount as u64
            } else {
                router_v3::get_batch_amount_out(
                    lp_path,
                    position.amount as u64,
                    position.asset,
                    stablecoin_metadata
                )
            };

        let total_profit: u64 = 0;
        let i = 0;
        let assets_len = vector::length(&assets);
        while (i < assets_len) {
            let asset_addr = *vector::borrow(&assets, i);
            let asset_amount = *vector::borrow(&amounts, i);
            let asset_metadata = object::address_to_object<Metadata>(asset_addr);

            if (asset_addr == object::object_address(&stablecoin_metadata)) {
                total_profit = total_profit + (asset_amount as u64);
            } else if (asset_amount > 0) {
                let amount_out =
                    router_v3::get_batch_amount_out(
                        lp_path,
                        (asset_amount as u64),
                        asset_metadata,
                        stablecoin_metadata
                    );
                total_profit = total_profit + amount_out;
            };
            i = i + 1;
        };

        let reward_path: vector<address> = vector[
            @0x925660b8618394809f89f8002e2926600c775221f43bf1919782b297a79400d8
        ];
        let reward_len = vector::length(&active_rewards);
        let j = 0;
        while (j < reward_len) {
            let reward_token_addr = *vector::borrow(&active_rewards, j);
            let reward_amount = *vector::borrow(&reward_amounts, j);
            let reward_metadata = object::address_to_object<Metadata>(reward_token_addr);

            if (reward_token_addr != object::object_address(&stablecoin_metadata)) {
                if (reward_amount > 0) {
                    let amount_out =
                        router_v3::get_batch_amount_out(
                            reward_path,
                            reward_amount,
                            reward_metadata,
                            stablecoin_metadata
                        );
                    total_profit = total_profit + amount_out;
                };
            } else {
                total_profit = total_profit + (reward_amount as u64);
            };
            j = j + 1;
        };

        if (total_profit > position_amount_usdc) {
            total_profit - position_amount_usdc
        } else { 0 }
    }
}

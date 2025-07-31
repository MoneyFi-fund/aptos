module moneyfi::hyperion_strategy {
    use std::signer;
    use std::vector;
    use std::bcs::to_bytes;
    use aptos_std::from_bcs;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset::Metadata;
    use dex_contract::router_v3;
    use dex_contract::pool_v3::{Self, LiquidityPoolV3};
    use dex_contract::rewarder;
    use dex_contract::position_v3::{Self, Info};
    use dex_contract::i32;

    use moneyfi::wallet_account::{Self, WalletAccount};
    friend moneyfi::strategy;
    // -- Constants
    const DEADLINE_BUFFER: u64 = 31556926; // 1 years
    const USDC_ADDRESS: address = @stablecoin;

    const STRATEGY_ID: u8 = 1; // Hyperion strategy id
    //const FEE_RATE_VEC: vector<u64> = vector[100, 500, 3000, 10000]; fee_tier is [0, 1, 2, 3] for [0.01%, 0.05%, 0.3%, 1%] ??

    //-- Errors
    /// Hyperion Strategy data not exists
    const E_HYPERION_STRATEGY_DATA_NOT_EXISTS: u64 = 1;
    /// Pool not exists
    const E_HYPERION_POOL_NOT_EXISTS: u64 = 2;
    /// Position not exists
    const E_HYPERION_POSITION_NOT_EXISTS: u64 = 3;

    // -- Structs
    struct StrategyStats has key {
        assets: OrderedMap<Object<Metadata>, AssetStats> // assets -> AssetStats
    }

    struct AssetStats has drop, store {
        total_value_locked: u128, // total value locked in this asset
        total_deposited: u128, // total deposited amount
        total_withdrawn: u128 // total withdrawn amount
    }

    struct HyperionStrategyData has copy, drop, store {
        strategy_id: u8,
        pools: OrderedMap<address, Position> // pool address -> Position
    }

    struct Position has copy, drop, store {
        position: Object<Info>,
        lp_amount: u128, // Liquidity pool amount
        asset: Object<Metadata>,
        pair: Object<Metadata>,
        amount: u64,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        // The amount of interest earned from the position
        interest_amount: u64,
        // The remaining amount after update tick
        remaining_amount: u64
    }

    struct ExtraData has drop, copy, store {
        fee_tier: u8,
        pool: address,
        slippage_numerator: u256,
        slippage_denominator: u256,
        threshold_numerator: u256,
        threshold_denominator: u256,
        withdraw_fee: u64
    }

    //--initialization
    fun init_module(sender: &signer) {
        move_to(
            sender,
            StrategyStats {
                assets: ordered_map::new<Object<Metadata>, AssetStats>()
            }
        );
    }

    //-- private functions

    // returns(actual_amount)
    public(friend) fun deposit_fund_to_hyperion_single(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount_in: u64,
        extra_data: vector<vector<u8>>
    ): u64 acquires StrategyStats {
        let extra_data = unpack_extra_data(extra_data);
        let position =
            create_or_get_exist_position(
                account,
                asset,
                extra_data.pool,
                extra_data.fee_tier
            );

        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let balance_pair_before =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.pair
            );
        let balance_asset_before =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.asset
            );
        router_v3::add_liquidity_single(
            &wallet_signer,
            position.position,
            position.asset,
            position.pair,
            amount_in,
            extra_data.slippage_numerator,
            extra_data.slippage_denominator,
            extra_data.threshold_numerator,
            extra_data.threshold_denominator
        );

        let remaining_balance =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.pair
            ) - balance_pair_before;
        if (remaining_balance > 0) {
            router_v3::exact_input_swap_entry(
                &wallet_signer,
                extra_data.fee_tier,
                remaining_balance,
                0,
                4295048016 + 1,
                position.pair,
                *asset,
                signer::address_of(&wallet_signer),
                timestamp::now_seconds() + DEADLINE_BUFFER
            );
        };

        let balance_asset_after =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.asset
            );

        let actual_amount = balance_asset_before - balance_asset_after;
        position.lp_amount = position_v3::get_liquidity(position.position);
        position.amount = position.amount + actual_amount;
        let strategy_data = set_position_data(account, extra_data.pool, position);
        wallet_account::set_strategy_data(account, strategy_data);
        strategy_stats_deposit(asset, actual_amount);
        actual_amount // returns (actual_amount)
    }

    // return (total_deposited_amount, total_withdrawn_amount, withdraw_fee)
    public(friend) fun withdraw_fund_from_hyperion_single(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount_min: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64, u64) acquires StrategyStats {
        let extra_data = unpack_extra_data(extra_data);
        let position = get_position_data(account, extra_data.pool);
        let (liquidity_remove, is_full_withdraw) =
            if (amount_min
                < (position.amount - position.remaining_amount
                    + position.interest_amount)) {
                let liquidity =
                    math128::mul_div(
                        position.lp_amount,
                        (amount_min as u128),
                        (
                            (
                                position.amount - position.remaining_amount
                                    + position.interest_amount
                            ) as u128
                        )
                    );
                (liquidity, false)
            } else {
                (position.lp_amount, true)
            };
        let (interest) = claim_fees_and_rewards_single(account, position);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        let balance_before = primary_fungible_store::balance(wallet_address, *asset);
        router_v3::remove_liquidity_single(
            &wallet_signer,
            position.position,
            liquidity_remove,
            *asset,
            extra_data.slippage_numerator,
            extra_data.slippage_denominator
        );
        let balance_after = primary_fungible_store::balance(wallet_address, *asset);
        let (strategy_data, total_deposited_amount) =
            if (!is_full_withdraw) {
                let total = balance_after - balance_before + position.remaining_amount;
                position.amount = position.amount - total;
                position.interest_amount = 0;
                position.remaining_amount = 0;
                position.lp_amount = position_v3::get_liquidity(position.position);
                (set_position_data(account, extra_data.pool, position), total)
            } else {
                (remove_position(account, extra_data.pool), position.amount)
            };
        wallet_account::set_strategy_data(account, strategy_data);
        let total_withdrawn_amount =
            balance_after - balance_before + position.remaining_amount + interest;
        strategy_stats_withdraw(asset, total_deposited_amount, total_withdrawn_amount);
        (total_deposited_amount, total_withdrawn_amount, extra_data.withdraw_fee)
    }

    public(friend) fun update_tick(
        account: &Object<WalletAccount>, extra_data: vector<vector<u8>>
    ) {
        let extra_data = unpack_extra_data(extra_data);
        if (!exists_hyperion_strategy_data(account)) { return };
        if (!exists_hyperion_postion(account, extra_data.pool)) { return };
        let position = get_position_data(account, extra_data.pool);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        let (current_tick, _) = pool_v3::current_tick_and_price(extra_data.pool);
        let (token_a, token_b, _) = position_v3::get_pool_info(position.position);
        if (i32::gt(i32::from_u32(current_tick), i32::from_u32(position.tick_lower))
            && i32::lt(i32::from_u32(current_tick), i32::from_u32(position.tick_lower))) {
            return
        };
        let tick_spacing = pool_v3::get_tick_spacing(position.fee_tier);
        let new_tick_lower =
            i32::wrapping_sub(i32::from_u32(current_tick), i32::from_u32(tick_spacing));
        let new_tick_upper =
            i32::wrapping_add(i32::from_u32(current_tick), i32::from_u32(tick_spacing));

        let liquidity = position_v3::get_liquidity(position.position);
        if (liquidity == 0) { return };
        let balance_before_remove =
            primary_fungible_store::balance(wallet_address, position.asset);
        let interest = claim_fees_and_rewards_single(account, position);
        router_v3::remove_liquidity_single(
            &wallet_signer,
            position.position,
            liquidity,
            position.asset,
            extra_data.slippage_numerator,
            extra_data.slippage_denominator
        );
        let balance_after_remove =
            primary_fungible_store::balance(wallet_address, position.asset);
        let balance_pair_before =
            primary_fungible_store::balance(wallet_address, position.pair);
        let new_position =
            pool_v3::open_position(
                &wallet_signer,
                token_a,
                token_b,
                position.fee_tier,
                i32::as_u32(new_tick_lower),
                i32::as_u32(new_tick_upper)
            );

        router_v3::add_liquidity_single(
            &wallet_signer,
            new_position,
            position.asset,
            position.pair,
            balance_after_remove - balance_before_remove + position.remaining_amount,
            extra_data.slippage_numerator,
            extra_data.slippage_denominator,
            extra_data.threshold_numerator,
            extra_data.threshold_denominator
        );

        let balance_after_add =
            primary_fungible_store::balance(wallet_address, position.asset);

        let remaining_balance =
            primary_fungible_store::balance(wallet_address, position.pair)
                - balance_pair_before;
        if (remaining_balance > 0) {
            router_v3::exact_input_swap_entry(
                &wallet_signer,
                extra_data.fee_tier,
                remaining_balance,
                0,
                4295048016 + 1, // min
                position.pair,
                position.asset,
                wallet_address,
                timestamp::now_seconds() + DEADLINE_BUFFER // deadline
            );
        };

        position.position = new_position;
        position.lp_amount = position_v3::get_liquidity(new_position);
        position.tick_lower = i32::as_u32(new_tick_lower);
        position.tick_upper = i32::as_u32(new_tick_upper);
        position.interest_amount = position.interest_amount + interest;
        position.remaining_amount =
            primary_fungible_store::balance(wallet_address, position.asset)
                - balance_after_add;
        let strategy_data = set_position_data(account, extra_data.pool, position);
        wallet_account::set_strategy_data(account, strategy_data);
    }

    // return (
    //    actual_amount_in,
    //    actual_amount_out
    // )
    public(friend) fun swap(
        account: &Object<WalletAccount>,
        from_asset: &Object<Metadata>,
        to_asset: &Object<Metadata>,
        amount_in: u64,
        min_amount_out: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64) {
        let extra_data = unpack_extra_data(extra_data);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        let balance_in_before =
            primary_fungible_store::balance(wallet_address, *from_asset);
        let balance_out_before = primary_fungible_store::balance(
            wallet_address, *to_asset
        );
        router_v3::exact_input_swap_entry(
            &wallet_signer,
            extra_data.fee_tier, // fee_tier for reward swaps
            amount_in,
            min_amount_out,
            4295048016 + 1, // min
            *from_asset,
            *to_asset,
            wallet_address,
            timestamp::now_seconds() + DEADLINE_BUFFER // deadline
        );
        let balance_in_after = primary_fungible_store::balance(
            wallet_address, *from_asset
        );
        let balance_out_after = primary_fungible_store::balance(
            wallet_address, *to_asset
        );

        (balance_in_before - balance_in_after, balance_out_after - balance_out_before)
    }

    fun claim_fees_and_rewards_single(
        account: &Object<WalletAccount>, position: Position
    ): u64 { //return all_profit and amount_swap_token_pair
        // Get pool and fee information (still needed for swapping)
        let pending_fees = pool_v3::get_pending_fees(position.position);
        let gas_fee_a = *vector::borrow(&pending_fees, 0);
        let gas_fee_b = *vector::borrow(&pending_fees, 1);
        // Get reward information
        let pending_rewards = pool_v3::get_pending_rewards(position.position);

        // Claim fees and rewards for single position
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        // Get balance before claiming
        let balance_before =
            primary_fungible_store::balance(wallet_address, position.asset);
        let position_addresses = vector::empty<address>();
        vector::push_back(
            &mut position_addresses, object::object_address<Info>(&position.position)
        );

        router_v3::claim_fees_and_rewards_directly_deposit(
            &wallet_signer, position_addresses
        );
        let (token_a, token_b, _) = position_v3::get_pool_info(position.position);
        let asset = position.asset;

        // Swap token_a to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&token_a)
            != object::object_address<Metadata>(&asset)) {
            if (gas_fee_a > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    position.fee_tier,
                    gas_fee_a,
                    0,
                    4295048016 + 1, // min
                    token_a,
                    asset,
                    wallet_address,
                    timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                );
            };
        };

        // Swap token_b to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&token_b)
            != object::object_address<Metadata>(&asset)) {
            if (gas_fee_b > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    position.fee_tier,
                    gas_fee_b,
                    0,
                    4295048016 + 1, // min
                    token_b,
                    asset,
                    wallet_address,
                    timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                );
            };
        };

        // Swap reward tokens to stablecoin
        let p = 0;
        let rewards_len = vector::length(&pending_rewards);
        while (p < rewards_len) {
            let reward = vector::borrow(&pending_rewards, p);
            let (reward_token, reward_amount) = rewarder::pending_rewards_unpack(reward);

            if (object::object_address<Metadata>(&reward_token)
                != object::object_address<Metadata>(&asset)) {
                if (reward_amount > 1000) {
                    router_v3::exact_input_swap_entry(
                        &wallet_signer,
                        1, // fee_tier for reward swaps
                        reward_amount,
                        0,
                        4295048016 + 1, // min
                        reward_token,
                        asset,
                        wallet_address,
                        timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                    );
                };
            };

            p = p + 1;
        };

        // Get balance after claiming and swapping
        let balance_after = primary_fungible_store::balance(wallet_address, asset);

        // Calculate total stablecoin amount gained
        (balance_after - balance_before)
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
            assert!(false, E_HYPERION_POSITION_NOT_EXISTS);
        };
    }

    fun ensure_hyperion_strategy_data(account: &Object<WalletAccount>): HyperionStrategyData {
        if (!exists_hyperion_strategy_data(account)) {
            let strategy_data = HyperionStrategyData {
                strategy_id: STRATEGY_ID,
                pools: ordered_map::new<address, Position>()
            };
            wallet_account::set_strategy_data<HyperionStrategyData>(
                account, strategy_data
            );
        };
        let strategy_data =
            wallet_account::get_strategy_data<HyperionStrategyData>(account);
        strategy_data
    }

    fun exists_hyperion_strategy_data(account: &Object<WalletAccount>): bool {
        wallet_account::strategy_data_exists<HyperionStrategyData>(account)
    }

    fun exists_hyperion_postion(
        account: &Object<WalletAccount>, pool: address
    ): bool {
        assert!(
            exists_hyperion_strategy_data(account),
            E_HYPERION_STRATEGY_DATA_NOT_EXISTS
        );
        let strategy_data = ensure_hyperion_strategy_data(account);
        ordered_map::contains(&strategy_data.pools, &pool)
    }

    fun set_position_data(
        account: &Object<WalletAccount>, pool: address, position: Position
    ): HyperionStrategyData {
        let strategy_data = ensure_hyperion_strategy_data(account);
        ordered_map::upsert(&mut strategy_data.pools, pool, position);
        strategy_data
    }

    fun remove_position(account: &Object<WalletAccount>, pool: address): HyperionStrategyData {
        let strategy_data = ensure_hyperion_strategy_data(account);
        ordered_map::remove(&mut strategy_data.pools, &pool);
        strategy_data
    }

    fun get_position_data(account: &Object<WalletAccount>, pool: address): Position {
        assert!(exists_hyperion_postion(account, pool), E_HYPERION_POSITION_NOT_EXISTS);
        let strategy_data = ensure_hyperion_strategy_data(account);
        let position = ordered_map::borrow(&strategy_data.pools, &pool);
        *position
    }

    fun create_or_get_exist_position(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        pool: address,
        fee_tier: u8
    ): Position {
        let strategy_data = ensure_hyperion_strategy_data(account);
        let position =
            if (exists_hyperion_postion(account, pool)) {
                let position = ordered_map::borrow(&strategy_data.pools, &pool);
                *position
            } else {
                assert!(object::object_exists<LiquidityPoolV3>(pool), 0x10034);
                let pool_obj = object::address_to_object<LiquidityPoolV3>(pool);
                let assets = pool_v3::supported_inner_assets(pool_obj);
                let token_a = vector::borrow(&assets, 0);
                let token_b = vector::borrow(&assets, 1);
                let (current_tick, _) = pool_v3::current_tick_and_price(pool);
                let tick_spacing = pool_v3::get_tick_spacing(fee_tier);
                let tick_lower =
                    i32::wrapping_sub(
                        i32::from_u32(current_tick), i32::from_u32(tick_spacing)
                    );
                let tick_upper =
                    i32::wrapping_add(
                        i32::from_u32(current_tick), i32::from_u32(tick_spacing)
                    );
                let position =
                    pool_v3::open_position(
                        &wallet_account::get_wallet_account_signer(account),
                        *token_a,
                        *token_b,
                        fee_tier,
                        i32::as_u32(tick_lower),
                        i32::as_u32(tick_upper)
                    );
                let pair =
                    if (object::object_address<Metadata>(asset)
                        == object::object_address<Metadata>(token_a)) {
                        *token_b
                    } else {
                        *token_a
                    };
                let new_position = Position {
                    position,
                    lp_amount: 0,
                    asset: *asset,
                    pair,
                    amount: 0,
                    fee_tier,
                    tick_lower: i32::as_u32(tick_lower),
                    tick_upper: i32::as_u32(tick_upper),
                    interest_amount: 0,
                    remaining_amount: 0
                };
                new_position
            };
        position
    }

    fun get_position(account: &Object<WalletAccount>, pool: address): Object<Info> {
        let position = get_position_data(account, pool);
        position.position
    }

    //Public
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

    //-- Views
    #[view]
    public fun get_user_strategy_data(wallet_id: vector<u8>): HyperionStrategyData {
        let account = wallet_account::get_wallet_account(wallet_id);
        if (!exists_hyperion_strategy_data(&account)) {
            assert!(false, E_HYPERION_STRATEGY_DATA_NOT_EXISTS);
        };
        wallet_account::get_strategy_data<HyperionStrategyData>(&account)
    }

    fun unpack_extra_data(extra_data: vector<vector<u8>>): ExtraData {
        let extra_data = ExtraData {
            fee_tier: from_bcs::to_u8(*vector::borrow(&extra_data, 0)),
            pool: from_bcs::to_address(*vector::borrow(&extra_data, 1)),
            slippage_numerator: from_bcs::to_u256(*vector::borrow(&extra_data, 2)),
            slippage_denominator: from_bcs::to_u256(*vector::borrow(&extra_data, 3)),
            threshold_numerator: from_bcs::to_u256(*vector::borrow(&extra_data, 4)),
            threshold_denominator: from_bcs::to_u256(*vector::borrow(&extra_data, 5)),
            withdraw_fee: from_bcs::to_u64(*vector::borrow(&extra_data, 6))
        };
        extra_data
    }

    #[view]
    public fun pack_extra_data(
        fee_tier: u8,
        pool: address,
        slippage_numerator: u256,
        slippage_denominator: u256,
        threshold_numerator: u256,
        threshold_denominator: u256,
        withdraw_fee: u64
    ): vector<vector<u8>> {
        let extra_data = vector::singleton<vector<u8>>(to_bytes<u8>(&fee_tier));
        vector::push_back(&mut extra_data, to_bytes<address>(&pool));
        vector::push_back(&mut extra_data, to_bytes<u256>(&slippage_numerator));
        vector::push_back(&mut extra_data, to_bytes<u256>(&slippage_denominator));
        vector::push_back(&mut extra_data, to_bytes<u256>(&threshold_numerator));
        vector::push_back(&mut extra_data, to_bytes<u256>(&threshold_denominator));
        vector::push_back(&mut extra_data, to_bytes<u64>(&withdraw_fee));
        extra_data
    }

    #[view]
    public fun get_profit(wallet_id: vector<u8>): u64 {
        let account = wallet_account::get_wallet_account(wallet_id);
        if (!exists_hyperion_strategy_data(&account)) {
            return 0
        };
        let strategy_data =
            wallet_account::get_strategy_data<HyperionStrategyData>(&account);
        let total_profit: u64 = 0;
        let pools = ordered_map::keys<address, Position>(&strategy_data.pools);
        let i = 0;
        let len = ordered_map::length(&strategy_data.pools);
        while (i < len) {
            let pool = *vector::borrow<address>(&pools, i);
            let position = get_position(&account, pool);
            total_profit = total_profit + get_pending_rewards_and_fees_usdc(position);
            i = i + 1;
        };

        total_profit
    }

    fun get_pending_rewards_and_fees_usdc(position: Object<Info>): u64 {
        let stablecoin_metadata = object::address_to_object<Metadata>(USDC_ADDRESS);
        let total_stablecoin_amount: u64 = 0;

        // Get pool and fee information
        let (token_a, token_b, fee_tier) = position_v3::get_pool_info(position);
        let pending_fees = pool_v3::get_pending_fees(position);
        let gas_fee_a = *vector::borrow(&pending_fees, 0);
        let gas_fee_b = *vector::borrow(&pending_fees, 1);

        // Get reward information
        let pending_rewards = pool_v3::get_pending_rewards(position);

        // Convert fees to stablecoin
        if (gas_fee_a > 0
            && object::object_address<Metadata>(&token_a)
                != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_a_to_stable =
                pool_v3::liquidity_pool(token_a, stablecoin_metadata, fee_tier);
            let (amount_out_a, _) =
                pool_v3::get_amount_out(pool_a_to_stable, token_a, gas_fee_a);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_a;
        } else if (gas_fee_a > 0
            && object::object_address<Metadata>(&token_a)
                == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + gas_fee_a;
        };

        if (gas_fee_b > 0
            && object::object_address<Metadata>(&token_b)
                != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_b_to_stable =
                pool_v3::liquidity_pool(token_b, stablecoin_metadata, fee_tier);
            let (amount_out_b, _) =
                pool_v3::get_amount_out(pool_b_to_stable, token_b, gas_fee_b);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_b;
        } else if (gas_fee_b > 0
            && object::object_address<Metadata>(&token_b)
                == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + gas_fee_b;
        };

        // Convert rewards to stablecoin
        let j = 0;
        let rewards_len = vector::length(&pending_rewards);
        while (j < rewards_len) {
            let reward = vector::borrow(&pending_rewards, j);
            let (reward_token, reward_amount) = rewarder::pending_rewards_unpack(reward);

            if (reward_amount > 0
                && object::object_address<Metadata>(&reward_token)
                    != object::object_address<Metadata>(&stablecoin_metadata)) {
                let pool_reward_to_stable =
                    pool_v3::liquidity_pool(reward_token, stablecoin_metadata, 1);
                let (amount_out_reward, _) =
                    pool_v3::get_amount_out(
                        pool_reward_to_stable, reward_token, reward_amount
                    );
                total_stablecoin_amount = total_stablecoin_amount + amount_out_reward;
            } else if (reward_amount > 0
                && object::object_address<Metadata>(&reward_token)
                    == object::object_address<Metadata>(&stablecoin_metadata)) {
                total_stablecoin_amount = total_stablecoin_amount + reward_amount;
            };

            j = j + 1;
        };
        total_stablecoin_amount
    }
}

module moneyfi::hyperion_strategy {
    use std::signer;
    use std::vector;
    use std::bcs::to_bytes;
    use aptos_std::from_bcs::from_bytes;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset::Metadata;
    use dex_contract::i32::{Self, I32};
    use dex_contract::router_v3;
    use dex_contract::pool_v3::{Self, LiquidityPoolV3};
    use dex_contract::rewarder;
    use dex_contract::position_v3::{Self, Info};

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
    struct HyperionStrategyData has store {
        strategy_id: u8,
        pools: OrderedMap<address, Position> // pool address -> Position
    }

    struct Position has drop, store {
        position: Object<Info>,
        lp_amount: u128, // Liquidity pool amount
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        amount_a: u64,
        amount_b: u64,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32
    }

    struct ExtraData has drop, store {
        gas_fee: u64,
        fee_tier: u8,
        slippage_numerator: u256,
        slippage_denominator: u256,
        threshold_numerator: u256,
        threshold_denominator: u256
    }

    #[view]
    public fun pack_extra_data(
        gas_fee: u64,
        fee_tier: u8,
        slippage_numerator: u256,
        slippage_denominator: u256,
        threshold_numerator: u256,
        threshold_denominator: u256
    ): vector<u8> {
        let extra_data = ExtraData {
            gas_fee,
            fee_tier: fee_tier,
            slippage_numerator,
            slippage_denominator,
            threshold_numerator,
            threshold_denominator
        };
        to_bytes<ExtraData>(&extra_data)
    }

    //-- Entries
    public(friend) fun deposit_fund_to_hyperion_single(
        account: Object<WalletAccount>,
        pool: address,
        asset: Object<Metadata>,
        amount_in: u64,
        extra_data: vector<u8>
    ): (u64, u64) acquires HyperionStrategyData { // returns(actual_amount, gas_fee)
        let extra_data = unpack_extra_data(extra_data);
        let position = create_or_get_exist_position(account, pool, extra_data.fee_tier);

        let token_pair =
            if (object::object_address<Metadata>(&asset)
                != object::object_address<Metadata>(&position.token_a)) {
                position.token_a
            } else {
                position.token_b
            };

        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let balance_pair_before =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), token_pair
            );
        let balance_a_before =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.token_a
            );
        let balance_b_before =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.token_b
            );
        router_v3::add_liquidity_single(
            &wallet_signer,
            position.position,
            asset,
            token_pair,
            amount_in - extra_data.gas_fee,
            extra_data.slippage_numerator,
            extra_data.slippage_denominator,
            extra_data.threshold_numerator,
            extra_data.threshold_denominator
        );

        let remaining_balance =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), token_pair
            ) - balance_pair_before;
        if (remaining_balance > 0) {
            router_v3::exact_input_swap_entry(
                &wallet_signer,
                extra_data.fee_tier,
                remaining_balance,
                0,
                4295048016 + 1,
                token_pair,
                asset,
                signer::address_of(&wallet_signer),
                timestamp::now_seconds() + DEADLINE_BUFFER
            );
        };

        let balance_a_after =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.token_a
            );
        let balance_b_after =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.token_b
            );

        let actual_amount =
            if (object::object_address<Metadata>(&asset)
                == object::object_address<Metadata>(&position.token_a)) {
                balance_a_before - balance_a_after - extra_data.gas_fee
            } else {
                balance_b_before - balance_b_after - extra_data.gas_fee
            };
        position.lp_amount = position_v3::get_liquidity(position.position);
        position.amount_a = position.amount_a + (balance_a_after - balance_a_before);
        position.amount_b = position.amount_b + (balance_b_after - balance_b_before);
        let strategy_data = set_position_data(account, pool, position);

        wallet_account::set_strategy_data(account, strategy_data);
        (actual_amount, extra_data.gas_fee) // returns (actual_amount, gas_fee)
    }

    public entry fun withdraw_fund_from_hyperion_single(
        account: Object<WalletAccount>,
        pool: address,
        asset: Object<Metadata>,
        amount_min: u64,
        extra_data: vector<u8>
    ): (u64, u64, u64) acquires HyperionStrategyData { //// return (total_deposited_amount, total_withdrawn_amount, gas_fee)
        let extra_data = unpack_extra_data(extra_data);
        let position = get_position_data(account, pool);
        let liquidity_remove =
            if (amount_min < (postion.amonut_a + position.amount_b)) {
                math128::mul_div(
                    position.lp_amount,
                    (amount_min as u128),
                    ((postion.amonut_a + position.amount_b) as u128)
                )
            } else {
                position.lp_amount
            };
        let (interest, _) = claim_fees_and_rewards_single(account, position, asset);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        let balance_before = primary_fungible_store::balance(wallet_address, asset);
        router_v3::remove_liquidity_single(
            &wallet_signer,
            position.position,
            liquidity_remove,
            asset,
            extra_data.slippage_numerator,
            extra_data.slippage_denominator
        );
        let balance_after = primary_fungible_store::balance(wallet_address, asset);
        let (strategy_data, total_deposited_amount) =
            if (amount_min < (postion.amonut_a + position.amount_b)) {
                let total = balance_after - balance_before;
                if (object::object_address<Metadata>(&position.token_a)
                    == object::object_address<Metadata>(&asset)) {
                    position.amount_a = position.amount_a - total;
                } else {
                    position.amount_b = position.amount_b - total;
                };
                (set_position_data(account, pool, position), total)
            } else {
                let total = postion.amonut_a + position.amount_b;
                (remove_position(account, pool), total)
            };
        wallet_account::set_strategy_data(account, strategy_data);
        let total_withdrawn_amount = total_deposited_amount + interest;
        (total_deposited_amount, total_withdrawn_amount, extra_data.gas_fee)
    }

    //return (
    //     total_deposited_amount_0,
    //     total_deposited_amount_1,
    //     total_withdrawn_amount_0,
    //     total_withdrawn_amount_1,
    //     amount_0_in,
    //     amount_1_out,
    // )
    public(friend) fun withdraw_fun_from_hyperion(
        account: Object<WalletAccount>,
        pool: address,
        asset_0: Object<Metadata>,
        asset_1: Object<Metadata>,
        amount_0: u64,
        amount_1: u64,
        extra_data: vector<u8>
    ): (u64, u64, u64, u64, u64, u64) {
        let extra_data = unpack_extra_data(extra_data);
        let position = get_position_data(account, pool);
        let is_asset_0_token_a =
            object::object_address<Metadata>(&asset_0)
                == object::object_address<Metadata>(&position.token_a);

        let total_request = amount_0 + amount_1;
        let total_position_amount = position.amount_a + position.amount_b;
        let (liquidity_remove, is_full_withdraw) =
            if (total_request < total_position_amount) {
                let liquidity =
                    math128::mul_div(
                        position.lp_amount,
                        (total_request as u128),
                        (total_position_amount as u128)
                    );
                (liquidity, false)
            } else {
                (position.lp_amount, true)
            };

        let (reward_1, amount_0_reward_swap) =
            claim_fees_and_rewards_single(account, position, asset);
        let balance_before = primary_fungible_store::balance(wallet_address, asset_1);
    }

    fun claim_fees_and_rewards_single(
        account: Object<WalletAccount>, position: Position, asset: Object<Metadata>
    ): (u64, u64) acquires HyperionStrategyData { //return all_profit and amount_swap_token_pair
        // Get pool and fee information (still needed for swapping)
        let pending_fees = get_pending_fees(position.position);
        let gas_fee_a = *vector::borrow(&pending_fees, 0);
        let gas_fee_b = *vector::borrow(&pending_fees, 1);
        let amount_swap_token_pair = 0;
        // Get reward information
        let pending_rewards = get_pending_rewards(position.position);

        // Claim fees and rewards for single position
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        // Get balance before claiming
        let balance_before = primary_fungible_store::balance(wallet_address, asset);
        let position_addresses = vector::empty<address>();
        vector::push_back(
            &mut position_addresses, object::object_address<Info>(&position.position)
        );

        router_v3::claim_fees_and_rewards_directly_deposit(
            &wallet_signer, position_addresses
        );

        // Swap token_a to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&position.token_a)
            != object::object_address<Metadata>(&asset)) {
            if (gas_fee_a > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    position.fee_tier,
                    gas_fee_a,
                    0,
                    4295048016 + 1, // min
                    position.token_a,
                    asset,
                    wallet_address,
                    timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                );
                amount_swap_token_pair = gas_fee_a;
            };
        };

        // Swap token_b to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&position.token_b)
            != object::object_address<Metadata>(&asset)) {
            if (gas_fee_b > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    position.fee_tier,
                    gas_fee_b,
                    0,
                    4295048016 + 1, // min
                    position.token_b,
                    asset,
                    wallet_address,
                    timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                );
                amount_swap_token_pair = gas_fee_b
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
        ((balance_after - balance_before), amount_swap_token_pair)
    }

    fun unpack_extra_data(extra_data: vector<u8>): ExtraData {
        from_bytes<ExtraData>(extra_data)
    }

    fun ensure_hyperion_strategy_data(
        account: Object<WalletAccount>
    ): &mut HyperionStrategyData acquires HyperionStrategyData {
        if (exists_hyperion_strategy_data(account)) {
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
        &mut strategy_data
    }

    fun exists_hyperion_strategy_data(
        account: Object<WalletAccount>
    ): bool acquires HyperionStrategyData {
        wallet_account::exists_strategy_data<HyperionStrategyData>(account)
    }

    fun exists_hyperion_postion(
        account: Object<WalletAccount>, pool: address
    ): bool acquires HyperionStrategyData {
        assert!(
            exists_hyperion_strategy_data(account),
            E_HYPERION_STRATEGY_DATA_NOT_EXISTS
        );
        let strategy_data = ensure_hyperion_strategy_data(account);
        ordered_map::contains(&strategy_data.pools, &pool)
    }

    fun set_position_data(
        account: Object<WalletAccount>, pool: address, position: Position
    ): HyperionStrategyData acquires HyperionStrategyData {
        let strategy_data = ensure_hyperion_strategy_data(account);
        ordered_map::upsert(&mut strategy_data.pools, pool, position);
        *strategy_data
    }

    fun remove_position(
        account: Object<WalletAccount>, pool: address
    ): HyperionStrategyData acquires HyperionStrategyData {
        let strategy_data = ensure_hyperion_strategy_data(account);
        ordered_map::remove(&mut strategy_data.pools, pool);
        *strategy_data
    }

    fun get_position_data(
        account: Object<WalletAccount>, pool: address
    ): Position acquires HyperionStrategyData {
        assert!(exists_hyperion_postion(account, pool), E_HYPERION_POSITION_NOT_EXISTS);
        let strategy_data = ensure_hyperion_strategy_data(account);
        let position = ordered_map::borrow(&strategy_data.pools, &pool);
        *position
    }

    fun create_or_get_exist_position(
        account: Object<WalletAccount>, pool: address, fee_tier: u8
    ): Position acquires HyperionStrategyData {
        let strategy_data = ensure_hyperion_strategy_data(account);
        let position =
            if (exists_hyperion_postion(account, pool)) {
                let position = ordered_map::borrow(&strategy_data.pools, &pool);
                *position
            } else {
                let pool_obj = object::address_to_object<LiquidityPoolV3>(pool);
                let assets = pool_v3::supported_inner_assets(pool_obj);
                let token_a = *vector::borrow(&assets, 0);
                let token_b = *vector::borrow(&assets, 1);
                let (current_tick, _) = pool_v3::current_tick_and_price(pool);
                let tick_spacing = pool_v3::get_tick_spacing(fee_tier);
                let position =
                    pool_v3::open_position(
                        &wallet_account::get_wallet_account_signer(account),
                        token_a,
                        token_b,
                        fee_tier,
                        current_tick - tick_spacing,
                        current_tick + tick_spacing
                    );
                let new_position = Position {
                    position,
                    lp_amount: 0,
                    token_a,
                    token_b,
                    amount_a: 0,
                    amount_b: 0,
                    fee_tier,
                    tick_lower: current_tick - tick_spacing,
                    tick_upper: current_tick + tick_spacing
                };
                new_position
            };
        position
    }

    fun get_position(
        account: Object<WalletAccount>, pool: address
    ): Object<Info> acquires HyperionStrategyData {
        let position = get_position_data(account, pool);
        position.position
    }

    public entry fun update_tick(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        asset: Object<Metadata>,
        tick_lower: u32,
        tick_upper: u32,
        gas_fee: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        let wallet_address = signer::address_of(&wallet_signer);
        let (tick_lower_before, tick_upper_before) = position_v3::get_tick(position);
        let current = tick_lower + 1;
        //current >= i32::as_u32(tick_lower_before) && current <= i32::as_u32(tick_upper_before)
        if (current >= i32::as_u32(tick_lower_before)
            && current <= i32::as_u32(tick_upper_before)) { return }
        else {
            let (token_a, token_b, fee_tier) = get_pool_info(position);
            remove_liquidity_single_from_operator(
                operator,
                wallet_id,
                position,
                asset,
                999,
                1000,
                0
            );
            let token_pair =
                if (object::object_address(&asset) != object::object_address(&token_a)) {
                    token_a
                } else {
                    token_b
                };

            let new_position =
                pool_v3::open_position(
                    &wallet_signer,
                    token_a,
                    token_b,
                    fee_tier,
                    tick_lower,
                    tick_upper
                );

            let balance_before = primary_fungible_store::balance(wallet_address, asset);

            router_v3::add_liquidity_single(
                &wallet_signer,
                new_position,
                asset,
                token_pair,
                balance_before - gas_fee,
                999,
                1000,
                1,
                1
            );

            let total_asset_amonut_added =
                balance_before - primary_fungible_store::balance(wallet_address, asset);

            let remaining_balance =
                primary_fungible_store::balance(wallet_address, token_pair);
            if (remaining_balance > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    fee_tier,
                    remaining_balance,
                    0,
                    4295048016 + 1,
                    token_pair,
                    asset,
                    wallet_address,
                    timestamp::now_seconds() + DEADLINE_BUFFER
                );
            };
            wallet_account::add_position_opened(
                wallet_id,
                object::object_address<Info>(&new_position),
                vector::singleton<address>(object::object_address<Metadata>(&asset)),
                vector::singleton<u64>(total_asset_amonut_added),
                STRATEGY_ID,
                gas_fee
            );
            wallet_account::remove_profit_unclaimed(
                wallet_id,
                object::object_address<Metadata>(&asset)
            );
        };
    }

    //-- Views
    #[view]
    public fun get_profit(wallet_id: vector<u8>): u64 {
        let (position_addrs, strategy_ids) =
            wallet_account::get_position_opened(wallet_id);
        let total_profit: u64 = 0;

        let i = 0;
        let len = vector::length(&position_addrs);

        while (i < len) {
            let strategy_id = *vector::borrow(&strategy_ids, i);

            if (strategy_id == 1) {
                let position_addr = *vector::borrow(&position_addrs, i);
                let position = object::address_to_object<Info>(position_addr);

                let position_profit = get_pending_rewards_and_fees_usdc(position);
                total_profit = total_profit + position_profit;
            };

            i = i + 1;
        };

        total_profit
    }

    #[view]
    public fun get_pending_rewards_and_fees_usdc(position: Object<Info>): u64 {
        let stablecoin_metadata = object::address_to_object<Metadata>(USDC_ADDRESS);
        let total_stablecoin_amount: u64 = 0;

        // Get pool and fee information
        let (token_a, token_b, fee_tier) = get_pool_info(position);
        let pending_fees = get_pending_fees(position);
        let gas_fee_a = *vector::borrow(&pending_fees, 0);
        let gas_fee_b = *vector::borrow(&pending_fees, 1);

        // Get reward information
        let pending_rewards = get_pending_rewards(position);

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

    #[view]
    public fun get_tick(_position: Object<Info>): (I32, I32) {
        position_v3::get_tick(_position)
    }

    #[view]
    public fun get_liquidity(_position: Object<Info>): u128 {
        position_v3::get_liquidity(_position)
    }

    #[view]
    public fun get_amount_by_liquidity(_position: Object<Info>): (u64, u64) {
        router_v3::get_amount_by_liquidity(_position)
    }

    #[view]
    public fun get_pending_rewards(_position: Object<Info>): vector<rewarder::PendingReward> {
        pool_v3::get_pending_rewards(_position)
    }

    //public fun rewarder::pending_rewards_unpack(info: &PendingReward): (Object<Metadata>, u64)

    #[view]
    public fun get_pending_fees(_position: Object<Info>): vector<u64> { // returns amount_a, amount_b
        pool_v3::get_pending_fees(_position)
    }

    #[view]
    public fun get_pool_info(_position: Object<Info>):
        (Object<Metadata>, Object<Metadata>, u8) { // Returns (token_a, token_b, free_tier)
        position_v3::get_pool_info(_position)
    }

    #[view]
    public fun optimal_liquidity_amounts(
        _tick_lower_u32: u32,
        _tick_upper_u32: u32,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _amount_a_desired: u64,
        _amount_b_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64
    ): (u128, u64, u64) {
        router_v3::optimal_liquidity_amounts(
            _tick_lower_u32,
            _tick_upper_u32,
            _token_a,
            _token_b,
            _fee_tier,
            _amount_a_desired,
            _amount_b_desired,
            _amount_a_min,
            _amount_b_min
        )
    }

    #[view]
    public fun optimal_liquidity_amounts_from_a(
        _tick_lower_u32: u32,
        _tick_upper_u32: u32,
        _tick_current_u32: u32,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _amount_a_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64
    ): (u128, u64) {
        router_v3::optimal_liquidity_amounts_from_a(
            _tick_lower_u32,
            _tick_upper_u32,
            _tick_current_u32,
            _token_a,
            _token_b,
            _fee_tier,
            _amount_a_desired,
            _amount_a_min,
            _amount_b_min
        )
    }
}

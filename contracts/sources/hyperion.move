module moneyfi::hyperion {
    use std::signer;
    use std::vector;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::error;
    use aptos_framework::fungible_asset::Metadata;
    use dex_contract::i32::{Self, I32};
    use dex_contract::router_v3;
    use dex_contract::pool_v3;
    use dex_contract::rewarder;
    use dex_contract::position_v3::{Self, Info};

    use moneyfi::wallet_account;

    const DEADLINE_BUFFER: u64 = 31556926; // 1 years
    const USDC_ADDRESS: address = @stablecoin;

    const STRATEGY_ID: u8 = 1; // Hyperion strategy id

    //--Error
    const E_INVALID_TICK: u64 = 1;

    //const FEE_RATE_VEC: vector<u64> = vector[100, 500, 3000, 10000]; fee_tier is [0, 1, 2, 3] for [0.01%, 0.05%, 0.3%, 1%] ??
    //-- Entries
    public entry fun deposit_fund_to_hyperion_from_operator_single(
        operator: &signer,
        wallet_id: vector<u8>,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        amount_in: u64,
        slippage_numerator: u256,
        slippage_denominator: u256,
        threshold_numerator: u256,
        threshold_denominator: u256,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );

        let balance_before =
            primary_fungible_store::balance(signer::address_of(&wallet_signer), token_a);

        let position =
            pool_v3::open_position(
                &wallet_signer,
                token_b,
                token_a,
                fee_tier,
                tick_lower,
                tick_upper
            );

        router_v3::add_liquidity_single(
            &wallet_signer,
            position,
            token_a,
            token_b,
            amount_in - fee_amount,
            slippage_numerator,
            slippage_denominator,
            threshold_numerator,
            threshold_denominator
        );

        let balance_after =
            primary_fungible_store::balance(signer::address_of(&wallet_signer), token_a);

        wallet_account::add_position_opened(
            wallet_id,
            object::object_address<Info>(&position),
            vector::singleton<address>(object::object_address<Metadata>(&token_a)),
            vector::singleton<u64>(balance_before - balance_after - fee_amount),
            STRATEGY_ID,
            fee_amount
        );
    }

    public fun deposit_fund_to_hyperion_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        tick_lower: u32,
        tick_upper: u32,
        _amount_a_desired: u64,
        _amount_b_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64,
        _deadline: u64,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        let balance_a_before = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_a);
        let balance_b_before = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_b);
        let position =
            pool_v3::open_position(
                &wallet_signer,
                token_a,
                token_b,
                fee_tier,
                tick_lower,
                tick_upper
            );
        router_v3::add_liquidity(
            &wallet_signer,
            position,
            token_a,
            token_b,
            fee_tier,
            _amount_a_desired - fee_amount,
            _amount_b_desired,
            _amount_a_min - fee_amount,
            _amount_b_min,
            _deadline
        );

        let (_, amount_a, amount_b) =
            optimal_liquidity_amounts(
                tick_lower,
                tick_upper,
                token_a,
                token_b,
                fee_tier,
                _amount_a_desired - fee_amount,
                _amount_b_desired,
                _amount_a_min - fee_amount,
                _amount_b_min
            );

        let balance_a_after = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_a);
        let balance_b_after = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_b);
        let assets = vector::singleton<address>(
            object::object_address<Metadata>(&token_a)
        );
        vector::push_back(&mut assets, object::object_address<Metadata>(&token_b));

        let amounts = vector::singleton<u64>(balance_a_before - balance_a_after - fee_amount);
        vector::push_back(&mut amounts, balance_b_before - balance_b_after - fee_amount);

        wallet_account::add_position_opened(
            wallet_id,
            object::object_address<Info>(&position),
            assets,
            amounts,
            STRATEGY_ID,
            fee_amount
        );
    }

    public entry fun add_liquidity_from_operator_single(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        token_input: Object<Metadata>,
        token_pair: Object<Metadata>,
        amount_in: u64,
        slippage_numerator: u256,
        slippage_denominator: u256,
        threshold_numerator: u256,
        threshold_denominator: u256,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        let balance_before = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_input);
        
        router_v3::add_liquidity_single(
            &wallet_signer,
            position,
            token_input,
            token_pair,
            amount_in - fee_amount,
            slippage_numerator,
            slippage_denominator,
            threshold_numerator,
            threshold_denominator
        );
        let balance_after = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_input);
        
        let assets = vector::singleton<address>(
            object::object_address<Metadata>(&token_input)
        );
        let amounts = vector::singleton<u64>(balance_before - balance_after - fee_amount);

        wallet_account::upgrade_position_opened(
            wallet_id,
            object::object_address<Info>(&position),
            assets,
            amounts,
            fee_amount
        );
    }

    public entry fun add_liquidity_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        fee_tier: u8,
        amount_a_desired: u64,
        amount_b_desired: u64,
        amount_a_min: u64,
        amount_b_min: u64,
        deadline: u64,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        let balance_a_before = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_a);
        let balance_b_before = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_b);

        router_v3::add_liquidity(
            &wallet_signer,
            position,
            token_a,
            token_b,
            fee_tier,
            amount_a_desired - fee_amount,
            amount_b_desired,
            amount_a_min - fee_amount,
            amount_b_min,
            deadline
        );
    
        let (tick_lower, tick_upper) = position_v3::get_tick(position);
        let (_, amount_a, amount_b) =
            optimal_liquidity_amounts(
                i32::as_u32(tick_lower),
                i32::as_u32(tick_upper),
                token_a,
                token_b,
                fee_tier,
                amount_a_desired - fee_amount,
                amount_b_desired,
                amount_a_min - fee_amount,
                amount_b_min
            );
        let balance_a_after = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_a);
        let balance_b_after = primary_fungible_store::balance(signer::address_of(&wallet_signer), token_b);
        let assets = vector::singleton<address>(
            object::object_address<Metadata>(&token_a)
        );
        vector::push_back(&mut assets, object::object_address<Metadata>(&token_b));

        let amounts = vector::singleton<u64>(balance_a_before - balance_a_after - fee_amount);
        vector::push_back(&mut amounts, balance_b_before - balance_a_after);

        wallet_account::upgrade_position_opened(
            wallet_id,
            object::object_address<Info>(&position),
            assets,
            amounts,
            fee_amount
        );
    }

    public entry fun remove_liquidity_single_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        asset: Object<Metadata>,
        slippage_numerator: u256,
        slippage_denominator: u256,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        claim_fees_and_rewards_from_operator(operator, wallet_id, position, asset, 0);
        let liquidity = position_v3::get_liquidity(position);
        router_v3::remove_liquidity_single(
            &wallet_signer,
            position,
            liquidity,
            asset,
            slippage_numerator,
            slippage_denominator
        );
        
        wallet_account::remove_position_opened(
            wallet_id,
            object::object_address<Info>(&position),
            asset,
            fee_amount
        );
    }

    public entry fun remove_amount_liquidity_single_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        asset: Object<Metadata>,
        _lp_amount: u128,
        slippage_numerator: u256,
        slippage_denominator: u256,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        if(_lp_amount >= get_liquidity(position)) {
            remove_liquidity_single_from_operator(
                operator, wallet_id, position, asset, slippage_numerator, slippage_denominator, fee_amount
            );
        }else {
            // Get amount before removal
            let balance_before =
                primary_fungible_store::balance(signer::address_of(&wallet_signer), asset);

            let (assets, amounts) =
                wallet_account::get_amount_by_position(
                    wallet_id, object::object_address<Info>(&position)
                );
            let (_, index) = vector::index_of(
                &assets, &object::object_address<Metadata>(&asset)
            );
            let amounts_before = *vector::borrow(&amounts, index);

            claim_fees_and_rewards_from_operator(operator, wallet_id, position, asset, 0);

            router_v3::remove_liquidity_single(
                &wallet_signer,
                position,
                _lp_amount,
                asset,
                slippage_numerator,
                slippage_denominator
            );

            let balance_after =
                primary_fungible_store::balance(signer::address_of(&wallet_signer), asset);

            let withdrawn_amount = balance_after - balance_before;
            let withdrawn_assets = vector::singleton<address>(
                object::object_address<Metadata>(&asset)
            );
            let withdrawn_amounts = vector::singleton<u64>(withdrawn_amount);
            let amounts_after = vector::singleton<u64>(amounts_before - withdrawn_amount);
            
            wallet_account::update_position_after_partial_removal(
                wallet_id,
                object::object_address<Info>(&position),
                withdrawn_assets,
                withdrawn_amounts,
                amounts_after,
                fee_amount
            );
        };
    }

    public entry fun claim_fees_and_rewards_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        asset: Object<Metadata>,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        let wallet_address = signer::address_of(&wallet_signer);

        // Get balance before claiming
        let balance_before = primary_fungible_store::balance(wallet_address, asset);

        // Get pool and fee information (still needed for swapping)
        let (token_a, token_b, fee_tier) = get_pool_info(position);
        let pending_fees = get_pending_fees(position);
        let fee_amount_a = *vector::borrow(&pending_fees, 0);
        let fee_amount_b = *vector::borrow(&pending_fees, 1);

        // Get reward information
        let pending_rewards = get_pending_rewards(position);

        // Claim fees and rewards for single position
        let position_addresses = vector::empty<address>();
        vector::push_back(
            &mut position_addresses, object::object_address<Info>(&position)
        );

        router_v3::claim_fees_and_rewards_directly_deposit(
            &wallet_signer, position_addresses
        );

        // Swap token_a to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&token_a)
            != object::object_address<Metadata>(&asset)) {
            if (fee_amount_a > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    fee_tier,
                    fee_amount_a,
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
            if (fee_amount_b > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    fee_tier,
                    fee_amount_b,
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
        let total_stablecoin_amount = balance_after - balance_before;

        wallet_account::add_profit_unclaimed(
            wallet_id,
            object::object_address<Info>(&position),
            object::object_address<Metadata>(&asset),
            total_stablecoin_amount,
            fee_amount
        );
    }

    public entry fun update_tick(
        operator: &signer, 
        wallet_id: vector<u8>, 
        position: Object<Info>,
        asset: Object<Metadata>, 
        tick_lower: u32, 
        tick_upper: u32,
        fee_amount: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(
            operator, wallet_id
        );
        let wallet_address = signer::address_of(&wallet_signer);
        let (token_a, token_b, fee_tier) = get_pool_info(position);
        let (tick_lower_before, tick_upper_before) = position_v3::get_tick(position);

        let token_pair = if(object::object_address(&asset) != object::object_address(&token_a)){
            token_a
        }else{
            token_b
        };
        
        if(i32::as_u32(tick_lower_before) == tick_lower && i32::as_u32(tick_upper_before) == tick_upper){
            return
        }else{
            let balance_before = primary_fungible_store::balance(wallet_address, asset);
            remove_liquidity_single_from_operator(
                operator, 
                wallet_id, 
                position,
                asset, 
                99, 
                100, 
                0
            );
            let balance_after = primary_fungible_store::balance(wallet_address, asset);
            deposit_fund_to_hyperion_from_operator_single(
                operator,
                wallet_id,
                asset,
                token_pair,
                fee_tier,
                tick_lower,
                tick_upper,
                balance_after - balance_before - fee_amount,
                99,
                100,
                1,
                1,
                fee_amount
            );
        }
    }

    //-- Views
    #[view]
    public fun get_profit(wallet_id: vector<u8>): u64 {
        let (position_addrs, strategy_ids) = wallet_account::get_position_opened(wallet_id);
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
        let fee_amount_a = *vector::borrow(&pending_fees, 0);
        let fee_amount_b = *vector::borrow(&pending_fees, 1);

        // Get reward information
        let pending_rewards = get_pending_rewards(position);

        // Convert fees to stablecoin
        if (fee_amount_a > 0
            && object::object_address<Metadata>(&token_a)
                != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_a_to_stable =
                pool_v3::liquidity_pool(token_a, stablecoin_metadata, fee_tier);
            let (amount_out_a, _) =
                pool_v3::get_amount_out(pool_a_to_stable, token_a, fee_amount_a);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_a;
        } else if (fee_amount_a > 0
            && object::object_address<Metadata>(&token_a)
                == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + fee_amount_a;
        };

        if (fee_amount_b > 0
            && object::object_address<Metadata>(&token_b)
                != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_b_to_stable =
                pool_v3::liquidity_pool(token_b, stablecoin_metadata, fee_tier);
            let (amount_out_b, _) =
                pool_v3::get_amount_out(pool_b_to_stable, token_b, fee_amount_b);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_b;
        } else if (fee_amount_b > 0
            && object::object_address<Metadata>(&token_b)
                == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + fee_amount_b;
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

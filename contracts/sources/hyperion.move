module moneyfi::hyperion {
    use std::signer;
    use std::vector;
    use std::error;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset::Metadata;
    use dex_contract::i32::{Self, I32};
    use dex_contract::router_v3;
    use dex_contract::pool_v3;
    use dex_contract::rewarder;
    use dex_contract::position_v3::{Self, Info};

    use moneyfi::access_control;
    use moneyfi::wallet_account;

    const DEADLINE_BUFFER: u64 = 31556926 ; // 1 years

    const STRATEGY_ID: u8 = 1; // Hyperion strategy id

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
        amount_out_min: u256,
        amount_out_max: u256,
        slippage_numerator: u256,
        slippage_denominator: u256,
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(operator,wallet_id);
        let position = pool_v3::open_position(
              &wallet_signer,
              token_a,
              token_b,
              fee_tier,
              tick_lower,
              tick_upper
        );

        router_v3::add_liquidity_single(
            &wallet_signer,
            position,
            token_a,
            token_b,
            amount_in,
            amount_out_min,
            amount_out_max,
            slippage_numerator,
            slippage_denominator
        );

        let server_signer = access_control::get_object_data_signer();
        wallet_account::add_position_opened(
            &server_signer,
            wallet_id,
            object::object_address<Info>(&position),
            vector::singleton<address>(object::object_address<Metadata>(&token_a)),
            vector::singleton<u64>(amount_in),
            STRATEGY_ID,
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
        _deadline: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(operator,wallet_id);
        let position = pool_v3::open_position(
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
            _amount_a_desired,
            _amount_b_desired,
            _amount_a_min,
            _amount_b_min,
            _deadline
        );

        let server_signer = access_control::get_object_data_signer();
        let (_, amount_a, amount_b) = optimal_liquidity_amounts(
            tick_lower,
            tick_upper,
            token_a,
            token_b,
            fee_tier,
            _amount_a_desired,
            _amount_b_desired,
            _amount_a_min,
            _amount_b_min
        );

        let assets = vector::singleton<address>(object::object_address<Metadata>(&token_a));
        vector::push_back(&mut assets, object::object_address<Metadata>(&token_b));
        
        let amounts = vector::singleton<u64>(amount_a);
        vector::push_back(&mut amounts, amount_b);

        wallet_account::add_position_opened(
            &server_signer,
            wallet_id,
            object::object_address<Info>(&position),
            assets,
            amounts,
            STRATEGY_ID,
        );
    }

    public entry fun add_liquidity_from_operator_single(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        token_input: Object<Metadata>,
        token_pair: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u256,
        amount_out_max: u256,
        slippage_numerator: u256,
        slippage_denominator: u256
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(operator, wallet_id);
        
        router_v3::add_liquidity_single(
            &wallet_signer,
            position,
            token_input,
            token_pair,
            amount_in,
            amount_out_min,
            amount_out_max,
            slippage_numerator,
            slippage_denominator
        );
        
        let server_signer = access_control::get_object_data_signer();
        
        let assets = vector::singleton<address>(object::object_address<Metadata>(&token_input));
        let amounts = vector::singleton<u64>(amount_in);

        wallet_account::upgrade_position_opened(
            &server_signer,
            wallet_id,
            object::object_address<Info>(&position),
            assets,
            amounts,
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
        deadline: u64
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(operator, wallet_id);
        
        router_v3::add_liquidity(
            &wallet_signer,
            position,
            token_a,
            token_b,
            fee_tier,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min,
            deadline
        );
        let server_signer = access_control::get_object_data_signer();

        let (tick_lower, tick_upper) = position_v3::get_tick(position);
        let (_, amount_a, amount_b) = optimal_liquidity_amounts(
            i32::as_u32(tick_lower),
            i32::as_u32(tick_upper),
            token_a,
            token_b,
            fee_tier,
            amount_a_desired,
            amount_b_desired,
            amount_a_min,
            amount_b_min
        );

        let assets = vector::singleton<address>(object::object_address<Metadata>(&token_a));
        vector::push_back(&mut assets, object::object_address<Metadata>(&token_b));
        
        let amounts = vector::singleton<u64>(amount_a);
        vector::push_back(&mut amounts, amount_b);

        wallet_account::upgrade_position_opened(
            &server_signer,
            wallet_id,
            object::object_address<Info>(&position),
            assets,
            amounts,
            );
    }

    public entry fun remove_liquidity_single_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>,
        asset: Object<Metadata>,
        slippage_numerator: u256,
        slippage_denominator: u256
        ) {
            let wallet_signer = wallet_account::get_wallet_account_signer(operator, wallet_id);
            claim_fees_and_rewards_from_operator(
                &wallet_signer,
                wallet_id,
                position
            );
            let liquidity = position_v3::get_liquidity(position);
            router_v3::remove_liquidity_single(
                &wallet_signer,
                position,
                liquidity,
                asset,
                slippage_numerator,
                slippage_denominator,
            );
            let server_signer = access_control::get_object_data_signer();
            wallet_account::remove_position_opened(
                &server_signer,
                wallet_id,
                object::object_address<Info>(&position)
            );
        }

    public entry fun claim_fees_and_rewards_from_operator(
        operator: &signer,
        wallet_id: vector<u8>,
        position: Object<Info>
    ) {
        let wallet_signer = wallet_account::get_wallet_account_signer(operator, wallet_id);
        
        let stablecoin_metadata = access_control::get_stablecoin_metadata();
        let total_stablecoin_amount : u64 = 0;
        
        // Get pool and fee information
        let (token_a, token_b, fee_tier) = get_pool_info(position);
        let pending_fees = get_pending_fees(position);
        let fee_amount_a = *vector::borrow(&pending_fees, 0);
        let fee_amount_b = *vector::borrow(&pending_fees, 1);
        
        // Get reward information
        let pending_rewards = get_pending_rewards(position);
        
        // Convert fees to stablecoin
        if (fee_amount_a > 0 && object::object_address<Metadata>(&token_a) != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_a_to_stable = pool_v3::liquidity_pool(token_a, stablecoin_metadata, fee_tier);
            let (amount_out_a, _) = pool_v3::get_amount_out(pool_a_to_stable, token_a, fee_amount_a);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_a;
        } else if (fee_amount_a > 0 && object::object_address<Metadata>(&token_a) == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + fee_amount_a;
        };
        
        if (fee_amount_b > 0 && object::object_address<Metadata>(&token_b) != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_b_to_stable = pool_v3::liquidity_pool(token_b, stablecoin_metadata, fee_tier);
            let (amount_out_b, _) = pool_v3::get_amount_out(pool_b_to_stable, token_b, fee_amount_b);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_b;
        } else if (fee_amount_b > 0 && object::object_address<Metadata>(&token_b) == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + fee_amount_b;
        };
        
        // Convert rewards to stablecoin
        let j = 0;
        let rewards_len = vector::length(&pending_rewards);
        let amount_reward_to_stable : u64 = 0;
        while (j < rewards_len) {
            let reward = vector::borrow(&pending_rewards, j);
            let (reward_token, reward_amount) = rewarder::pending_rewards_unpack(reward);
            
            if (reward_amount > 0 && object::object_address<Metadata>(&reward_token) != object::object_address<Metadata>(&stablecoin_metadata)) {
                let pool_reward_to_stable = pool_v3::liquidity_pool(reward_token, stablecoin_metadata, 1);
                let (amount_out_reward, _) = pool_v3::get_amount_out(pool_reward_to_stable, reward_token, reward_amount);
                total_stablecoin_amount = total_stablecoin_amount + amount_out_reward;
                amount_reward_to_stable = amount_out_reward;
            } else if (reward_amount > 0 && object::object_address<Metadata>(&reward_token) == object::object_address<Metadata>(&stablecoin_metadata)) {
                total_stablecoin_amount = total_stablecoin_amount + reward_amount;
            };
            
            j = j + 1;
        };
        
        // Claim fees and rewards for single position
        let position_addresses = vector::empty<address>();
        vector::push_back(&mut position_addresses, object::object_address<Info>(&position));
        
        router_v3::claim_fees_and_rewards_directly_deposit(
            &wallet_signer,
            position_addresses,
        );
        
        // Swap token_a to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&token_a) != object::object_address<Metadata>(&stablecoin_metadata)) {
            if (fee_amount_a > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    fee_tier,
                    fee_amount_a,
                    99,
                    0, // sqrt_price_limit = 0 for no limit
                    token_a,
                    stablecoin_metadata,
                    signer::address_of(&wallet_signer),
                    timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                );
            };
        };
        
        // Swap token_b to stablecoin if not already stablecoin
        if (object::object_address<Metadata>(&token_b) != object::object_address<Metadata>(&stablecoin_metadata)) {
            if (fee_amount_b > 0) {
                router_v3::exact_input_swap_entry(
                    &wallet_signer,
                    fee_tier,
                    fee_amount_b,
                    99,
                    0, // sqrt_price_limit = 0 for no limit
                    token_b,
                    stablecoin_metadata,
                    signer::address_of(&wallet_signer),
                    timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                );
            };
        };
        
        // Swap reward tokens to stablecoin
        let p = 0;
        let rewards_len = vector::length(&pending_rewards);
        while (p < rewards_len) {
            let reward = vector::borrow(&pending_rewards, p);
            let (reward_token, _) = rewarder::pending_rewards_unpack(reward);
            
            if (object::object_address<Metadata>(&reward_token) != object::object_address<Metadata>(&stablecoin_metadata)) {
                if (amount_reward_to_stable > 0) {
                    router_v3::exact_input_swap_entry(
                        &wallet_signer,
                        fee_tier,
                        amount_reward_to_stable,
                        99,
                        0, // sqrt_price_limit = 0 for no limit
                        reward_token,
                        stablecoin_metadata,
                        signer::address_of(&wallet_signer),
                        timestamp::now_seconds() + DEADLINE_BUFFER // deadline
                    );
                };
            };
            
            p = p + 1;
        };

        let server_signer = access_control::get_object_data_signer();
        wallet_account::add_profit_unclaimed(
            &server_signer,
            wallet_id,
            object::object_address<Info>(&position),
            object::object_address<Metadata>(&stablecoin_metadata),
            total_stablecoin_amount
        );
    }


    //-- Views
    #[view]
    public fun get_pending_rewards_and_fees_usdc(
        position: Object<Info>
    ): u64 {
        let stablecoin_metadata = access_control::get_stablecoin_metadata();
        let total_stablecoin_amount : u64 = 0;
        
        // Get pool and fee information
        let (token_a, token_b, fee_tier) = get_pool_info(position);
        let pending_fees = get_pending_fees(position);
        let fee_amount_a = *vector::borrow(&pending_fees, 0);
        let fee_amount_b = *vector::borrow(&pending_fees, 1);
        
        // Get reward information
        let pending_rewards = get_pending_rewards(position);
        
        // Convert fees to stablecoin
        if (fee_amount_a > 0 && object::object_address<Metadata>(&token_a) != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_a_to_stable = pool_v3::liquidity_pool(token_a, stablecoin_metadata, fee_tier);
            let (amount_out_a, _) = pool_v3::get_amount_out(pool_a_to_stable, token_a, fee_amount_a);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_a;
        } else if (fee_amount_a > 0 && object::object_address<Metadata>(&token_a) == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + fee_amount_a;
        };
        
        if (fee_amount_b > 0 && object::object_address<Metadata>(&token_b) != object::object_address<Metadata>(&stablecoin_metadata)) {
            let pool_b_to_stable = pool_v3::liquidity_pool(token_b, stablecoin_metadata, fee_tier);
            let (amount_out_b, _) = pool_v3::get_amount_out(pool_b_to_stable, token_b, fee_amount_b);
            total_stablecoin_amount = total_stablecoin_amount + amount_out_b;
        } else if (fee_amount_b > 0 && object::object_address<Metadata>(&token_b) == object::object_address<Metadata>(&stablecoin_metadata)) {
            total_stablecoin_amount = total_stablecoin_amount + fee_amount_b;
        };
        
        // Convert rewards to stablecoin
        let j = 0;
        let rewards_len = vector::length(&pending_rewards);
        while (j < rewards_len) {
            let reward = vector::borrow(&pending_rewards, j);
            let (reward_token, reward_amount) = rewarder::pending_rewards_unpack(reward);
            
            if (reward_amount > 0 && object::object_address<Metadata>(&reward_token) != object::object_address<Metadata>(&stablecoin_metadata)) {
                let pool_reward_to_stable = pool_v3::liquidity_pool(reward_token, stablecoin_metadata, 1);
                let (amount_out_reward, _) = pool_v3::get_amount_out(pool_reward_to_stable, reward_token, reward_amount);
                total_stablecoin_amount = total_stablecoin_amount + amount_out_reward;
            } else if (reward_amount > 0 && object::object_address<Metadata>(&reward_token) == object::object_address<Metadata>(&stablecoin_metadata)) {
                total_stablecoin_amount = total_stablecoin_amount + reward_amount;
            };
            
            j = j + 1;
        };
        total_stablecoin_amount
    }
        
    #[view]
    public fun get_tick(
        _position: Object<Info>
    ): (I32, I32) {
        position_v3::get_tick(_position)
    }

    #[view]
     public fun get_liquidity(
        _position: Object<Info>
    ): u128 {
        position_v3::get_liquidity(_position)
    }

     #[view]
    public fun get_amount_by_liquidity(_position: Object<Info>): (u64, u64) {
        router_v3::get_amount_by_liquidity(_position)
    }

    #[view]
    public fun get_pending_rewards(
        _position: Object<Info>
    ): vector<rewarder::PendingReward> {
        pool_v3::get_pending_rewards(_position)
    }
    //public fun rewarder::pending_rewards_unpack(info: &PendingReward): (Object<Metadata>, u64)

    #[view]
    public fun get_pending_fees(_position: Object<Info>): vector<u64> { // returns amount_a, amount_b
        pool_v3::get_pending_fees(_position)
    }

    #[view]
    public fun get_pool_info(
        _position: Object<Info>
    ):(Object<Metadata>, Object<Metadata>, u8) { // Returns (token_a, token_b, free_tier)
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
        _amount_b_min: u64,
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
        _amount_b_min: u64,
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

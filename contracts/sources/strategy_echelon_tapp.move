module moneyfi::strategy_echelon_tapp {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::bcs::to_bytes;
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
    use moneyfi::strategy_echelon;

    const ZERO_ADDRESS: address =
        @0x0000000000000000000000000000000000000000000000000000000000000000;

    const MINIMUM_LIQUIDITY: u128 = 1_000_000_000;

    const APT_FA_ADDRESS: address = @0xa;
    //Error
    /// Position not exists
    const E_TAPP_POSITION_NOT_EXISTS: u64 = 1;
    /// Invalid asset
    const E_INVALID_ASSET: u64 = 2;
    const E_POOL_NOT_EXIST: u64 = 3;

    struct TappData has key {
        pools: OrderedMap<address, Position> // pool address -> Position
    }

    struct Position has copy, drop, store {
        position: address, // position address
        lp_amount: u128, // Liquidity pool amount
        asset: Object<Metadata>,
        pair: Object<Metadata>,
        amount: u64
    }

    fun deposit_to_tapp_impl(
        caller: &signer,
        asset: &Object<Metadata>,
        pool: address,
        amount_in: u64
    ): u64 acquires TappData {
        let position = create_or_get_exist_position(caller, asset, pool);
        let caller_address = signer::address_of(caller);
        let amount_pair_in = math128::mul_div(amount_in as u128, 1, 1000) as u64;
        let balance_asset_before_swap =
            primary_fungible_store::balance<Metadata>(caller_address, position.asset);
        let balance_pair_before_swap =
            primary_fungible_store::balance<Metadata>(caller_address, position.pair);

        swap_with_hyperion(
            caller,
            &position.pair,
            &position.asset,
            amount_pair_in,
            false
        );

        let actual_amount_asset_swap =
            balance_asset_before_swap
                - primary_fungible_store::balance<Metadata>(
                    caller_address, position.asset
                );
        let actual_amount_pair =
            primary_fungible_store::balance<Metadata>(caller_address, position.pair)
                - balance_pair_before_swap;

        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let token_a = *vector::borrow(&assets, 0);
        let token_b = *vector::borrow(&assets, 1);

        // Determine which token we're depositing and create amounts vector
        let amounts = vector::empty<u256>();

        if (object::object_address(asset) == token_a) {
            // Depositing token A (first token)
            vector::push_back(
                &mut amounts, (amount_in - actual_amount_asset_swap) as u256
            );
            vector::push_back(&mut amounts, actual_amount_pair as u256);
        } else if (object::object_address(asset) == token_b) {
            // Depositing token B (second token)
            vector::push_back(&mut amounts, actual_amount_pair as u256);
            vector::push_back(
                &mut amounts, (amount_in - actual_amount_asset_swap) as u256
            );
        } else {
            // Asset is not part of this pool
            assert!(false, error::invalid_argument(E_INVALID_ASSET));
        };
        // serialize data to bytes
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
        // Call integration to add liquidity
        let (position_idx, position_addr) = integration::add_liquidity(caller, payload);

        let actual_amount =
            balance_asset_before_swap
                - primary_fungible_store::balance<Metadata>(
                    caller_address, position.asset
                );

        // Update position data
        position.position = position_addr;
        position.lp_amount = stable_views::position_shares(pool, position_idx) as u128;
        position.amount = position.amount + actual_amount;
        set_position_data(caller, pool, position);
        actual_amount
    }

    // Return deposited_amount, withdrawn_amount
    fun withdraw_from_tapp_impl(
        caller: &signer,
        asset: &Object<Metadata>,
        pool: address,
        amount_min: u64
    ): (u64, u64) acquires TappData {
        let position = get_position_data(caller, pool);
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
                position.asset // to satisfy the type checker
            };
        let balance_asset_before = primary_fungible_store::balance(
            caller_address, *asset
        );
        let balance_pair_before = primary_fungible_store::balance(caller_address, pair);
        let (active_rewards, _) = get_active_rewards(pool, &position);
        // Serialize data to bytes
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
        // Call integration to remove liquidity
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
                remove_position(caller, pool);
                amount
            } else {
                position.amount = position.amount - amount_min;
                position.lp_amount = position.lp_amount - (liquidity_remove as u128);
                set_position_data(caller, pool, position);
                amount_min
            };
        (total_deposited_amount, total_withdrawn_amount)
    }

    // Return reward_amounts to asset
    fun claim_tapp_reward(caller: &signer, pool: address): u64 acquires TappData {
        let tapp_data = ensure_tapp_data(caller);
        if (!exists_tapp_position(tapp_data, pool)) {
            return 0
        };
        let position = get_position_data(caller, pool);
        let caller_addr = signer::address_of(caller);
        if (position.position == ZERO_ADDRESS) {
            return 0
        };
        // Calculate minimal liquidity to keep
        let minimal_liquidity =
            math128::min(
                MINIMUM_LIQUIDITY, math128::ceil_div(position.lp_amount, 10000)
            ); // Keep 0.01% or minimum
        let liquidity_to_remove = (position.lp_amount - minimal_liquidity) as u256;
        if (liquidity_to_remove == 0) {
            return 0 // Not enough liquidity to claim meaningful rewards
        };
        let (active_rewards, _) = get_active_rewards(pool, &position);
        if (active_rewards.is_empty()) {
            return 0
        };
        let assets = hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
        let token_a = object::address_to_object<Metadata>(*vector::borrow(&assets, 0));
        let token_b = object::address_to_object<Metadata>(*vector::borrow(&assets, 1));
        let balance_a_before_remove =
            primary_fungible_store::balance(caller_addr, token_a);
        let balance_b_before_remove =
            primary_fungible_store::balance(caller_addr, token_b);
        // Serialize data to bytes
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
        // Call integration to remove liquidity
        router::remove_liquidity(caller, payload);
        let amount_a =
            primary_fungible_store::balance(caller_addr, token_a)
                - balance_a_before_remove;
        let amount_b =
            primary_fungible_store::balance(caller_addr, token_b)
                - balance_b_before_remove;

        // Determine which token we're depositing and create amounts vector
        let amounts = vector::empty<u256>();
        vector::push_back(&mut amounts, (amount_a as u256));
        vector::push_back(&mut amounts, (amount_b as u256));
        // serialize data to bytes
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
        // Call integration to add liquidity
        let (position_idx, position_addr) = integration::add_liquidity(caller, payload);
        assert!(position.position == position_addr);
        let balance_before = primary_fungible_store::balance(
            caller_addr, position.asset
        );
        //Swap all reward tokens to asset
        vector::for_each(
            active_rewards,
            |reward_token_addr| {
                if (reward_token_addr != object::object_address(&position.asset)) {
                    let reward_balance =
                        primary_fungible_store::balance(
                            caller_addr,
                            object::address_to_object<Metadata>(reward_token_addr)
                        );

                    if (reward_balance > 0) {
                        swap_with_hyperion(
                            caller,
                            &object::address_to_object<Metadata>(reward_token_addr),
                            &position.asset,
                            reward_balance,
                            false
                        );
                    };
                };
            }
        );
        position.lp_amount = stable_views::position_shares(pool, position_idx) as u128;
        set_position_data(caller, pool, position);
        (primary_fungible_store::balance(caller_addr, position.asset) - balance_before)
    }

    fun create_or_get_exist_position(
        caller: &signer, asset: &Object<Metadata>, pool: address
    ): Position acquires TappData {
        let tapp_data = ensure_tapp_data(caller);
        let position =
            if (exists_tapp_position(tapp_data, pool)) {
                let position = ordered_map::borrow(&tapp_data.pools, &pool);
                *position
            } else {
                let assets =
                    hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
                let token_a = *vector::borrow(&assets, 0);
                let token_b = *vector::borrow(&assets, 1);
                let pair =
                    if (token_a == object::object_address(asset)) {
                        token_b
                    } else {
                        token_a
                    };
                let new_position = Position {
                    position: ZERO_ADDRESS,
                    lp_amount: 0,
                    asset: *asset,
                    pair: object::address_to_object<Metadata>(pair),
                    amount: 0
                };
                new_position
            };
        position
    }

    fun get_position_data(caller: &signer, pool: address): Position acquires TappData {
        let tapp_data = ensure_tapp_data(caller);
        assert!(
            exists_tapp_position(tapp_data, pool),
            error::not_found(E_TAPP_POSITION_NOT_EXISTS)
        );
        let position = ordered_map::borrow(&tapp_data.pools, &pool);
        *position
    }

    inline fun ensure_tapp_data(caller: &signer): &TappData acquires TappData {
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

    fun exists_tapp_position(tapp_data: &TappData, pool: address): bool {
        ordered_map::contains(&tapp_data.pools, &pool)
    }

    fun set_position_data(
        caller: &signer, pool: address, position: Position
    ) acquires TappData {
        let caller_address = signer::address_of(caller);
        let tapp_data = borrow_global_mut<TappData>(caller_address);
        ordered_map::upsert(&mut tapp_data.pools, pool, position);
    }

    fun remove_position(caller: &signer, pool: address) acquires TappData {
        let caller_address = signer::address_of(caller);
        let tapp_data = borrow_global_mut<TappData>(caller_address);
        ordered_map::remove(&mut tapp_data.pools, &pool);
    }

    // return (active_reward, active_reward_amount)
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
        let caller_addr = signer::address_of(caller);

        let (pool, fee_tier, slippage) = get_hyperion_pool(from, to);
        let (amount_in, amount_out) =
            if (exact_out) {
                let (amount_in, _) = hyperion::pool_v3::get_amount_in(
                    pool, *from, amount
                );
                amount_in = math64::mul_div(amount_in, (10000 + slippage), 10000);
                (amount_in, amount)
            } else {
                let (amount_out, _) =
                    hyperion::pool_v3::get_amount_out(pool, *from, amount);
                amount_out = math64::mul_div(amount_out, (10000 - slippage), 10000);
                (amount, amount_out)
            };

        // ignore price impact
        let sqrt_price_limit =
            if (hyperion::utils::is_sorted(*from, *to)) {
                04295048016 // min sqrt price
            } else {
                79226673515401279992447579055 // max sqrt price
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
}

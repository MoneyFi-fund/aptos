module moneyfi::strategy_echelon_tapp {
    use std::signer;
    use std::vector;
    use std::string::String;
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

    use moneyfi::strategy_echelon;

    const ZERO_ADDRESS: address =
        @0x0000000000000000000000000000000000000000000000000000000000000000;

    const MINIMUM_LIQUIDITY: u128 = 1_000_000_000;
    const U64_MAX: u64 = 18446744073709551615;

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

    struct PoolAmountPair has copy, drop, store {
        pool_address: address,
        amount: u64
    }

    public entry fun deposit(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64
    ) {
        strategy_echelon::deposit(sender, vault_name, wallet_id, amount);
    }

    public entry fun withdraw(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64,
        gas_fee: u64,
        hook_data: vector<u8>
    ) acquires TappData {
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = get_vault_tapp_data(vault_addr);
        let total_borrow_amount = strategy_echelon::vault_borrow_amount(vault_name);

        // Claim TAPP rewards if vault has TAPP positions and borrows
        if (!tapp_data.is_empty() && total_borrow_amount > 0) {
            let withdraw_amount =
                strategy_echelon::estimate_repay_amount_from_account_withdraw_amount(
                    vault_name, wallet_id, amount
                );

            // If we need to repay some borrowed amount, try to get funds from TAPP first
            if (withdraw_amount > 0) {
                let claimed_total = 0;

                // Claim rewards from all TAPP positions
                tapp_data.for_each_ref(
                    |pool, _| {
                        let reward_amount =
                            claim_tapp_reward(
                                &vault_signer,
                                strategy_echelon::vault_asset(vault_name),
                                *pool
                            );
                        if (reward_amount > 0) {
                            claimed_total = claimed_total + reward_amount;
                        }
                    }
                );

                // Compound claimed rewards
                if (claimed_total > 0) {
                    strategy_echelon::compound_rewards(vault_name, claimed_total);
                };

                // Handle TAPP withdrawal with proper sorting and logic
                handle_tapp_withdrawal(
                    &vault_signer,
                    &vault_name,
                    &tapp_data,
                    withdraw_amount,
                    total_borrow_amount
                );
            } else {
                // Even if no repayment needed, still claim rewards for compounding
                tapp_data.for_each_ref(
                    |pool, _| {
                        let reward_amount =
                            claim_tapp_reward(
                                &vault_signer,
                                strategy_echelon::vault_asset(vault_name),
                                *pool
                            );
                        if (reward_amount > 0) {
                            strategy_echelon::compound_rewards(vault_name, reward_amount);
                        };
                    }
                );
            };
        };

        // Proceed with the actual withdrawal from the main strategy
        strategy_echelon::withdraw(
            sender,
            vault_name,
            wallet_id,
            amount,
            gas_fee,
            hook_data
        );
    }

    public entry fun vault_deposit_echelon(
        sender: &signer, vault_name: String, amount: u64
    ) acquires TappData {
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = get_vault_tapp_data(vault_addr);
        if (!tapp_data.is_empty()) {
            tapp_data.for_each_ref(
                |pool, _| {
                    let reward_amount =
                        claim_tapp_reward(
                            &vault_signer, strategy_echelon::vault_asset(vault_name), *pool
                        );
                    if (reward_amount > 0) {
                        strategy_echelon::compound_rewards(vault_name, reward_amount);
                    }
                }
            )
        };
        strategy_echelon::vault_deposit_echelon(sender, vault_name, amount);
    }

    public entry fun borrow_and_deposit_to_tapp(
        sender: &signer,
        vault_name: String,
        pool: address,
        amount: u64
    ) acquires TappData {
        let borrowable_amount = strategy_echelon::max_borrowable_amount(vault_name);
        if (borrowable_amount == 0) {
            return;
        };
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = get_vault_tapp_data(vault_addr);
        if (!tapp_data.is_empty()) {
            tapp_data.for_each_ref(
                |pool, _| {
                    let reward_amount =
                        claim_tapp_reward(
                            &vault_signer, strategy_echelon::vault_asset(vault_name), *pool
                        );
                    if (reward_amount > 0) {
                        strategy_echelon::compound_rewards(vault_name, reward_amount);
                    }
                }
            )
        };
        let borrowed_amount = strategy_echelon::borrow(sender, vault_name, amount);
        if (borrowed_amount > 0) {
            let asset = strategy_echelon::vault_borrow_asset(vault_name);
            deposit_to_tapp_impl(&vault_signer, &asset, pool, borrowed_amount);
        };
    }

    public entry fun withdraw_from_tapp_and_repay(
        sender: &signer,
        vault_name: String,
        pool: address,
        min_amount: u64
    ) acquires TappData {
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = get_vault_tapp_data(vault_addr);
        if (!tapp_data.is_empty()) {
            tapp_data.for_each_ref(
                |pool, _| {
                    let reward_amount =
                        claim_tapp_reward(
                            &vault_signer, strategy_echelon::vault_asset(vault_name), *pool
                        );
                    if (reward_amount > 0) {
                        strategy_echelon::compound_rewards(vault_name, reward_amount);
                    }
                }
            )
        } else {
            assert!(false, error::invalid_argument(E_POOL_NOT_EXIST));
        };
        let total_borrow_amount = strategy_echelon::vault_borrow_amount(vault_name);
        let (_, total_withdrawn_amount) =
            withdraw_from_tapp_impl(
                &vault_signer,
                &strategy_echelon::vault_borrow_asset(vault_name),
                pool,
                min_amount
            );

        let repay_amount =
            if (min_amount >= total_borrow_amount) {
                U64_MAX
            } else {
                total_withdrawn_amount
            };
        if (total_withdrawn_amount > 0) {
            let repaid_amount = strategy_echelon::repay(sender, vault_name, repay_amount);
            if (repaid_amount < total_withdrawn_amount) {
                let profit = total_withdrawn_amount - repaid_amount;
                let (amount_out, _) =
                    swap_with_hyperion(
                        &vault_signer,
                        &strategy_echelon::vault_borrow_asset(vault_name),
                        &strategy_echelon::vault_asset(vault_name),
                        profit,
                        false
                    );
                strategy_echelon::compound_rewards(vault_name, amount_out);
            };
        };
    }

    // Returns (pending_amount, deposited_amount, estimate_withdrawable_amount)
    #[view]
    public fun get_account_state(
        vault_name: String, wallet_id: vector<u8>
    ): (u64, u64, u64) acquires TappData {
        let (
            pending_amount,
            deposited_amount,
            estimate_withdrawable_amount,
            user_shares,
            total_shares
        ) = strategy_echelon::get_account_state(vault_name, wallet_id);
        if (exists<TappData>(strategy_echelon::vault_address(vault_name))) {
            let asset = strategy_echelon::vault_asset(vault_name);
            let borrow_asset = strategy_echelon::vault_borrow_asset(vault_name);
            let borrow_amount = strategy_echelon::vault_borrow_amount(vault_name);
            let total_tapp_amount =
                get_estimate_withdrawable_amount_to_asset(vault_name, &borrow_asset);
            let (interest_amount, loss_amount) =
                if (total_tapp_amount > borrow_amount) {
                    let profit = total_tapp_amount - borrow_amount;
                    let amount_out = get_amount_out(&borrow_asset, &asset, profit);
                    (amount_out, 0)
                } else {
                    let loss = borrow_amount - total_tapp_amount;
                    let amount_out = get_amount_out(&borrow_asset, &asset, loss);
                    (0, amount_out)
                };
            let (user_interest, user_loss) =
                if (total_shares > 0 && user_shares > 0) {
                    (
                        math128::ceil_div(
                            (interest_amount as u128) * (user_shares as u128),
                            (total_shares as u128)
                        ) as u64,
                        math128::ceil_div(
                            (loss_amount as u128) * (user_shares as u128),
                            (total_shares as u128)
                        ) as u64
                    )
                } else { (0, 0) };
            estimate_withdrawable_amount =
                estimate_withdrawable_amount + user_interest - user_loss
        };
        (pending_amount, deposited_amount, estimate_withdrawable_amount)

    }

    fun get_vault_tapp_data(vault_addr: address): OrderedMap<address, Position> acquires TappData {
        if (!exists<TappData>(vault_addr)) {
            return ordered_map::new<address, Position>()
        };
        let tapp_data = borrow_global<TappData>(vault_addr);
        tapp_data.pools
    }

    fun deposit_to_tapp_impl(
        caller: &signer,
        asset: &Object<Metadata>,
        pool: address,
        amount_in: u64
    ): u64 acquires TappData {
        let position = create_or_get_exist_position(caller, asset, pool);
        let caller_address = signer::address_of(caller);
        let amount_pair_in = math64::max(100000,math128::mul_div(amount_in as u128, 1, 1000) as u64);
        let balance_asset_before_swap =
            primary_fungible_store::balance(caller_address, position.asset);
        let balance_pair_before_swap =
            primary_fungible_store::balance(caller_address, position.pair);
        
        swap_with_hyperion(
            caller,
            &position.pair,
            &position.asset,
            amount_pair_in,
            false
        );

        let actual_amount_asset_swap =
            balance_asset_before_swap
                - primary_fungible_store::balance(
                    caller_address, position.asset
                );
        let actual_amount_pair =
            primary_fungible_store::balance(caller_address, position.pair)
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
                - primary_fungible_store::balance(
                    caller_address, position.asset
                );

        // Update position data
        position.position = position_addr;
        position.lp_amount = stable_views::position_shares(pool, position_idx) as u128;
        position.amount = position.amount + actual_amount;
        set_position_data(caller, pool, position);
        actual_amount
    }

    // Collect all pools with their amounts from TAPP data
    fun collect_pool_amounts(
        vault_signer: &signer, tapp_data: &OrderedMap<address, Position>
    ): vector<PoolAmountPair> acquires TappData {
        let pool_amounts = vector::empty<PoolAmountPair>();

        tapp_data.for_each_ref(
            |pool, _| {
                let position_data = get_position_data(vault_signer, *pool);
                if (position_data.amount > 0) {
                    let pair =
                        PoolAmountPair { pool_address: *pool, amount: position_data.amount };
                    vector::push_back(&mut pool_amounts, pair);
                };
            }
        );

        pool_amounts
    }

    // Sort pools by amount (smallest first) using bubble sort
    fun sort_pools_by_amount_asc(
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

    // Sort pools by amount (largest first) using bubble sort
    fun sort_pools_by_amount_desc(
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
                if (amount1 < amount2) {
                    vector::swap(pool_amounts, j, j + 1);
                };
                j = j + 1;
            };
            i = i + 1;
        };
    }

    // Calculate total amount across all pools
    fun calculate_total_pool_amount(
        pool_amounts: &vector<PoolAmountPair>
    ): u64 {
        let total = 0u64;
        let i = 0;
        let len = vector::length(pool_amounts);

        while (i < len) {
            let pair = vector::borrow(pool_amounts, i);
            total = total + pair.amount;
            i = i + 1;
        };

        total
    }

    // Withdraw from multiple pools in order
    fun withdraw_from_pools_sequential(
        vault_signer: &signer,
        vault_name: &String,
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
                    pair.amount // Withdraw everything
                } else {
                    math64::min(remaining_needed, pair.amount)
                };

            if (withdraw_from_this_pool > 0) {
                let (_, actual_withdrawn) =
                    withdraw_from_tapp_impl(
                        vault_signer,
                        &strategy_echelon::vault_borrow_asset(*vault_name),
                        pair.pool_address,
                        withdraw_from_this_pool
                    );

                // Add to total withdrawn (no conversion needed as position.asset == borrow_asset)
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

    /// Main function to handle TAPP withdrawal with sorting
    fun handle_tapp_withdrawal(
        vault_signer: &signer,
        vault_name: &String,
        tapp_data: &OrderedMap<address, Position>,
        withdraw_amount: u64,
        total_borrow_amount: u64
    ): u64 acquires TappData {
        let should_withdraw_all = withdraw_amount >= total_borrow_amount;

        if (!should_withdraw_all && withdraw_amount == 0) {
            return 0; // No need to withdraw from TAPP
        };

        // Collect and sort pools
        let pool_amounts = collect_pool_amounts(vault_signer, tapp_data);
        sort_pools_by_amount_asc(&mut pool_amounts); // Sort smallest first

        let target_amount =
            if (should_withdraw_all) {
                U64_MAX
            } else {
                withdraw_amount
            };

        // Withdraw from pools
        let withdrawn_amount =
            withdraw_from_pools_sequential(
                vault_signer,
                vault_name,
                &pool_amounts,
                target_amount,
                should_withdraw_all
            );

        withdrawn_amount
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
    fun claim_tapp_reward(
        caller: &signer, asset: Object<Metadata>, pool: address
    ): u64 acquires TappData {
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
        let balance_before = primary_fungible_store::balance(caller_addr, asset);
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
                            &asset,
                            reward_balance,
                            false
                        );
                    };
                };
            }
        );
        position.lp_amount = stable_views::position_shares(pool, position_idx) as u128;
        set_position_data(caller, pool, position);
        (primary_fungible_store::balance(caller_addr, asset) - balance_before)
    }

    fun get_estimate_withdrawable_amount_to_asset(
        vault_name: String, asset: &Object<Metadata>
    ): u64 acquires TappData {
        let vault_addr = strategy_echelon::vault_address(vault_name);
        if (!exists<TappData>(vault_addr)) {
            return 0;
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

    fun get_estimate_withdrawable_amount(
        pool: address, position: &Position, asset: &Object<Metadata>
    ): u64 {
        if (position.lp_amount == 0) {
            return 0
        };
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
                    } else if (token_b == object::object_address(asset)) {
                        token_a
                    } else {
                        assert!(false, error::invalid_argument(E_INVALID_ASSET));
                        token_a // to satisfy the type checker
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

    fun get_amount_out(
        from: &Object<Metadata>, to: &Object<Metadata>, amount_in: u64
    ): u64 {
        if (amount_in == 0) {
            return 0;
        };
        if (object::object_address(from) == object::object_address(to)) {
            return amount_in;
        };
        let (pool, _, _) = get_hyperion_pool(from, to);
        let (amount_out, _) = hyperion::pool_v3::get_amount_out(pool, *from, amount_in);
        amount_out
    }

    /// return (pool, fee_tier, slippage)
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

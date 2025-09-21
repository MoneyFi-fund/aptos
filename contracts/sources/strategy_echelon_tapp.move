module moneyfi::strategy_echelon_tapp {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::bcs::to_bytes;
    use aptos_std::math128;
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

    use moneyfi::strategy_echelon;

    const ZERO_ADDRESS: address =
        @0x0000000000000000000000000000000000000000000000000000000000000000;

    /// Position not exists
    const E_TAPP_POSITION_NOT_EXISTS: u64 = 1;
    /// Invalid asset
    const E_INVALID_ASSET: u64 = 2;

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
        router_v3::exact_input_swap_entry(
            caller,
            0,
            amount_pair_in,
            0,
            79226673515401279992447579055 - 1,
            position.asset,
            position.pair,
            caller_address,
            timestamp::now_seconds() + 600 //10 minutes
        );

        let actual_amount_asset_swap =
            balance_asset_before_swap
                - primary_fungible_store::balance<Metadata>(
                    caller_address, position.asset
                );
        let actual_amount_pair =
            primary_fungible_store::balance<Metadata>(caller_address, position.pair)
                - balance_pair_before_swap;

        let assets =
            hook_factory::pool_meta_assets(&hook_factory::pool_meta(pool));
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
        let (position_idx, position_addr) =
            integration::add_liquidity(caller, payload);

        let actual_amount =
            balance_asset_before_swap
                - primary_fungible_store::balance<Metadata>(
                    caller_address, position.asset
                );

        // Update position data
        position.position = position_addr;
        position.lp_amount =
            stable_views::position_shares(pool, position_idx) as u128;
        position.amount = position.amount + actual_amount;
        set_position_data(caller, pool, position);
        actual_amount
    }

    fun create_or_get_exist_position(
        caller: &signer,
        asset: &Object<Metadata>,
        pool: address
    ): Position acquires TappData {
        let caller_address = signer::address_of(caller);
        let tapp_data = ensure_tapp_data(caller);
        let position =
            if (exists_tapp_position(tapp_data, pool)) {
                let position = ordered_map::borrow(
                    &tapp_data.pools, &pool
                );
                *position
            } else {
                let assets =
                    hook_factory::pool_meta_assets(
                        &hook_factory::pool_meta(pool)
                    );
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
        caller: &signer,
        pool: address,
        position: Position
    ) acquires TappData {
        let caller_address = signer::address_of(caller);
        let tapp_data = borrow_global_mut<TappData>(caller_address);
        ordered_map::upsert(&mut tapp_data.pools, pool, position);
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
}

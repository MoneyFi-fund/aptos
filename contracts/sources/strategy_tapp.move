module moneyfi::strategy_tapp {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use std::bcs::to_bytes;
    use aptos_std::from_bcs;
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
    friend moneyfi::strategy;

    // -- Constants
    const DEADLINE_BUFFER: u64 = 31556926; // 1 years
    const USDC_ADDRESS: address = @stablecoin;
    const ZERO_ADDRESS: address = @0x0000000000000000000000000000000000000000000000000000000000000000;

    const STRATEGY_ID: u8 = 4;

    // -- Error
    /// Tapp Strategy data not exists
    const E_TAPP_STRATEGY_DATA_NOT_EXISTS: u64 = 1;
    /// Position not exists
    const E_TAPP_POSITION_NOT_EXISTS: u64 = 2;
    /// Invalid asset
    const E_INVALID_ASSET: u64 = 3;

    // -- Structs
    struct StrategyStats has key {
        assets: OrderedMap<Object<Metadata>, AssetStats> // assets -> AssetStats
    }

    struct AssetStats has drop, store {
        total_value_locked: u128, // total value locked in this asset
        total_deposited: u128, // total deposited amount
        total_withdrawn: u128 // total withdrawn amount
    }

    struct TappStrategyData has copy, drop, store {
        strategy_id: u8,
        pools: OrderedMap<address, Position> // pool address -> Position
    }

    struct Position has copy, drop, store {
        position: address, // position address
        lp_amount: u128, // Liquidity pool amount
        asset: Object<Metadata>,
        pair: Object<Metadata>,
        amount: u64,
    }

    struct ExtraData has drop, copy, store {
        pool: address,
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


    // returns(actual_amount)
    public(friend) fun deposit_fund_to_thala_single(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount_in: u64,
        extra_data: vector<vector<u8>>
    ): u64 acquires StrategyStats {
        let extra_data = unpack_extra_data(extra_data);
        let position = create_or_get_exist_position(
            account, asset, extra_data
        );
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        let balance_asset_before_swap = primary_fungible_store::balance<Metadata>(wallet_address, position.asset);
        let balance_pair_before_swap = primary_fungible_store::balance<Metadata>(wallet_address, position.pair);
        router_v3::exact_input_swap_entry(
            &wallet_signer,
            0,
            1000,
            0,
            4295048016 + 1,
            position.asset,
            position.pair,
            signer::address_of(&wallet_signer),
            timestamp::now_seconds() + DEADLINE_BUFFER
        );

        let actual_amount_asset_swap = balance_asset_before_swap - primary_fungible_store::balance<Metadata>(wallet_address, position.asset);
        let actual_amount_pair = primary_fungible_store::balance<Metadata>(wallet_address, position.pair) - balance_pair_before_swap;
        
        let assets = hook_factory::pool_meta_assets(
                    &hook_factory::pool_meta(extra_data.pool)
                );
        let token_a = *vector::borrow(&assets, 0);
        let token_b = *vector::borrow(&assets, 1);

        // Determine which token we're depositing and create amounts vector
        let amounts = vector::empty<u256>();

        if (object::object_address(asset) == token_a) {
            // Depositing token A (first token)
            vector::push_back(&mut amounts, (amount_in - actual_amount_asset_swap) as u256);
            vector::push_back(&mut amounts, actual_amount_pair as u256);
        } else if (object::object_address(asset) == token_b) {
            // Depositing token B (second token)
            vector::push_back(&mut amounts, actual_amount_pair as u256);
            vector::push_back(&mut amounts, (amount_in - actual_amount_asset_swap) as u256);
        } else {
            // Asset is not part of this pool
            assert!(false, error::invalid_argument(E_INVALID_ASSET));
        };
        // serialize data to bytes
        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&extra_data.pool));
        if(position.position == ZERO_ADDRESS){
            vector::append(&mut payload, to_bytes<Option<address>>(&option::none<address>()));
        }else {
            vector::append(&mut payload, to_bytes<Option<address>>(&option::some(position.position)));
        };
        vector::append(&mut payload, to_bytes<vector<u256>>(&amounts));
        let minMintAmount: u256 = 0;
        vector::append(&mut payload, to_bytes<u256>(&minMintAmount));
        // Call integration to add liquidity
        let (position_idx, position_addr) = integration::add_liquidity(&wallet_signer, payload);

        let actual_amount = balance_asset_before_swap - primary_fungible_store::balance<Metadata>(wallet_address, position.asset);

        // Update position data
        position.position = position_addr;
        position.lp_amount = stable_views::position_shares(extra_data.pool, position_idx) as u128;
        position.amount = position.amount + actual_amount;
        strategy_stats_deposit(asset, actual_amount);
        let strategy_data = set_position_data(account, extra_data.pool, position);
        wallet_account::set_strategy_data(account, strategy_data);
        actual_amount
    }

    //return (total_deposited_amount, total_withdrawn_amount)
    public(friend) fun withdraw_fund_from_thala_single(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount_min: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64, u64) acquires StrategyStats {
        let extra_data = unpack_extra_data(extra_data);
        let position = get_position_data(account, extra_data.pool);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let wallet_address = signer::address_of(&wallet_signer);
        let (liquidity_remove, is_full_withdraw) =
            if (amount_min < position.amount) {
                let liquidity =
                    math128::mul_div(
                        position.lp_amount,
                        (amount_min as u128),
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
            } else {
                position.asset
            };
        let balance_asset_before = primary_fungible_store::balance(
            wallet_address, *asset
        );
        let balance_pair_before = primary_fungible_store::balance(wallet_address, pair);
        let (active_rewards, _) = get_active_rewards(extra_data.pool, &position);
        // Serialize data to bytes
        let payload: vector<u8> = vector[];
        vector::append(&mut payload, to_bytes<address>(&extra_data.pool));
        vector::append(&mut payload, to_bytes<address>(&position.position));
        let remove_type: u8 = 3;
        vector::append(&mut payload, to_bytes<u8>(&remove_type));
        vector::append(&mut payload, to_bytes<u256>(&liquidity_remove));
        let remove_amounts = stable_views::calc_ratio_amounts(
            extra_data.pool, liquidity_remove
        ); 
        let min_amounts = vector::map(remove_amounts, |amount| {
            math128::mul_div(amount as u128, 98, 100) as u256
        });
        vector::append(&mut payload, to_bytes<vector<u256>>(&min_amounts));
        // Call integration to remove liquidity
        router::remove_liquidity(&wallet_signer, payload);

        let pair_amount = primary_fungible_store::balance(
            wallet_address, pair
        ) - balance_pair_before;
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
                timestamp::now_seconds() + DEADLINE_BUFFER
            );
        };

        vector::for_each(active_rewards, |reward_token_addr| {
            if (reward_token_addr != object::object_address(asset)) {
                let reward_balance = primary_fungible_store::balance(
                    wallet_address, object::address_to_object<Metadata>(reward_token_addr)
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
                        timestamp::now_seconds() + DEADLINE_BUFFER
                    );
                };
            };
        });

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
        strategy_stats_withdraw(
            asset, total_deposited_amount, total_withdrawn_amount
        );
        (total_deposited_amount, total_withdrawn_amount, extra_data.withdraw_fee)
    }

    // return (active_reward, active_reward_amount)
    fun get_active_rewards(pool: address, position: &Position): (vector<address>, vector<u64>) {
        let active_reward = vector::empty<address>();
        let active_reward_amount = vector::empty<u64>();

        let rewards = stable::calculate_pending_rewards(pool, position::position_idx(&position::position_meta(position.position)));
        vector::for_each_ref(&rewards, |reward| {
            let token_addr = stable::campaign_reward_token(reward);
            let amount = stable::campaign_reward_amount(reward);
            if (amount > 0) {
                let (found, index) = vector::index_of(&active_reward, &token_addr);
                if (found) {
                    let existing_amount = vector::borrow_mut(&mut active_reward_amount, index);
                    *existing_amount = *existing_amount + amount;
                } else {
                    vector::push_back(&mut active_reward, token_addr);
                    vector::push_back(&mut active_reward_amount, amount);
                };
            };
        });
        (active_reward, active_reward_amount)
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
        asset: &Object<Metadata>, deposit_amount: u64, interest: u64
    ) acquires StrategyStats {
        let stats = borrow_global_mut<StrategyStats>(@moneyfi);
        if (ordered_map::contains(&stats.assets, asset)) {
            let asset_stats = ordered_map::borrow_mut(&mut stats.assets, asset);
            asset_stats.total_value_locked =
                asset_stats.total_value_locked - (deposit_amount as u128);
            asset_stats.total_withdrawn =
                asset_stats.total_withdrawn + ((deposit_amount + interest) as u128);
        } else {
            assert!(false, error::not_found(E_TAPP_POSITION_NOT_EXISTS));
        };
    }

    fun ensure_tapp_strategy_data(account: &Object<WalletAccount>): TappStrategyData {
        if (!exists_tapp_strategy_data(account)) {
            let strategy_data = TappStrategyData {
                strategy_id: STRATEGY_ID,
                pools: ordered_map::new<address, Position>()
            };
            wallet_account::set_strategy_data<TappStrategyData>(account, strategy_data);
        };
        let strategy_data = wallet_account::get_strategy_data<TappStrategyData>(account);
        strategy_data
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
        let position =
            if (exists_tapp_position(account, extra_data.pool)) {
                let position = ordered_map::borrow(
                    &strategy_data.pools, &extra_data.pool
                );
                *position
            } else {
                let assets = hook_factory::pool_meta_assets(
                    &hook_factory::pool_meta(extra_data.pool)
                );
                let token_a = *vector::borrow(&assets, 0);
                let token_b = *vector::borrow(&assets, 1);
                let pair = if (token_a == object::object_address(asset)) {
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

    fun unpack_extra_data(extra_data: vector<vector<u8>>): ExtraData {
        let extra_data = ExtraData {
            pool: from_bcs::to_address(*vector::borrow(&extra_data, 0)),
            withdraw_fee: from_bcs::to_u64(*vector::borrow(&extra_data, 1))
        };
        extra_data
    }

    //-- Views
    #[view]
    public fun get_user_strategy_data(wallet_id: vector<u8>): TappStrategyData {
        let account = wallet_account::get_wallet_account(wallet_id);
        if (!exists_tapp_strategy_data(&account)) {
            assert!(false, error::not_found(E_TAPP_STRATEGY_DATA_NOT_EXISTS));
        };
        wallet_account::get_strategy_data<TappStrategyData>(&account)
    }

    #[view]
    public fun pack_extra_data(
        pool: address,
        withdraw_fee: u64
    ): vector<vector<u8>> {
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
        let strategy_data =
            wallet_account::get_strategy_data<TappStrategyData>(&account);
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
            let profit =
                get_pending_rewards_and_fees_usdc(
                    pool_address, *position
                );
            total_profit = total_profit + profit;
            i = i + 1;
        };

        total_profit
    }

     fun get_pending_rewards_and_fees_usdc(
        pool: address, position: Position
    ): u64 {
        let stablecoin_metadata = object::address_to_object<Metadata>(USDC_ADDRESS);
        let (active_rewards, reward_amounts) = get_active_rewards(pool, &position);
        let assets = hook_factory::pool_meta_assets(
            &hook_factory::pool_meta(pool)
        );
        let amounts = stable_views::calc_ratio_amounts(pool, position.lp_amount as u256);
        let lp_path: vector<address> = vector[
            @0x6fc5dbd4c66b9f96644bd3412b8e836a584bd10ddee62c380d54fc2f75369f4a,
            @0xd3894aca06d5f42b27c89e6f448114b3ed6a1ba07f992a58b2126c71dd83c127
        ];
        let total_profit: u64 = 0;
        let i = 0;
        let assets_len = vector::length(&assets);
        while (i < assets_len) {
            let asset_addr = *vector::borrow(&assets, i);
            let asset_amount = *vector::borrow(&amounts, i);
            let asset_metadata = object::address_to_object<Metadata>(asset_addr);
            if (asset_addr == object::object_address(&stablecoin_metadata)) {
                total_profit = total_profit + (asset_amount as u64);
            } else {
                let path = vector::singleton<address>(*vector::borrow(&lp_path, 1));
                let amount_out = router_v3::get_batch_amount_out(path, (asset_amount as u64), asset_metadata, stablecoin_metadata);
                total_profit = total_profit + amount_out;
            };
            i = i + 1;
        };
        
        vector::for_each(active_rewards, |reward_token_addr| {
            let (_, index) = vector::index_of(&active_rewards, &reward_token_addr);
            let reward_amount = *vector::borrow(&reward_amounts, index);
            let reward_metadata = object::address_to_object<Metadata>(reward_token_addr);
            if (reward_token_addr == object::object_address(&stablecoin_metadata)) {
                let amount_out = router_v3::get_batch_amount_out(lp_path, reward_amount, reward_metadata, stablecoin_metadata);
                total_profit = total_profit + amount_out;
            }
        });

        if (total_profit > position.amount) {
            total_profit - position.amount
        } else { 0 }
    }
}
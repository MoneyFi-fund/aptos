module moneyfi::thala_strategy {
    use std::signer;
    use std::vector;
    use std::option;
    use std::string::String;
    use std::bcs::to_bytes;
    use aptos_std::from_bcs;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::aptos_coin::AptosCoin;

    use thalaswap_v2::pool::{Self, Pool};
    use thalaswap_v2::coin_wrapper::{Self, Notacoin};
    use thala_staked_lpt::staked_lpt;
    use thala_lsd::staking::ThalaAPT;

    use moneyfi::wallet_account::{Self, WalletAccount};
    use dex_contract::router_v3;
    friend moneyfi::strategy;

    // -- Constants
    const DEADLINE_BUFFER: u64 = 31556926; // 1 years
    const USDC_ADDRESS: address = @stablecoin;

    const STRATEGY_ID: u8 = 3;

    // -- Error
    /// Thala Strategy data not exists
    const E_THALA_STRATEGY_DATA_NOT_EXISTS: u64 = 1;
    /// Position not exists
    const E_THALA_POSITION_NOT_EXISTS: u64 = 2;
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

    struct ThalaStrategyData has copy, drop, store {
        strategy_id: u8,
        pools: OrderedMap<address, Position> // pool address -> Position
    }

    struct Position has copy, drop, store {
        lp_amount: u128, // Liquidity pool amount
        asset: Object<Metadata>,
        pair: Object<Metadata>,
        amount: u64,
        staked_lp_amount: u64,
        reward_ids: vector<String>
    }

    struct ExtraData has drop, copy, store {
        pool: address,
        reward_a: String,
        reward_b: String
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
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount_in: u64,
        extra_data: vector<vector<u8>>
    ): u64 acquires StrategyStats{
        let extra_data = unpack_extra_data(extra_data);
        let position = create_or_get_exist_position(account, asset, extra_data);
        let wallet_signer = wallet_account::get_wallet_account_signer(account);
        let pool_obj = object::address_to_object<Pool>(extra_data.pool);
        let assets = pool::pool_assets_metadata(pool_obj);
        let token_a = *vector::borrow(&assets, 0);
        let token_b = *vector::borrow(&assets, 1);

        // Determine which token we're depositing and create amounts vector
        let amounts = vector::empty<u64>();
        
        if (asset == token_a) {
            // Depositing token A (first token)
            vector::push_back(&mut amounts, amount_in);  // Amount for token A
            vector::push_back(&mut amounts, 0);          // 0 for token B
        } else if (asset == token_b) {
            // Depositing token B (second token)
            vector::push_back(&mut amounts, 0);          // 0 for token A
            vector::push_back(&mut amounts, amount_in);  // Amount for token B
        } else {
            // Asset is not part of this pool
            assert!(false ,E_INVALID_ASSET);
        };

        let balance_asset_before =
            primary_fungible_store::balance(
                signer::address_of(&wallet_signer), position.asset
            );
        let preview = pool::preview_add_liquidity_stable(pool_obj, assets, amounts);
        let (lp_amount, _) = pool::add_liquidity_preview_info(preview);
        coin_wrapper::add_liquidity_stable<Notacoin, Notacoin, Notacoin, Notacoin, Notacoin, Notacoin>(
            &wallet_signer,
            pool_obj,
            amounts,
            lp_amount
        );

        let actual_amount = balance_asset_before - primary_fungible_store::balance(signer::address_of(&wallet_signer), position.asset);
        let pool_lp_token_metadata = pool::pool_lp_token_metadata(pool_obj);
        staked_lpt::stake_entry(
            &wallet_signer,
            pool_lp_token_metadata,
            lp_amount
        );
        position.lp_amount = position.lp_amount + (lp_amount as u128);
        position.amount = position.amount + actual_amount;
        position.staked_lp_amount = position.staked_lp_amount + lp_amount;
        strategy_stats_deposit(asset, actual_amount);
        let strategy_data = set_position_data(account, extra_data.pool, position);
        wallet_account::set_strategy_data(account, strategy_data);
        actual_amount
    }

    // return (total_deposited_amount, total_withdrawn_amount)
    public(friend) fun withdraw_fund_from_thala_single(
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount_min: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64) {
        let extra_data = unpack_extra_data(extra_data);
        let position = get_position_data(account, extra_data.pool);
        let pool_obj = object::address_to_object<Pool>(extra_data.pool);
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
                (liquidity, false)
            } else {
                (position.lp_amount, true)
            };
        let balance_asset_after = primary_fungible_store::balance(wallet_address, asset);
        //Claim reward
        let pool_lp_token_metadata = pool::pool_lp_token_metadata(pool_obj);
        let reward_ids = position.reward_ids;
        vector::for_each(reward_ids, |reward_id| {
            let amount = staked_lpt::claimable_reward(
                wallet_address, 
                staked_lpt::get_staked_lpt_metadata_from_lpt(pool_lp_token_metadata), 
                reward_id
            );
            staked_lpt::claim_reward(
                &wallet_signer,
                wallet_address, 
                staked_lpt::get_staked_lpt_metadata_from_lpt(pool_lp_token_metadata), 
                reward_id
            );
            if(object::object_address(&position.asset) == object::object_address(&staked_lpt::get_reward_metadata(reward_id))){
                if(amount > 0){
                    let lp_path: vector<address> = vector[
                        @0x692ba87730279862aa1a93b5fef9a175ea0cccc1f29dfc84d3ec7fbe1561aef3,
                        @0x925660b8618394809f89f8002e2926600c775221f43bf1919782b297a79400d8
                    ];
                    router_v3::swap_batch_coin_entry<ThalaAPT>(
                        &wallet_signer,
                        lp_path,
                        staked_lpt::get_reward_metadata(reward_id),
                        position.asset,
                        amount,
                        0,
                        wallet_address
                    );
                }
            };
        });
        //Remove lp
        let assets = pool::pool_assets_metadata(pool_obj);
        let amounts = pool::remove_liquidity_preview_info(pool::preview_remove_liquidity(pool_obj, pool_lp_token_metadata, liquidity_remove as u64));
        pool::remove_liquidity_entry(
            &wallet_signer,
            pool_obj, 
            pool_lp_token_metadata, 
            liquidity_remove as u64,
            amounts
        );
        let i = 0;
        while (i < vector::length(&assets)) {
            let token = *vector::borrow(&assets, i);
            if (object::object_address(&token) != object::object_address(&asset)) {
                let (_, index) = vector::index_of(&assets, &token);
                let amount = *vector::borrow(&amounts, index);
                let (_, _, amount_out, _, _, _, _, _, _, _) = pool::swap_preview_info(pool::preview_swap_exact_in_stable(
                    pool_obj, 
                    token, 
                    asset, 
                    amount, 
                    option::none()
                ));
                coin_wrapper::swap_exact_in_stable<AptosCoin>(
                    &wallet_signer,
                    pool_obj,
                    token,
                    amount,
                    asset,
                    amount_out
                );
            };
            i = i + 1;
        };
        let balance_asset_before = primary_fungible_store::balance(wallet_address, asset);
        let total_withdrawn_amount = balance_asset_before - balance_asset_after;
        let (total_deposited_amount, strategy_data) = if(is_full_withdraw) {
            (position.amount, remove_position(account, extra_data.pool))
        }else {
            position.amount = position.amount - amount_min;
            position.lp_amount = position.lp_amount - liquidity_remove;
            position.staked_lp_amount= position.staked_lp_amount - (liquidity_remove as u64);
            (amount_min, set_position_data(account, extra_data.pool, position))
        };
        wallet_account::set_strategy_data(account, strategy_data);
        (total_deposited_amount, total_withdrawn_amount)
    }

    // return (
    //    actual_amount_in,
    //    actual_amount_out
    // )
    public(friend) fun swap(
        account: Object<WalletAccount>,
        from_asset: Object<Metadata>,
        to_asset: Object<Metadata>,
        amount_in: u64,
        min_amount_out: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64) {
        (0, 0)
    }

    fun strategy_stats_deposit(asset: Object<Metadata>, amount: u64) acquires StrategyStats {
        let stats = borrow_global_mut<StrategyStats>(@moneyfi);
        if (ordered_map::contains(&stats.assets, &asset)) {
            let asset_stats = ordered_map::borrow_mut(&mut stats.assets, &asset);
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
            ordered_map::upsert(&mut stats.assets, asset, new_asset_stats);
        };
    }

    fun strategy_stats_withdraw(
        asset: Object<Metadata>, deposit_amount: u64, interest: u64
    ) acquires StrategyStats {
        let stats = borrow_global_mut<StrategyStats>(@moneyfi);
        if (ordered_map::contains(&stats.assets, &asset)) {
            let asset_stats = ordered_map::borrow_mut(&mut stats.assets, &asset);
            asset_stats.total_value_locked =
                asset_stats.total_value_locked - (deposit_amount as u128);
            asset_stats.total_withdrawn =
                asset_stats.total_withdrawn + ((deposit_amount + interest) as u128);
        } else {
            assert!(false, E_THALA_POSITION_NOT_EXISTS);
        };
    }

    fun ensure_thala_strategy_data(account: Object<WalletAccount>): ThalaStrategyData {
        if (!exists_thala_strategy_data(account)) {
            let strategy_data = ThalaStrategyData {
                strategy_id: STRATEGY_ID,
                pools: ordered_map::new<address, Position>()
            };
            wallet_account::set_strategy_data<ThalaStrategyData>(account, strategy_data);
        };
        let strategy_data = wallet_account::get_strategy_data<ThalaStrategyData>(account);
        strategy_data
    }

    fun exists_thala_strategy_data(account: Object<WalletAccount>): bool {
        wallet_account::exists_strategy_data<ThalaStrategyData>(account)
    }

    fun exists_thala_postion(
        account: Object<WalletAccount>, pool: address
    ): bool {
        assert!(
            exists_thala_strategy_data(account),
            E_THALA_STRATEGY_DATA_NOT_EXISTS
        );
        let strategy_data = ensure_thala_strategy_data(account);
        ordered_map::contains(&strategy_data.pools, &pool)
    }

    fun set_position_data(
        account: Object<WalletAccount>, pool: address, position: Position
    ): ThalaStrategyData {
        let strategy_data = ensure_thala_strategy_data(account);
        ordered_map::upsert(&mut strategy_data.pools, pool, position);
        strategy_data
    }

    fun create_or_get_exist_position(
        account: Object<WalletAccount>, asset: Object<Metadata>, extra_data: ExtraData
    ): Position {
        let strategy_data = ensure_thala_strategy_data(account);
        let position =
            if (exists_thala_postion(account, extra_data.pool)) {
                let position = ordered_map::borrow(&strategy_data.pools, &extra_data.pool);
                *position
            } else {
                let pool_obj = object::address_to_object<Pool>(extra_data.pool);
                let assets = pool::pool_assets_metadata(pool_obj);
                let token_a = *vector::borrow(&assets, 0);
                let token_b = *vector::borrow(&assets, 1);
                let reward_ids = vector::singleton<String>(extra_data.reward_a);
                vector::push_back(&mut reward_ids, extra_data.reward_b);
                let pair =
                    if (object::object_address<Metadata>(&asset)
                        == object::object_address<Metadata>(&token_a)) {
                        token_b
                    } else {
                        token_a
                    };
                let new_position =
                    Position {
                        lp_amount: 0, // Liquidity pool amount
                        asset: asset,
                        pair: pair,
                        amount: 0,
                        staked_lp_amount: 0,
                        reward_ids: reward_ids
                    };
                new_position
            };
        position
    }

    fun remove_position(account: Object<WalletAccount>, pool: address): ThalaStrategyData {
        let strategy_data = ensure_thala_strategy_data(account);
        ordered_map::remove(&mut strategy_data.pools, &pool);
        strategy_data
    }

    fun get_position_data(account: Object<WalletAccount>, pool: address): Position {
        assert!(exists_thala_postion(account, pool), E_THALA_POSITION_NOT_EXISTS);
        let strategy_data = ensure_thala_strategy_data(account);
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
            reward_a: from_bcs::to_string(*vector::borrow(&extra_data, 1)),
            reward_b: from_bcs::to_string(*vector::borrow(&extra_data, 2))
        };
        extra_data
    }

    //-- Views
    #[view]
    public fun get_user_strategy_data(wallet_id: vector<u8>): ThalaStrategyData {
        let account = wallet_account::get_wallet_account(wallet_id);
        if (!exists_thala_strategy_data(account)) {
            assert!(false, E_THALA_STRATEGY_DATA_NOT_EXISTS);
        };
        wallet_account::get_strategy_data<ThalaStrategyData>(account)
    }

    #[view]
    public fun pack_extra_data(pool: address, reward_a: String, reward_b: String): vector<vector<u8>> {
        let extra_data = vector::singleton<vector<u8>>(to_bytes<address>(&pool));
        vector::push_back(&mut extra_data, to_bytes<String>(&reward_a));
        vector::push_back(&mut extra_data, to_bytes<String>(&reward_b));
        extra_data
    }

    #[view]
    public fun get_profit(wallet_id: vector<u8>): u64 {
        let account = wallet_account::get_wallet_account(wallet_id);
        if (!exists_thala_strategy_data(account)) {
            return 0
        };
        let strategy_data = wallet_account::get_strategy_data<ThalaStrategyData>(account);
        let total_profit: u64 = 0;
        let pools = ordered_map::keys<address, Position>(&strategy_data.pools);
        let i = 0;
        let pools_len = vector::length(&pools);

        while (i < pools_len) {
            let pool_address = *vector::borrow(&pools, i);
            let position = ordered_map::borrow<address, Position>(&strategy_data.pools, &pool_address);
            let pool = object::address_to_object<Pool>(pool_address);
            let profit = get_pending_rewards_and_fees_usdc(object::object_address(&account), pool, *position);
            total_profit = total_profit + profit;
            i = i + 1;
        };

        total_profit
    }

    fun get_pending_rewards_and_fees_usdc(wallet_address: address, pool: Object<Pool>, position: Position): u64 {
        let stablecoin_metadata = object::address_to_object<Metadata>(USDC_ADDRESS);
        let pool_lp_token_metadata = pool::pool_lp_token_metadata(pool);
        let assets = pool::pool_assets_metadata(pool);
        let amounts = pool::remove_liquidity_preview_info(pool::preview_remove_liquidity(pool, pool_lp_token_metadata, position.lp_amount as u64));
        let reward_ids = position.reward_ids;
        let amount_rewards = vector::map(reward_ids, |reward_id| 
            staked_lpt::claimable_reward(
                wallet_address, 
                staked_lpt::get_staked_lpt_metadata_from_lpt(pool_lp_token_metadata), 
                reward_id
            )
        );
        
        let total_stablecoin_amount: u64 = 0;
        let i = 0;
        let assets_len = vector::length(&assets);
        while (i < assets_len) {
            let asset_metadata = *vector::borrow(&assets, i);
            let asset_amount = *vector::borrow(&amounts, i);
            
            if (object::object_address(&asset_metadata) == object::object_address(&stablecoin_metadata)) {
                total_stablecoin_amount = total_stablecoin_amount + asset_amount;
            } else {
                let swap_preview = pool::preview_swap_exact_in_stable(
                    pool, 
                    asset_metadata, 
                    stablecoin_metadata, 
                    asset_amount, 
                    option::none()
                );
                let (_, _, amount_out, _, _, _, _, _, _, _) = pool::swap_preview_info(swap_preview);
                total_stablecoin_amount = total_stablecoin_amount + amount_out;
            };
            i = i + 1;
        };
        
        let lp_path: vector<address> = vector[
            @0x692ba87730279862aa1a93b5fef9a175ea0cccc1f29dfc84d3ec7fbe1561aef3,
            @0x925660b8618394809f89f8002e2926600c775221f43bf1919782b297a79400d8
        ];
        
        let j = 0;
        let rewards_len = vector::length(&reward_ids);
        while (j < rewards_len) {
            let reward_id = *vector::borrow(&reward_ids, j);
            let reward_amount = *vector::borrow(&amount_rewards, j);
            
            let reward_metadata = staked_lpt::get_reward_metadata(reward_id);
            
            if (object::object_address(&reward_metadata) == object::object_address(&stablecoin_metadata)) {
                total_stablecoin_amount = total_stablecoin_amount + reward_amount;
            } else {
                 if (reward_amount > 0) {
                    let usdc_amount = router_v3::get_batch_amount_out(
                        lp_path,
                        reward_amount,
                        reward_metadata,
                        stablecoin_metadata
                    );
                    total_stablecoin_amount = total_stablecoin_amount + usdc_amount;
                };
            };
            j = j + 1;
        };
        
        total_stablecoin_amount - position.amount
    }
}

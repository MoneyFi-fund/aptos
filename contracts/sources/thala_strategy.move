module moneyfi::thala_strategy {
    use std::signer;
    use std::vector;
    use std::bcs::to_bytes;
    use aptos_std::from_bcs;
    use aptos_std::bcs_stream;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset::Metadata;

    use thalaswap_v2::pool;
    use thalaswap_v2::coin_wrapper::{Self, Notacoin};
    use thala_staked_lpt::staked_lpt;

    use moneyfi::wallet_account::{Self, WalletAccount};
    friend moneyfi::strategy;

    // -- Constants
    const DEADLINE_BUFFER: u64 = 31556926; // 1 years
    const USDC_ADDRESS: address = @stablecoin;

    const STRATEGY_ID: u8 = 2;

    // -- Error
    /// Thala Strategy data not exists
    const E_THALA_STRATEGY_DATA_NOT_EXISTS: u64 = 1;
    /// Position not exists
    const E_THALA_POSITION_NOT_EXISTS: u64 = 3;

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
        reward_metadata: Object<Metadata>,
        // The amount of interest earned from the position
        interest_amount: u64
    }

    struct ExtraData has drop, copy, store {
        pool: address
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
        extra_data: vector<u8>
    ): u64 {
        0
        //TODO
    }

    // return (total_deposited_amount, total_withdrawn_amount)
    public(friend) fun withdraw_fund_from_thala_single(
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount_min: u64,
        extra_data: vector<u8>
    ): (u64, u64) {
        (0, 0)
        //TODO
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
        extra_data: vector<u8>
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

    fun unpack_extra_data(extra_data: vector<u8>): ExtraData {
        let bcs = bcs_stream::new(extra_data);
        let extra_data = ExtraData { pool: bcs_stream::deserialize_address(&mut bcs) };
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
    public fun pack_extra_data(pool: address): vector<u8> {
        let extra_data: vector<u8> = vector[];
        vector::append(&mut extra_data, to_bytes<address>(&pool));
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

        total_profit
    }
}

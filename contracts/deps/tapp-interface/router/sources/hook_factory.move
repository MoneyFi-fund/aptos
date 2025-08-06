module tapp::hook_factory {

    struct IncentiveReward has copy, drop {
        token: address,
        amount: u64,
    }
    
    struct PoolIncentiveMeta has copy, drop, store, key {
        pool_addr: address,
        assets: vector<address>,
        reserves: vector<u64>,
    }
    
    struct PoolMeta has copy, drop, store, key {
        pool_addr: address,
        hook_type: u8,
        assets: vector<address>,
        reserves: vector<u64>,
        is_paused: bool,
        platform_fee_rate: u64,
    }

    public fun pool_meta(arg0: address) : PoolMeta acquires PoolMeta {
        *borrow_global<PoolMeta>(arg0)
    }

    public fun pool_meta_assets(arg0: &PoolMeta) : vector<address> {
        arg0.assets
    }
}
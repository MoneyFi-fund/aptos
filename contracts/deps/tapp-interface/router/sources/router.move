module tapp::router {
    use aptos_framework::object;
    use tapp::hook_factory;
    struct PoolCap has key {
        extend_ref: object::ExtendRef
    }

    public entry fun swap(arg0: &signer, arg1: vector<u8>) {
        abort 0x1;
    }

    public entry fun collect_fee(arg0: &signer, arg1: vector<u8>) {
        abort 0x1;
    }

    public entry fun remove_liquidity(arg0: &signer, arg1: vector<u8>) {
        abort 0x1;
    }

    public fun get_pool_meta(arg0: address): hook_factory::PoolMeta {
        hook_factory::pool_meta(arg0)
    }
}

module tapp::position {
    struct PositionMeta has copy, drop, store, key {
        hook_type: u8,
        pool_addr: address,
        position_idx: u64,
    }
    
    public fun hook_type(arg0: &PositionMeta) : u8 {
        arg0.hook_type
    }

    public fun pool_id(arg0: &PositionMeta) : address {
        arg0.pool_addr
    }
    
    public fun position_idx(arg0: &PositionMeta) : u64 {
        arg0.position_idx
    }
    
    public fun position_meta(arg0: address) : PositionMeta acquires PositionMeta {
        *borrow_global<PositionMeta>(arg0)
    }
}
module oracle::oracle {
    use aptos_std::type_info;
    use decimal::decimal;

    struct SwitchboardConfig has copy, drop, store {
        sb_addr: address,
        max_age: u64,
        weight: u64
    }

    public fun get_price(a0: type_info::TypeInfo): decimal::Decimal {
        decimal::from_u64(1)
    }
}

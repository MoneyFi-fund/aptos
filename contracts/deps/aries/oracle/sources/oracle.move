module oracle::oracle {
    use aptos_std::type_info;
    use decimal::decimal;

    struct SwitchboardConfig has copy, drop, store {
        sb_addr: address,
        max_age: u64,
        weight: u64
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun get_price(a0: type_info::TypeInfo): decimal::Decimal;
}

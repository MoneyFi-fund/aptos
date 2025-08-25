module aries::reserve {
    use aptos_std::type_info;

    use aries::decimal;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun get_borrow_amount_from_share_dec(
        a0: type_info::TypeInfo, a1: decimal::Decimal
    ): decimal::Decimal;
    #[native_interface]
    native public fun get_lp_amount_from_underlying_amount(
        a0: type_info::TypeInfo, a1: u64
    ): u64;
    #[native_interface]
    native public fun get_underlying_amount_from_lp_amount(
        a0: type_info::TypeInfo, a1: u64
    ): u64;
}

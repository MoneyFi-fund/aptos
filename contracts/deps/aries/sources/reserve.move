module aries::reserve {
    use aptos_std::type_info;

    use decimal::decimal;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun get_borrow_amount_from_share_dec(
        a0: type_info::TypeInfo, a1: decimal::Decimal
    ): decimal::Decimal;

    public fun get_lp_amount_from_underlying_amount(
        a0: type_info::TypeInfo, a1: u64
    ): u64 {
        aries::mock::get_call_data(
            b"reserve::get_lp_amount_from_underlying_amount", a1
        )
    }

    public fun get_underlying_amount_from_lp_amount(
        a0: type_info::TypeInfo, a1: u64
    ): u64 {
        // std::debug::print(&b"get_underlying_amount_from_lp_amount");
        aries::mock::get_call_data(
            b"reserve::get_underlying_amount_from_lp_amount", a1
        )
    }
}

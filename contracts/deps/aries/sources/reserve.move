module aries::reserve {
    use aptos_std::type_info;

    use decimal::decimal;

    public fun get_borrow_amount_from_share_dec(
        a0: type_info::TypeInfo, a1: decimal::Decimal
    ): decimal::Decimal {
        let v =
            aries::mock::get_call_data<u128>(
                b"reserve::get_borrow_amount_from_share_dec", 0
            );
        decimal::from_u128(v)
    }

    public fun get_lp_amount_from_underlying_amount(
        a0: type_info::TypeInfo, a1: u64
    ): u64 {
        // std::debug::print(&b"get_lp_amount_from_underlying_amount");
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

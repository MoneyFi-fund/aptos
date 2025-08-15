module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_details {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::interest_rate_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_details;

    struct ReserveDetails has copy, drop, store {
        total_lp_supply: u128,
        total_cash_available: u128,
        initial_exchange_rate: decimal::Decimal,
        reserve_amount: decimal::Decimal,
        total_borrowed_share: decimal::Decimal,
        total_borrowed: decimal::Decimal,
        interest_accrue_timestamp: u64,
        reserve_config: reserve_config::ReserveConfig,
        interest_rate_config: interest_rate_config::InterestRateConfig,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun allow_collateral(a0: &reserve_details::ReserveDetails): bool;
    #[native_interface]
    native public fun borrow(a0: &mut reserve_details::ReserveDetails, a1: u64);
    #[native_interface]
    native public fun calculate_borrow_fee(a0: &reserve_details::ReserveDetails, a1: u64): u64;
    #[native_interface]
    native public fun calculate_flash_loan_fee(a0: &reserve_details::ReserveDetails, a1: u64): u64;
    #[native_interface]
    native public fun calculate_repay(a0: &mut reserve_details::ReserveDetails, a1: u64, a2: decimal::Decimal): (u64, decimal::Decimal);
    #[native_interface]
    native public fun get_borrow_amount_from_share_amount(a0: &mut reserve_details::ReserveDetails, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun get_borrow_exchange_rate(a0: &mut reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun get_lp_amount_from_underlying_amount(a0: &mut reserve_details::ReserveDetails, a1: u64): u64;
    #[native_interface]
    native public fun get_share_amount_from_borrow_amount(a0: &mut reserve_details::ReserveDetails, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun get_underlying_amount_from_lp_amount(a0: &mut reserve_details::ReserveDetails, a1: u64): u64;
    #[native_interface]
    native public fun get_underlying_amount_from_lp_amount_frac(a0: &mut reserve_details::ReserveDetails, a1: u64): decimal::Decimal;
    #[native_interface]
    native public fun initial_exchange_rate(a0: &reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun interest_accrue_timestamp(a0: &reserve_details::ReserveDetails): u64;
    #[native_interface]
    native public fun interest_rate_config(a0: &reserve_details::ReserveDetails): interest_rate_config::InterestRateConfig;
    #[native_interface]
    native public fun mint(a0: &mut reserve_details::ReserveDetails, a1: u64): u64;
    #[native_interface]
    native public fun new(a0: u128, a1: u128, a2: decimal::Decimal, a3: decimal::Decimal, a4: decimal::Decimal, a5: decimal::Decimal, a6: u64, a7: reserve_config::ReserveConfig, a8: interest_rate_config::InterestRateConfig): reserve_details::ReserveDetails;
    #[native_interface]
    native public fun new_fresh(a0: decimal::Decimal, a1: reserve_config::ReserveConfig, a2: interest_rate_config::InterestRateConfig): reserve_details::ReserveDetails;
    #[native_interface]
    native public fun redeem(a0: &mut reserve_details::ReserveDetails, a1: u64): u64;
    #[native_interface]
    native public fun repay(a0: &mut reserve_details::ReserveDetails, a1: u64): (u64, decimal::Decimal);
    #[native_interface]
    native public fun reserve_amount(a0: &mut reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun reserve_amount_raw(a0: &reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun reserve_config(a0: &reserve_details::ReserveDetails): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun set_total_cash_available(a0: &mut reserve_details::ReserveDetails, a1: u128);
    #[native_interface]
    native public fun total_borrow_amount(a0: &mut reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun total_borrowed(a0: &reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun total_borrowed_share(a0: &reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun total_cash_available(a0: &reserve_details::ReserveDetails): u128;
    #[native_interface]
    native public fun total_lp_supply(a0: &reserve_details::ReserveDetails): u128;
    #[native_interface]
    native public fun total_user_liquidity(a0: &mut reserve_details::ReserveDetails): decimal::Decimal;
    #[native_interface]
    native public fun update_interest_rate_config(a0: &mut reserve_details::ReserveDetails, a1: interest_rate_config::InterestRateConfig);
    #[native_interface]
    native public fun update_reserve_config(a0: &mut reserve_details::ReserveDetails, a1: reserve_config::ReserveConfig);
    #[native_interface]
    native public fun withdraw_reserve_amount(a0: &mut reserve_details::ReserveDetails): u64;

}

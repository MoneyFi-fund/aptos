module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::interest_rate_config {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::interest_rate_config;

    struct InterestRateConfig has copy, drop, store {
        min_borrow_rate: u64,
        optimal_borrow_rate: u64,
        max_borrow_rate: u64,
        optimal_utilization: u64,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun default_config(): interest_rate_config::InterestRateConfig;
    #[native_interface]
    native public fun get_borrow_rate(a0: &interest_rate_config::InterestRateConfig, a1: decimal::Decimal, a2: u128, a3: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun get_borrow_rate_for_seconds(a0: u64, a1: &interest_rate_config::InterestRateConfig, a2: decimal::Decimal, a3: u128, a4: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun max_borrow_rate(a0: &interest_rate_config::InterestRateConfig): u64;
    #[native_interface]
    native public fun min_borrow_rate(a0: &interest_rate_config::InterestRateConfig): u64;
    #[native_interface]
    native public fun new_interest_rate_config(a0: u64, a1: u64, a2: u64, a3: u64): interest_rate_config::InterestRateConfig;
    #[native_interface]
    native public fun optimal_borrow_rate(a0: &interest_rate_config::InterestRateConfig): u64;
    #[native_interface]
    native public fun optimal_utilization(a0: &interest_rate_config::InterestRateConfig): u64;
    #[native_interface]
    native public fun update_max_borrow_rate(a0: &interest_rate_config::InterestRateConfig, a1: u64): interest_rate_config::InterestRateConfig;
    #[native_interface]
    native public fun update_min_borrow_rate(a0: &interest_rate_config::InterestRateConfig, a1: u64): interest_rate_config::InterestRateConfig;
    #[native_interface]
    native public fun update_optimal_borrow_rate(a0: &interest_rate_config::InterestRateConfig, a1: u64): interest_rate_config::InterestRateConfig;
    #[native_interface]
    native public fun update_optimal_utilization(a0: &interest_rate_config::InterestRateConfig, a1: u64): interest_rate_config::InterestRateConfig;

}

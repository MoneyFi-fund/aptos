module aries::profile {
    use std::option;
    use std::string;
    use aptos_std::type_info;

    use decimal::decimal;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun asset_price(
        a0: &option::Option<string::String>, a1: &type_info::TypeInfo
    ): decimal::Decimal;
    #[native_interface]
    native public fun available_borrowing_power(
        a0: address, a1: &string::String
    ): decimal::Decimal;

    public fun claimable_reward_amount_on_farming<T0>(
        a0: address, a1: string::String
    ): (vector<type_info::TypeInfo>, vector<u64>) {
        (vector[], vector[])
    }

    #[native_interface]
    native public fun get_adjusted_borrowed_value(
        a0: address, a1: &string::String
    ): decimal::Decimal;
    #[native_interface]
    native public fun get_borrowed_amount(
        a0: address, a1: &string::String, a2: type_info::TypeInfo
    ): decimal::Decimal;

    public fun get_deposited_amount(
        a0: address, a1: &string::String, a2: type_info::TypeInfo
    ): u64 {
        // std::debug::print(&b"get_deposited_amount");
        aries::mock::get_call_data(b"profile::get_deposited_amount", 0)
    }

    public fun get_profile_address(a0: address, a1: string::String): address {
        aries::mock::get_call_data(b"profile::get_profile_address", a0)
    }

    public fun init_with_referrer(a0: &signer, a1: address) {}

    public fun is_registered(a0: address): bool {
        aries::mock::get_call_data(b"profile::is_registered", false)
    }

    #[native_interface]
    native public fun max_borrow_amount(
        a0: address, a1: &string::String, a2: type_info::TypeInfo
    ): u64;

    public fun new(a0: &signer, a1: string::String) {}

    public fun profile_exists(a0: address, a1: string::String): bool {
        aries::mock::get_call_data(b"profile::profile_exists", false)
    }

    public fun profile_loan<T0>(a0: address, a1: string::String): (u128, u128) {
        (0, 0)
    }
}

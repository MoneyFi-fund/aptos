module aries::profile {
    use std::option;
    use std::string;
    use aptos_std::type_info;

    use aries::decimal;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun asset_price(
        a0: &option::Option<string::String>, a1: &type_info::TypeInfo
    ): decimal::Decimal;
    #[native_interface]
    native public fun available_borrowing_power(
        a0: address, a1: &string::String
    ): decimal::Decimal;
    #[native_interface]
    native public fun claimable_reward_amount_on_farming<T0>(
        a0: address, a1: string::String
    ): (vector<type_info::TypeInfo>, vector<u64>);
    #[native_interface]
    native public fun get_adjusted_borrowed_value(
        a0: address, a1: &string::String
    ): decimal::Decimal;
    #[native_interface]
    native public fun get_borrowed_amount(
        a0: address, a1: &string::String, a2: type_info::TypeInfo
    ): decimal::Decimal;
    #[native_interface]
    native public fun get_deposited_amount(
        a0: address, a1: &string::String, a2: type_info::TypeInfo
    ): u64;
    #[native_interface]
    native public fun get_profile_address(a0: address, a1: string::String): address;
    #[native_interface]
    native public fun init_with_referrer(a0: &signer, a1: address);
    #[native_interface]
    native public fun is_registered(a0: address): bool;
    #[native_interface]
    native public fun max_borrow_amount(
        a0: address, a1: &string::String, a2: type_info::TypeInfo
    ): u64;
    #[native_interface]
    native public fun new(a0: &signer, a1: string::String);
    #[native_interface]
    native public fun profile_exists(a0: address, a1: string::String): bool;
    #[native_interface]
    native public fun profile_loan<T0>(a0: address, a1: string::String): (u128, u128);
}

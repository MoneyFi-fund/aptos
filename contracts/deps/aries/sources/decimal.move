module aries::decimal {
    struct Decimal has copy, drop, store {
        val: u128
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun as_u64(a0: Decimal): u64;
    #[native_interface]
    native public fun ceil_u64(a0: Decimal): u64;
    #[native_interface]
    native public fun div(a0: Decimal, a1: Decimal): Decimal;
    #[native_interface]
    native public fun from_scaled_val(a0: u128): Decimal;
    #[native_interface]
    native public fun from_u64(a0: u64): Decimal;
    #[native_interface]
    native public fun raw(a0: Decimal): u128;
}

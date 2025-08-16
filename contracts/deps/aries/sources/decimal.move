module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;

    struct Decimal has copy, drop, store {
        val: u128,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun add(a0: decimal::Decimal, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun as_percentage(a0: decimal::Decimal): u128;
    #[native_interface]
    native public fun as_u128(a0: decimal::Decimal): u128;
    #[native_interface]
    native public fun as_u64(a0: decimal::Decimal): u64;
    #[native_interface]
    native public fun ceil(a0: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun ceil_u64(a0: decimal::Decimal): u64;
    #[native_interface]
    native public fun div(a0: decimal::Decimal, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun div_u128(a0: decimal::Decimal, a1: u128): decimal::Decimal;
    #[native_interface]
    native public fun div_u64(a0: decimal::Decimal, a1: u64): decimal::Decimal;
    #[native_interface]
    native public fun eq(a0: decimal::Decimal, a1: decimal::Decimal): bool;
    #[native_interface]
    native public fun floor(a0: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun floor_u64(a0: decimal::Decimal): u64;
    #[native_interface]
    native public fun from_bips(a0: u128): decimal::Decimal;
    #[native_interface]
    native public fun from_millionth(a0: u128): decimal::Decimal;
    #[native_interface]
    native public fun from_percentage(a0: u128): decimal::Decimal;
    #[native_interface]
    native public fun from_scaled_val(a0: u128): decimal::Decimal;
    #[native_interface]
    native public fun from_u128(a0: u128): decimal::Decimal;
    #[native_interface]
    native public fun from_u64(a0: u64): decimal::Decimal;
    #[native_interface]
    native public fun from_u8(a0: u8): decimal::Decimal;
    #[native_interface]
    native public fun gt(a0: decimal::Decimal, a1: decimal::Decimal): bool;
    #[native_interface]
    native public fun gte(a0: decimal::Decimal, a1: decimal::Decimal): bool;
    #[native_interface]
    native public fun half(): decimal::Decimal;
    #[native_interface]
    native public fun hundredth(): decimal::Decimal;
    #[native_interface]
    native public fun lt(a0: decimal::Decimal, a1: decimal::Decimal): bool;
    #[native_interface]
    native public fun lte(a0: decimal::Decimal, a1: decimal::Decimal): bool;
    #[native_interface]
    native public fun max(a0: decimal::Decimal, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun min(a0: decimal::Decimal, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun mul(a0: decimal::Decimal, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun mul_div(a0: decimal::Decimal, a1: decimal::Decimal, a2: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun mul_u128(a0: decimal::Decimal, a1: u128): decimal::Decimal;
    #[native_interface]
    native public fun mul_u64(a0: decimal::Decimal, a1: u64): decimal::Decimal;
    #[native_interface]
    native public fun one(): decimal::Decimal;
    #[native_interface]
    native public fun raw(a0: decimal::Decimal): u128;
    #[native_interface]
    native public fun round(a0: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun round_u64(a0: decimal::Decimal): u64;
    #[native_interface]
    native public fun scaling_factor(): u128;
    #[native_interface]
    native public fun sub(a0: decimal::Decimal, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun tenth(): decimal::Decimal;
    #[native_interface]
    native public fun zero(): decimal::Decimal;

}

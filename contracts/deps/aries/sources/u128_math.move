module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::u128_math {

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun ascending_u128(a0: u128, a1: u128): (u128, u128);
    #[native_interface]
    native public fun bits_u128(a0: u128): u8;
    #[native_interface]
    native public fun leading_zeros_u128(a0: u128): u8;
    #[native_interface]
    native public fun mul_div_u128(a0: u128, a1: u128, a2: u128): u128;
    #[native_interface]
    native public fun tailing_zeros_u128(a0: u128): u8;

}

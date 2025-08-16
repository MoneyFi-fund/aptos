module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::math_utils {

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun mul_millionth_u64(a0: u64, a1: u64): u64;
    #[native_interface]
    native public fun mul_percentage_u64(a0: u64, a1: u64): u64;
    #[native_interface]
    native public fun u64_max(): u64;

}

module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::uint {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::uint;

    struct Uint has copy, drop, store {
        ret: vector<u64>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun add(a0: uint::Uint, a1: uint::Uint): uint::Uint;
    #[native_interface]
    native public fun as_u128(a0: uint::Uint): u128;
    #[native_interface]
    native public fun compare(a0: &uint::Uint, a1: &uint::Uint): u8;
    #[native_interface]
    native public fun div(a0: uint::Uint, a1: uint::Uint): uint::Uint;
    #[native_interface]
    native public fun from_u128(a0: u128): uint::Uint;
    #[native_interface]
    native public fun from_u64(a0: u64): uint::Uint;
    #[native_interface]
    native public fun from_u8(a0: u8): uint::Uint;
    #[native_interface]
    native public fun mod(a0: uint::Uint, a1: uint::Uint): uint::Uint;
    #[native_interface]
    native public fun mul(a0: uint::Uint, a1: uint::Uint): uint::Uint;
    #[native_interface]
    native public fun sub(a0: uint::Uint, a1: uint::Uint): uint::Uint;
    #[native_interface]
    native public fun zero(): uint::Uint;

}

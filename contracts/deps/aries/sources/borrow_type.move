module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::borrow_type {

    use 0x1::string;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun borrow_type_str(a0: u8): string::String;
    #[native_interface]
    native public fun flash_borrow_type(): u8;
    #[native_interface]
    native public fun flash_borrow_type_str(): string::String;
    #[native_interface]
    native public fun normal_borrow_type(): u8;
    #[native_interface]
    native public fun normal_borrow_type_str(): string::String;

}

module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::utils {

    use 0x1::coin;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun burn_coin<T0>(a0: coin::Coin<T0>, a1: &coin::BurnCapability<T0>);
    #[native_interface]
    native public fun can_receive_coin<T0>(a0: address): bool;
    #[native_interface]
    native public fun deposit_coin<T0>(a0: &signer, a1: coin::Coin<T0>);
    #[native_interface]
    native public fun type_eq<T0, T1>(): bool;

}

module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::fa_to_coin_wrapper {

    use 0x1::account;
    use 0x1::coin;
    use 0x1::fungible_asset;
    use 0x1::object;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller;

    friend controller;

    struct FASigner has store, key {
        addr: address,
        cap: account::SignerCapability,
    }
    struct WrappedUSDT {
        dummy_field: bool,
    }
    struct WrapperCoinInfo<phantom T0> has key {
        mint_capability: coin::MintCapability<T0>,
        burn_capability: coin::BurnCapability<T0>,
        freeze_capability: coin::FreezeCapability<T0>,
        metadata: object::Object<fungible_asset::Metadata>,
        fa_amount: u64,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun add_fa<T0>(a0: &signer, a1: object::Object<fungible_asset::Metadata>);
    #[native_interface]
    native public fun coin_to_fa<T0>(a0: coin::Coin<T0>, a1: &signer);
    #[native_interface]
    native public fun fa_to_coin<T0>(a0: &signer, a1: u64): coin::Coin<T0>;
    #[native_interface]
    native public(friend) fun init(a0: &signer);
    #[native_interface]
    native public fun is_fa_wrapped_coin<T0>(): bool;
    #[native_interface]
    native public fun wrapped_amount<T0>(): u64;

}

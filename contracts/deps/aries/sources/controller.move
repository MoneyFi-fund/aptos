module aries::controller {
    use std::string;
    use std::signer;
    use aptos_std::type_info;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun claim_reward_ti<T0>(
        a0: &signer,
        a1: vector<u8>,
        a2: type_info::TypeInfo,
        a3: type_info::TypeInfo
    );

    public entry fun deposit_fa<T0>(a0: &signer, a1: vector<u8>, a2: u64) {
        let asset = aries::mock::get_call_data<address>(b"controller::deposit_fa", @0xa);
        primary_fungible_store::transfer(
            a0,
            object::address_to_object<Metadata>(asset),
            @aries,
            a2
        );
    }

    #[native_interface]
    native public entry fun enter_emode(
        a0: &signer, a1: string::String, a2: string::String
    );
    #[native_interface]
    native public entry fun exit_emode(a0: &signer, a1: string::String);

    public entry fun withdraw_fa<T0>(
        a0: &signer, a1: vector<u8>, a2: u64, a3: bool
    ) {
        let store_addr =
            aries::mock::get_call_data<address>(b"controller::withdraw_fa:store", @0x0);
        let asset_addr =
            aries::mock::get_call_data<address>(b"controller::withdraw_fa:asset", @0x0);
        let store = object::address_to_object<FungibleStore>(store_addr);
        let asset = object::address_to_object<Metadata>(asset_addr);
        fungible_asset::transfer(
            a0,
            store,
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(a0), asset
            ),
            a2
        );
    }
}

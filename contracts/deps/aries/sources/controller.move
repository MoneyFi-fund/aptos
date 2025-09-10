module aries::controller {
    use std::string;
    use std::signer;
    use aptos_std::type_info;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};

    public fun claim_reward_ti<T0>(
        a0: &signer,
        a1: vector<u8>,
        a2: type_info::TypeInfo,
        a3: type_info::TypeInfo
    ) {
        let amount =
            aries::mock::get_call_data<u64>(b"controller::claim_reward_ti:amount", 0);
        let store_addr =
            aries::mock::get_call_data<address>(
                b"controller::claim_reward_ti:store", @0x0
            );
        let store = object::address_to_object<FungibleStore>(store_addr);
        // std::debug::print(
        //     &aptos_std::string_utils::format1(
        //         &b"controller::claim_reward_ti: {}", amount
        //     )
        // );
        fungible_asset::transfer(
            a0,
            store,
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(a0),
                object::address_to_object<Metadata>(@0xa)
            ),
            amount
        );
    }

    public entry fun deposit_fa<T0>(a0: &signer, a1: vector<u8>, a2: u64) {
        let asset =
            aries::mock::get_call_data<address>(b"controller::deposit_fa:asset", @0xa);
        // let amount = aries::mock::get_call_data<u64>(
        //     b"controller::deposit_fa:amount", 0
        // );
        // assert!(amount == a2);

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
        // std::debug::print(
        //     &aptos_std::string_utils::format2(
        //         &b"controller::withdraw_fa: {}: {}", asset_addr, a2
        //     )
        // );
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

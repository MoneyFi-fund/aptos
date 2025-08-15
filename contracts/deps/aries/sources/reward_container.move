module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reward_container {

    use 0x1::coin;
    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::map;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::pair;

    friend controller;

    struct RewardContainer<phantom T0> has key {
        rewards: map::Map<pair::Pair<type_info::TypeInfo, type_info::TypeInfo>, coin::Coin<T0>>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun add_reward<T0, T1, T2>(a0: coin::Coin<T2>);
    #[native_interface]
    native public fun exists_container<T0>(): bool;
    #[native_interface]
    native public fun has_reward<T0, T1, T2>(): bool;
    #[native_interface]
    native public(friend) fun init_container<T0>(a0: &signer);
    #[native_interface]
    native public fun remaining_reward<T0, T1, T2>(): u64;
    #[native_interface]
    native public(friend) fun remove_reward<T0, T1, T2>(a0: u64): coin::Coin<T2>;
    #[native_interface]
    native public(friend) fun remove_reward_ti<T0>(a0: type_info::TypeInfo, a1: type_info::TypeInfo, a2: u64): coin::Coin<T0>;

}

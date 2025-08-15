module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_farm {

    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::iterable_table;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::map;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_farm;

    friend reserve;

    struct ReserveFarm has store {
        timestamp: u64,
        share: u128,
        rewards: iterable_table::IterableTable<type_info::TypeInfo, reserve_farm::Reward>,
    }
    struct ReserveFarmRaw has copy, drop, store {
        timestamp: u64,
        share: u128,
        reward_types: vector<type_info::TypeInfo>,
        rewards: vector<reserve_farm::RewardRaw>,
    }
    struct Reward has copy, drop, store {
        reward_config: reserve_farm::RewardConfig,
        remaining_reward: u128,
        reward_per_share: decimal::Decimal,
    }
    struct RewardConfig has copy, drop, store {
        reward_per_day: u128,
    }
    struct RewardRaw has copy, drop, store {
        reward_per_day: u128,
        remaining_reward: u128,
        reward_per_share_decimal: u128,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun add_reward(a0: &mut reserve_farm::ReserveFarm, a1: type_info::TypeInfo, a2: u128);
    #[native_interface]
    native public fun add_share(a0: &mut reserve_farm::ReserveFarm, a1: u128);
    #[native_interface]
    native public fun borrow_reward(a0: &reserve_farm::ReserveFarm, a1: type_info::TypeInfo): &reserve_farm::Reward;
    #[native_interface]
    native public(friend) fun get_latest_reserve_farm_view(a0: &reserve_farm::ReserveFarm): map::Map<type_info::TypeInfo, reserve_farm::Reward>;
    #[native_interface]
    native public(friend) fun get_latest_reserve_reward_view(a0: &reserve_farm::ReserveFarm, a1: type_info::TypeInfo): reserve_farm::Reward;
    #[native_interface]
    native public fun get_reward_per_day(a0: &reserve_farm::ReserveFarm, a1: type_info::TypeInfo): u128;
    #[native_interface]
    native public fun get_reward_per_share(a0: &reserve_farm::ReserveFarm, a1: type_info::TypeInfo): decimal::Decimal;
    #[native_interface]
    native public fun get_reward_remaining(a0: &reserve_farm::ReserveFarm, a1: type_info::TypeInfo): u128;
    #[native_interface]
    native public fun get_rewards(a0: &mut reserve_farm::ReserveFarm): map::Map<type_info::TypeInfo, reserve_farm::Reward>;
    #[native_interface]
    native public fun get_share(a0: &reserve_farm::ReserveFarm): u128;
    #[native_interface]
    native public fun get_timestamp(a0: &reserve_farm::ReserveFarm): u64;
    #[native_interface]
    native public fun has_reward(a0: &reserve_farm::ReserveFarm, a1: type_info::TypeInfo): bool;
    #[native_interface]
    native public fun new(): reserve_farm::ReserveFarm;
    #[native_interface]
    native public fun new_reward(): reserve_farm::Reward;
    #[native_interface]
    native public fun new_reward_config(a0: u128): reserve_farm::RewardConfig;
    #[native_interface]
    native public fun remaining_reward(a0: &reserve_farm::Reward): u128;
    #[native_interface]
    native public fun remove_reward(a0: &mut reserve_farm::ReserveFarm, a1: type_info::TypeInfo, a2: u128);
    #[native_interface]
    native public fun remove_share(a0: &mut reserve_farm::ReserveFarm, a1: u128);
    #[native_interface]
    native public fun reserve_farm_raw(a0: &reserve_farm::ReserveFarm): reserve_farm::ReserveFarmRaw;
    #[native_interface]
    native public fun reward_per_day(a0: &reserve_farm::Reward): u128;
    #[native_interface]
    native public fun reward_per_share(a0: &reserve_farm::Reward): decimal::Decimal;
    #[native_interface]
    native public fun self_update(a0: &mut reserve_farm::ReserveFarm);
    #[native_interface]
    native public fun unwrap_reserve_farm_raw(a0: reserve_farm::ReserveFarmRaw): (u64, u128, vector<type_info::TypeInfo>, vector<reserve_farm::RewardRaw>);
    #[native_interface]
    native public fun unwrap_reserve_reward_raw(a0: reserve_farm::RewardRaw): (u128, u128, u128);
    #[native_interface]
    native public fun update_reward_config(a0: &mut reserve_farm::ReserveFarm, a1: type_info::TypeInfo, a2: reserve_farm::RewardConfig);

}

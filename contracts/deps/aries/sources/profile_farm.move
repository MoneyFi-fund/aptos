module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile_farm {

    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::iterable_table;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::map;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile_farm;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_farm;

    friend profile;

    struct ProfileFarm has store {
        share: u128,
        rewards: iterable_table::IterableTable<type_info::TypeInfo, profile_farm::Reward>,
    }
    struct ProfileFarmRaw has copy, drop, store {
        share: u128,
        reward_type: vector<type_info::TypeInfo>,
        rewards: vector<profile_farm::RewardRaw>,
    }
    struct Reward has drop, store {
        unclaimed_amount: decimal::Decimal,
        last_reward_per_share: decimal::Decimal,
    }
    struct RewardRaw has copy, drop, store {
        unclaimed_amount_decimal: u128,
        last_reward_per_share_decimal: u128,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun accumulate_profile_farm_raw(a0: &mut profile_farm::ProfileFarmRaw, a1: &map::Map<type_info::TypeInfo, reserve_farm::Reward>);
    #[native_interface]
    native public(friend) fun accumulate_profile_reward_raw(a0: &mut profile_farm::RewardRaw, a1: u128, a2: decimal::Decimal);
    #[native_interface]
    native public fun add_share(a0: &mut profile_farm::ProfileFarm, a1: &map::Map<type_info::TypeInfo, reserve_farm::Reward>, a2: u128);
    #[native_interface]
    native public fun aggregate_all_claimable_rewards(a0: &profile_farm::ProfileFarm, a1: &mut map::Map<type_info::TypeInfo, u64>);
    #[native_interface]
    native public fun claim_reward(a0: &mut profile_farm::ProfileFarm, a1: &map::Map<type_info::TypeInfo, reserve_farm::Reward>, a2: type_info::TypeInfo): u64;
    #[native_interface]
    native public fun get_all_claimable_rewards(a0: &profile_farm::ProfileFarm): map::Map<type_info::TypeInfo, u64>;
    #[native_interface]
    native public fun get_claimable_amount(a0: &profile_farm::ProfileFarm, a1: type_info::TypeInfo): u64;
    #[native_interface]
    native public fun get_reward_balance(a0: &profile_farm::ProfileFarm, a1: type_info::TypeInfo): decimal::Decimal;
    #[native_interface]
    native public fun get_reward_detail(a0: &profile_farm::ProfileFarm, a1: type_info::TypeInfo): (decimal::Decimal, decimal::Decimal);
    #[native_interface]
    native public fun get_share(a0: &profile_farm::ProfileFarm): u128;
    #[native_interface]
    native public fun has_reward(a0: &profile_farm::ProfileFarm, a1: type_info::TypeInfo): bool;
    #[native_interface]
    native public fun new(a0: &map::Map<type_info::TypeInfo, reserve_farm::Reward>): profile_farm::ProfileFarm;
    #[native_interface]
    native public fun new_reward(a0: decimal::Decimal): profile_farm::Reward;
    #[native_interface]
    native public fun profile_farm_raw(a0: &profile_farm::ProfileFarm): profile_farm::ProfileFarmRaw;
    #[native_interface]
    native public fun profile_farm_reward_raw(a0: &profile_farm::ProfileFarm, a1: type_info::TypeInfo): profile_farm::RewardRaw;
    #[native_interface]
    native public fun try_remove_share(a0: &mut profile_farm::ProfileFarm, a1: &map::Map<type_info::TypeInfo, reserve_farm::Reward>, a2: u128): u128;
    #[native_interface]
    native public fun unwrap_profile_farm_raw(a0: profile_farm::ProfileFarmRaw): (u128, vector<type_info::TypeInfo>, vector<profile_farm::RewardRaw>);
    #[native_interface]
    native public fun unwrap_profile_reward_raw(a0: profile_farm::RewardRaw): (u128, u128);
    #[native_interface]
    native public fun update(a0: &mut profile_farm::ProfileFarm, a1: &map::Map<type_info::TypeInfo, reserve_farm::Reward>);

}

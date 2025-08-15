module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile {

    use 0x1::account;
    use 0x1::option;
    use 0x1::simple_map;
    use 0x1::string;
    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::iterable_table;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::pair;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile_farm;

    friend controller;

    struct CheckEquity {
        user_addr: address,
        profile_name: string::String,
    }
    struct Deposit has drop, store {
        collateral_amount: u64,
    }
    struct Loan has drop, store {
        borrowed_share: decimal::Decimal,
    }
    struct Profile has key {
        deposited_reserves: iterable_table::IterableTable<type_info::TypeInfo, profile::Deposit>,
        deposit_farms: iterable_table::IterableTable<type_info::TypeInfo, profile_farm::ProfileFarm>,
        borrowed_reserves: iterable_table::IterableTable<type_info::TypeInfo, profile::Loan>,
        borrow_farms: iterable_table::IterableTable<type_info::TypeInfo, profile_farm::ProfileFarm>,
    }
    struct Profiles has key {
        profile_signers: simple_map::SimpleMap<string::String, account::SignerCapability>,
        referrer: option::Option<address>,
    }
    struct SyncProfileBorrowEvent has drop, store {
        user_addr: address,
        profile_name: string::String,
        reserve_type: type_info::TypeInfo,
        borrowed_share_decimal: u128,
        farm: option::Option<profile_farm::ProfileFarmRaw>,
    }
    struct SyncProfileDepositEvent has drop, store {
        user_addr: address,
        profile_name: string::String,
        reserve_type: type_info::TypeInfo,
        collateral_amount: u64,
        farm: option::Option<profile_farm::ProfileFarmRaw>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun add_collateral(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: u64);
    #[native_interface]
    native public(friend) fun asset_borrow_factor(a0: &option::Option<string::String>, a1: &type_info::TypeInfo): u8;
    #[native_interface]
    native public(friend) fun asset_liquidation_bonus_bips(a0: &option::Option<string::String>, a1: &type_info::TypeInfo): u64;
    #[native_interface]
    native public(friend) fun asset_liquidation_threshold(a0: &option::Option<string::String>, a1: &type_info::TypeInfo): u8;
    #[native_interface]
    native public(friend) fun asset_ltv(a0: &option::Option<string::String>, a1: &type_info::TypeInfo): u8;
    #[native_interface]
    native public(friend) fun asset_price(a0: &option::Option<string::String>, a1: &type_info::TypeInfo): decimal::Decimal;
    #[native_interface]
    native public fun available_borrowing_power(a0: address, a1: &string::String): decimal::Decimal;
    #[native_interface]
    native public(friend) fun can_borrow_asset(a0: &option::Option<string::String>, a1: &type_info::TypeInfo): bool;
    #[native_interface]
    native public fun check_enough_collateral(a0: profile::CheckEquity);
    #[native_interface]
    native public(friend) fun claim_reward<T0>(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: type_info::TypeInfo): u64;
    #[native_interface]
    native public(friend) fun claim_reward_ti(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: type_info::TypeInfo, a4: type_info::TypeInfo): u64;
    #[native_interface]
    native public fun claimable_reward_amount_on_farming<T0>(a0: address, a1: string::String): (vector<type_info::TypeInfo>, vector<u64>);
    #[native_interface]
    native public fun claimable_reward_amounts(a0: address, a1: string::String): (vector<type_info::TypeInfo>, vector<u64>);
    #[native_interface]
    native public(friend) fun deposit(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: u64, a4: bool): (u64, u64);
    #[native_interface]
    native public(friend) fun emode_is_matching(a0: &option::Option<string::String>, a1: &option::Option<string::String>): bool;
    #[native_interface]
    native public fun get_adjusted_borrowed_value(a0: address, a1: &string::String): decimal::Decimal;
    #[native_interface]
    native public fun get_borrowed_amount(a0: address, a1: &string::String, a2: type_info::TypeInfo): decimal::Decimal;
    #[native_interface]
    native public fun get_deposited_amount(a0: address, a1: &string::String, a2: type_info::TypeInfo): u64;
    #[native_interface]
    native public fun get_liquidation_borrow_value(a0: &profile::Profile): decimal::Decimal;
    #[native_interface]
    native public(friend) fun get_liquidation_borrow_value_inner(a0: &profile::Profile, a1: &option::Option<string::String>): decimal::Decimal;
    #[native_interface]
    native public fun get_profile_address(a0: address, a1: string::String): address;
    #[native_interface]
    native public fun get_profile_name_str(a0: string::String): string::String;
    #[native_interface]
    native public fun get_total_borrowing_power(a0: address, a1: &string::String): decimal::Decimal;
    #[native_interface]
    native public fun get_total_borrowing_power_from_profile(a0: &profile::Profile): decimal::Decimal;
    #[native_interface]
    native public(friend) fun get_total_borrowing_power_from_profile_inner(a0: &profile::Profile, a1: &option::Option<string::String>): decimal::Decimal;
    #[native_interface]
    native public fun get_user_referrer(a0: address): option::Option<address>;
    #[native_interface]
    native public fun has_enough_collateral(a0: address, a1: string::String): bool;
    #[native_interface]
    native public(friend) fun has_enough_collateral_for_profile(a0: &profile::Profile, a1: &option::Option<string::String>): bool;
    #[native_interface]
    native public fun init(a0: &signer);
    #[native_interface]
    native public fun init_with_referrer(a0: &signer, a1: address);
    #[native_interface]
    native public fun is_eligible_for_emode(a0: address, a1: string::String, a2: string::String): (bool, bool, vector<string::String>);
    #[native_interface]
    native public fun is_registered(a0: address): bool;
    #[native_interface]
    native public(friend) fun liquidate(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: type_info::TypeInfo, a4: u64): (u64, u64);
    #[native_interface]
    native public fun list_claimable_reward_of_coin<T0>(a0: address, a1: &string::String): vector<pair::Pair<type_info::TypeInfo, type_info::TypeInfo>>;
    #[native_interface]
    native public fun max_borrow_amount(a0: address, a1: &string::String, a2: type_info::TypeInfo): u64;
    #[native_interface]
    native public fun new(a0: &signer, a1: string::String);
    #[native_interface]
    native public fun profile_deposit<T0>(a0: address, a1: string::String): (u64, u64);
    #[native_interface]
    native public fun profile_exists(a0: address, a1: string::String): bool;
    #[native_interface]
    native public fun profile_farm<T0, T1>(a0: address, a1: string::String): option::Option<profile_farm::ProfileFarmRaw>;
    #[native_interface]
    native public fun profile_farm_coin<T0, T1, T2>(a0: address, a1: string::String): (u128, u128);
    #[native_interface]
    native public fun profile_loan<T0>(a0: address, a1: string::String): (u128, u128);
    #[native_interface]
    native public(friend) fun read_check_equity_data(a0: &profile::CheckEquity): (address, string::String);
    #[native_interface]
    native public(friend) fun remove_collateral(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: u64): profile::CheckEquity;
    #[native_interface]
    native public(friend) fun set_emode(a0: address, a1: &string::String, a2: option::Option<string::String>);
    #[native_interface]
    native public fun try_add_or_init_profile_reward_share<T0>(a0: &mut profile::Profile, a1: type_info::TypeInfo, a2: u128);
    #[native_interface]
    native public fun try_subtract_profile_reward_share<T0>(a0: &mut profile::Profile, a1: type_info::TypeInfo, a2: u128): u128;
    #[native_interface]
    native public(friend) fun withdraw(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: u64, a4: bool): (u64, u64, profile::CheckEquity);
    #[native_interface]
    native public(friend) fun withdraw_flash_loan(a0: address, a1: &string::String, a2: type_info::TypeInfo, a3: u64, a4: bool): (u64, u64, profile::CheckEquity);

}

module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve {

    use 0x1::coin;
    use 0x1::option;
    use 0x1::string;
    use 0x1::table;
    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::interest_rate_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::map;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::pair;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_details;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_farm;

    friend controller;
    friend profile;

    struct DistributeBorrowFeeEvent<phantom T0> has drop, store {
        actual_borrow_amount: u64,
        platform_fee_amount: u64,
        referrer_fee_amount: u64,
        referrer: option::Option<address>,
        borrow_type: string::String,
    }
    struct FeeDisbursement<phantom T0> {
        coin: coin::Coin<T0>,
        receiver: address,
    }
    struct LP<phantom T0> has store {
        dummy_field: bool,
    }
    struct MintLPEvent<phantom T0> has drop, store {
        amount: u64,
        lp_amount: u64,
    }
    struct RedeemLPEvent<phantom T0> has drop, store {
        amount: u64,
        fee_amount: u64,
        lp_amount: u64,
    }
    struct ReserveCoinContainer<phantom T0> has key {
        underlying_coin: coin::Coin<T0>,
        collateralised_lp_coin: coin::Coin<reserve::LP<T0>>,
        mint_capability: coin::MintCapability<reserve::LP<T0>>,
        burn_capability: coin::BurnCapability<reserve::LP<T0>>,
        freeze_capability: coin::FreezeCapability<reserve::LP<T0>>,
        fee: coin::Coin<T0>,
    }
    struct Reserves has key {
        stats: table::Table<type_info::TypeInfo, reserve_details::ReserveDetails>,
        farms: table::Table<pair::Pair<type_info::TypeInfo, type_info::TypeInfo>, reserve_farm::ReserveFarm>,
    }
    struct SyncReserveDetailEvent<phantom T0> has drop, store {
        total_lp_supply: u128,
        total_cash_available: u128,
        initial_exchange_rate_decimal: u128,
        reserve_amount_decimal: u128,
        total_borrowed_share_decimal: u128,
        total_borrowed_decimal: u128,
        interest_accrue_timestamp: u64,
    }
    struct SyncReserveFarmEvent has drop, store {
        reserve_type: type_info::TypeInfo,
        farm_type: type_info::TypeInfo,
        farm: reserve_farm::ReserveFarmRaw,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public(friend) fun add_collateral<T0>(a0: coin::Coin<reserve::LP<T0>>);
    #[native_interface]
    native public(friend) fun add_reward<T0, T1, T2>(a0: u64);
    #[native_interface]
    native public(friend) fun borrow<T0>(a0: u64, a1: option::Option<address>): coin::Coin<T0>;
    #[native_interface]
    native public(friend) fun borrow_factor(a0: type_info::TypeInfo): u8;
    #[native_interface]
    native public fun calculate_borrow_fee_using_borrow_type(a0: type_info::TypeInfo, a1: u64, a2: u8): u64;
    #[native_interface]
    native public fun calculate_repay(a0: type_info::TypeInfo, a1: u64, a2: decimal::Decimal): (u64, decimal::Decimal);
    #[native_interface]
    native public fun charge_liquidation_fee<T0>(a0: coin::Coin<reserve::LP<T0>>): coin::Coin<reserve::LP<T0>>;
    #[native_interface]
    native public fun charge_withdrawal_fee<T0>(a0: coin::Coin<T0>): coin::Coin<T0>;
    #[native_interface]
    native public(friend) fun create<T0>(a0: &signer, a1: decimal::Decimal, a2: reserve_config::ReserveConfig, a3: interest_rate_config::InterestRateConfig);
    #[native_interface]
    native public(friend) fun flash_borrow<T0>(a0: u64, a1: option::Option<address>): coin::Coin<T0>;
    #[native_interface]
    native public fun get_borrow_amount_from_share(a0: type_info::TypeInfo, a1: u64): decimal::Decimal;
    #[native_interface]
    native public fun get_borrow_amount_from_share_dec(a0: type_info::TypeInfo, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun get_lp_amount_from_underlying_amount(a0: type_info::TypeInfo, a1: u64): u64;
    #[native_interface]
    native public fun get_reserve_rewards<T0>(a0: type_info::TypeInfo): map::Map<type_info::TypeInfo, reserve_farm::Reward>;
    #[native_interface]
    native public fun get_reserve_rewards_ti(a0: type_info::TypeInfo, a1: type_info::TypeInfo): map::Map<type_info::TypeInfo, reserve_farm::Reward>;
    #[native_interface]
    native public fun get_share_amount_from_borrow_amount(a0: type_info::TypeInfo, a1: u64): decimal::Decimal;
    #[native_interface]
    native public fun get_share_amount_from_borrow_amount_dec(a0: type_info::TypeInfo, a1: decimal::Decimal): decimal::Decimal;
    #[native_interface]
    native public fun get_underlying_amount_from_lp_amount(a0: type_info::TypeInfo, a1: u64): u64;
    #[native_interface]
    native public(friend) fun init(a0: &signer);
    #[native_interface]
    native public fun liquidation_bonus_bips(a0: type_info::TypeInfo): u64;
    #[native_interface]
    native public fun liquidation_threshold(a0: type_info::TypeInfo): u8;
    #[native_interface]
    native public fun loan_to_value(a0: type_info::TypeInfo): u8;
    #[native_interface]
    native public fun make_symbol_and_name_for_lp_token<T0>(): (string::String, string::String);
    #[native_interface]
    native public fun mint<T0>(a0: coin::Coin<T0>): coin::Coin<reserve::LP<T0>>;
    #[native_interface]
    native public fun redeem<T0>(a0: coin::Coin<reserve::LP<T0>>): coin::Coin<T0>;
    #[native_interface]
    native public(friend) fun remove_collateral<T0>(a0: u64): coin::Coin<reserve::LP<T0>>;
    #[native_interface]
    native public(friend) fun remove_reward<T0, T1, T2>(a0: u64);
    #[native_interface]
    native public(friend) fun remove_reward_ti(a0: type_info::TypeInfo, a1: type_info::TypeInfo, a2: type_info::TypeInfo, a3: u64);
    #[native_interface]
    native public(friend) fun repay<T0>(a0: coin::Coin<T0>): coin::Coin<T0>;
    #[native_interface]
    native public fun reserve_config(a0: type_info::TypeInfo): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun reserve_details(a0: type_info::TypeInfo): reserve_details::ReserveDetails;
    #[native_interface]
    native public fun reserve_farm<T0, T1>(): option::Option<reserve_farm::ReserveFarmRaw>;
    #[native_interface]
    native public fun reserve_farm_coin<T0, T1, T2>(): (u128, u128, u128, u128);
    #[native_interface]
    native public fun reserve_farm_map<T0, T1>(): map::Map<type_info::TypeInfo, reserve_farm::Reward>;
    #[native_interface]
    native public fun reserve_has_farm<T0>(a0: type_info::TypeInfo): bool;
    #[native_interface]
    native public fun reserve_state<T0>(): reserve_details::ReserveDetails;
    #[native_interface]
    native public(friend) fun sync_cash_available<T0>();
    #[native_interface]
    native public(friend) fun try_add_reserve_reward_share<T0>(a0: type_info::TypeInfo, a1: u128);
    #[native_interface]
    native public(friend) fun try_remove_reserve_reward_share<T0>(a0: type_info::TypeInfo, a1: u128);
    #[native_interface]
    native public fun type_info<T0>(): type_info::TypeInfo;
    #[native_interface]
    native public(friend) fun update_interest_rate_config<T0>(a0: interest_rate_config::InterestRateConfig);
    #[native_interface]
    native public(friend) fun update_reserve_config<T0>(a0: reserve_config::ReserveConfig);
    #[native_interface]
    native public(friend) fun update_reward_config<T0, T1, T2>(a0: reserve_farm::RewardConfig);
    #[native_interface]
    native public(friend) fun withdraw_borrow_fee<T0>(): coin::Coin<T0>;
    #[native_interface]
    native public(friend) fun withdraw_reserve_fee<T0>(): coin::Coin<T0>;

}

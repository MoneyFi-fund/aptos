module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::emode_category {

    use 0x1::option;
    use 0x1::simple_map;
    use 0x1::smart_table;
    use 0x1::string;
    use 0x1::table_with_length;
    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::emode_category;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve;

    friend controller;
    friend profile;
    friend reserve;

    struct DummyOracleKey {
        dummy_field: bool,
    }
    struct EMode has copy, drop, store {
        label: string::String,
        oracle_key_type: option::Option<type_info::TypeInfo>,
        loan_to_value: u8,
        liquidation_threshold: u8,
        liquidation_bonus_bips: u64,
    }
    struct EModeCategories has key {
        admin: address,
        categories: simple_map::SimpleMap<string::String, emode_category::EMode>,
        profile_emodes: smart_table::SmartTable<address, string::String>,
        reserve_emodes: table_with_length::TableWithLength<type_info::TypeInfo, string::String>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun emode_categoies_ids(): vector<string::String>;
    #[native_interface]
    native public fun emode_config(a0: string::String): emode_category::EMode;
    #[native_interface]
    native public(friend) fun emode_liquidation_bonus_bips(a0: string::String): u64;
    #[native_interface]
    native public(friend) fun emode_liquidation_threshold(a0: string::String): u8;
    #[native_interface]
    native public(friend) fun emode_loan_to_value(a0: string::String): u8;
    #[native_interface]
    native public(friend) fun emode_oracle_key_type(a0: string::String): option::Option<type_info::TypeInfo>;
    #[native_interface]
    native public(friend) fun extract_emode(a0: emode_category::EMode): (string::String, option::Option<type_info::TypeInfo>, u8, u8, u64);
    #[native_interface]
    native public(friend) fun init(a0: &signer, a1: address);
    #[native_interface]
    native public fun profile_emode(a0: address): option::Option<string::String>;
    #[native_interface]
    native public(friend) fun profile_enter_emode(a0: address, a1: string::String);
    #[native_interface]
    native public(friend) fun profile_exit_emode(a0: address);
    #[native_interface]
    native public fun reserve_emode<T0>(): option::Option<string::String>;
    #[native_interface]
    native public(friend) fun reserve_emode_t(a0: type_info::TypeInfo): option::Option<string::String>;
    #[native_interface]
    native public(friend) fun reserve_enter_emode<T0>(a0: &signer, a1: string::String);
    #[native_interface]
    native public(friend) fun reserve_exit_emode<T0>(a0: &signer);
    #[native_interface]
    native public fun reserve_in_emode<T0>(a0: string::String): bool;
    #[native_interface]
    native public(friend) fun reserve_in_emode_t(a0: &string::String, a1: type_info::TypeInfo): bool;
    #[native_interface]
    native public(friend) fun set_emode_category<T0>(a0: &signer, a1: string::String, a2: string::String, a3: u8, a4: u8, a5: u64);

}

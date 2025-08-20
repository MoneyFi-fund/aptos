module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::oracle {

    use 0x1::option;
    use 0x1::table;
    use 0x1::type_info;
    // use 0x7E783B349D3E89CF5931AF376EBEADBFAB855B3FA239B7ADA8F5A92FBEA6B387::price_identifier;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::decimal;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::oracle;

    struct OracleIndex has key {
        admin: address,
        prices: table::Table<type_info::TypeInfo, oracle::OracleInfo>
    }

    struct OracleInfo has drop, store {
        switchboard: option::Option<oracle::SwitchboardConfig>,
        // pyth: option::Option<oracle::PythConfig>,
        coin_decimals: u8,
        max_deviation: decimal::Decimal,
        default_price: option::Option<decimal::Decimal>
    }

    // struct PythConfig has copy, drop, store {
    //     pyth_id: price_identifier::PriceIdentifier,
    //     max_age: u64,
    //     weight: u64
    // }

    struct SwitchboardConfig has copy, drop, store {
        sb_addr: address,
        max_age: u64,
        weight: u64
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun get_price(a0: type_info::TypeInfo): decimal::Decimal;
    #[native_interface]
    native public fun get_reserve_price<T0>(): decimal::Decimal;
    #[native_interface]
    native public fun init(a0: &signer, a1: address);
    #[native_interface]
    native public fun new_oracle_info(a0: u8, a1: decimal::Decimal): oracle::OracleInfo;
    #[native_interface]
    native public entry fun set_pyth_oracle<T0>(
        a0: &signer,
        a1: vector<u8>,
        a2: u64,
        a3: u64,
        a4: u64
    );
    #[native_interface]
    native public entry fun set_switchboard_oracle<T0>(
        a0: &signer, a1: address, a2: u64, a3: u64, a4: u64
    );
    #[native_interface]
    native public entry fun unset_oracle<T0>(a0: &signer);

}

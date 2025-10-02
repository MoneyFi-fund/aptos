module lending::lending {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_framework::coin;
    use aptos_framework::fungible_asset;
    use aptos_framework::object;

    use fixed_point64::fixed_point64;

    struct Market has key {
        extend_ref: object::ExtendRef,
        asset_name: string::String,
        asset_type: u64,
        asset_mantissa: u64,
        initial_liquidity: u64,
        total_shares: u64,
        total_liability: u64,
        total_reserve: u64,
        total_cash: u64,
        interest_rate_model_type: u64,
        interest_rate_index: fixed_point64::FixedPoint64,
        interest_rate_last_update_seconds: u64,
        collateral_factor_bps: u64,
        efficiency_mode_id: u8,
        paused: bool,
        supply_cap: u64,
        borrow_cap: u64
    }

    struct FungibleAssetInfo has key {
        metadata: object::Object<fungible_asset::Metadata>
    }

    public fun account_borrowable_coins(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_borrowable_coins_given_health_factor(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_borrowing_power(arg0: address): fixed_point64::FixedPoint64 {
        fixed_point64::zero()
    }

    public fun account_coins(arg0: address, arg1: object::Object<Market>): u64 {
        0
    }

    public fun account_collateral_markets(arg0: address): vector<object::Object<Market>> {
        vector::empty<object::Object<Market>>()
    }

    public fun account_lend_value(arg0: address): fixed_point64::FixedPoint64 {
        fixed_point64::zero()
    }

    public fun account_liability(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_liability_markets(arg0: address): vector<object::Object<Market>> {
        vector::empty<object::Object<Market>>()
    }

    public fun account_liability_value(arg0: address): fixed_point64::FixedPoint64 {
        fixed_point64::zero()
    }

    public fun account_liquidation_threshold(arg0: address): fixed_point64::FixedPoint64 {
        fixed_point64::zero()
    }

    public fun account_liquidity(
        arg0: address
    ): (fixed_point64::FixedPoint64, fixed_point64::FixedPoint64) {
        let v0 = account_borrowing_power(arg0);
        let v1 = account_liability_value(arg0);
        (v0, v1)
    }

    public fun account_market_collateral_factor_bps(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_market_liquidation_threshold_bps(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_shares(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_withdrawable_coins(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_withdrawable_coins_rate_limited(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun account_withdrawable_shares(
        arg0: address, arg1: object::Object<Market>
    ): u64 {
        0
    }

    public fun asset_price(arg0: object::Object<Market>): fixed_point64::FixedPoint64 {
        fixed_point64::zero()
    }

    public fun borrow_interest_rate(arg0: object::Object<Market>): fixed_point64::FixedPoint64 {
        fixed_point64::zero()
    }

    public fun coins_to_shares(arg0: object::Object<Market>, arg1: u64): u64 {
        0
    }

    public fun shares_to_coins(arg0: object::Object<Market>, arg1: u64): u64 {
        0
    }

    public fun exchange_rate(arg0: object::Object<Market>): (u64, u64) {
        (0, 0)
    }

    public fun market_asset_mantissa(arg0: object::Object<Market>): u64 {
        0
    }

    public fun market_asset_metadata(
        arg0: object::Object<Market>
    ): object::Object<fungible_asset::Metadata> acquires FungibleAssetInfo, Market {
        let v0 = arg0;
        assert!(
            borrow_global<Market>(object::object_address<Market>(&v0)).asset_type == 301,
            34
        );
        let v1 = arg0;
        borrow_global<FungibleAssetInfo>(object::object_address<Market>(&v1)).metadata
    }

    public fun market_asset_name(arg0: object::Object<Market>): string::String acquires Market {
        let v0 = arg0;
        borrow_global<Market>(object::object_address<Market>(&v0)).asset_name
    }

    public fun market_asset_type(arg0: object::Object<Market>): u64 acquires Market {
        let v0 = arg0;
        borrow_global<Market>(object::object_address<Market>(&v0)).asset_type
    }

    public fun market_is_coin(arg0: object::Object<Market>): bool acquires Market {
        let v0 = arg0;
        borrow_global<Market>(object::object_address<Market>(&v0)).asset_type == 300
    }

    public fun market_is_fa(arg0: object::Object<Market>): bool acquires Market {
        let v0 = arg0;
        borrow_global<Market>(object::object_address<Market>(&v0)).asset_type == 301
    }

    public entry fun user_enter_efficiency_mode(arg0: &signer, arg1: u8) {
        abort(0);
    }
    
    public entry fun user_quit_efficiency_mode(arg0: &signer) {
        abort(0);
    }
}

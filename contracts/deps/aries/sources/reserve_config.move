module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_config {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_config;

    struct BorrowFarming {
        dummy_field: bool,
    }
    struct DepositFarming {
        dummy_field: bool,
    }
    struct ReserveConfig has copy, drop, store {
        loan_to_value: u8,
        liquidation_threshold: u8,
        liquidation_bonus_bips: u64,
        liquidation_fee_hundredth_bips: u64,
        borrow_factor: u8,
        reserve_ratio: u8,
        borrow_fee_hundredth_bips: u64,
        withdraw_fee_hundredth_bips: u64,
        deposit_limit: u64,
        borrow_limit: u64,
        allow_collateral: bool,
        allow_redeem: bool,
        flash_loan_fee_hundredth_bips: u64,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun allow_collateral(a0: &reserve_config::ReserveConfig): bool;
    #[native_interface]
    native public fun allow_redeem(a0: &reserve_config::ReserveConfig): bool;
    #[native_interface]
    native public fun borrow_factor(a0: &reserve_config::ReserveConfig): u8;
    #[native_interface]
    native public fun borrow_fee_hundredth_bips(a0: &reserve_config::ReserveConfig): u64;
    #[native_interface]
    native public fun borrow_limit(a0: &reserve_config::ReserveConfig): u64;
    #[native_interface]
    native public fun default_config(): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun deposit_limit(a0: &reserve_config::ReserveConfig): u64;
    #[native_interface]
    native public fun flash_loan_fee_hundredth_bips(a0: &reserve_config::ReserveConfig): u64;
    #[native_interface]
    native public fun liquidation_bonus_bips(a0: &reserve_config::ReserveConfig): u64;
    #[native_interface]
    native public fun liquidation_fee_hundredth_bips(a0: &reserve_config::ReserveConfig): u64;
    #[native_interface]
    native public fun liquidation_threshold(a0: &reserve_config::ReserveConfig): u8;
    #[native_interface]
    native public fun loan_to_value(a0: &reserve_config::ReserveConfig): u8;
    #[native_interface]
    native public fun new_reserve_config(a0: u8, a1: u8, a2: u64, a3: u64, a4: u8, a5: u8, a6: u64, a7: u64, a8: u64, a9: u64, a10: bool, a11: bool, a12: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun reserve_ratio(a0: &reserve_config::ReserveConfig): u8;
    #[native_interface]
    native public fun update_allow_collateral(a0: &reserve_config::ReserveConfig, a1: bool): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_allow_redeem(a0: &reserve_config::ReserveConfig, a1: bool): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_borrow_factor(a0: &reserve_config::ReserveConfig, a1: u8): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_borrow_fee_hundredth_bips(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_borrow_limit(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_deposit_limit(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_flash_loan_fee_hundredth_bips(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_liquidation_bonus_bips(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_liquidation_fee_hundredth_bips(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_liquidation_threshold(a0: &reserve_config::ReserveConfig, a1: u8): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_loan_to_value(a0: &reserve_config::ReserveConfig, a1: u8): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_reserve_ratio(a0: &reserve_config::ReserveConfig, a1: u8): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun update_withdraw_fee_hundredth_bips(a0: &reserve_config::ReserveConfig, a1: u64): reserve_config::ReserveConfig;
    #[native_interface]
    native public fun withdraw_fee_hundredth_bips(a0: &reserve_config::ReserveConfig): u64;

}

module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller {

    use 0x1::coin;
    use 0x1::fungible_asset;
    use 0x1::object;
    use 0x1::option;
    use 0x1::string;
    use 0x1::type_info;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::interest_rate_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::profile;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::reserve_farm;

    struct AddLPShareEvent<phantom T0> has drop, store {
        user_addr: address,
        profile_name: string::String,
        lp_amount: u64,
    }
    struct AddReserveEvent<phantom T0> has drop, store {
        signer_addr: address,
        initial_exchange_rate_decimal: u128,
        reserve_conf: reserve_config::ReserveConfig,
        interest_rate_conf: interest_rate_config::InterestRateConfig,
    }
    struct AddRewardEvent<phantom T0, phantom T1, phantom T2> has drop, store {
        signer_addr: address,
        amount: u64,
    }
    struct AddSubaccountEvent has drop, store {
        user_addr: address,
        profile_name: string::String,
    }
    struct BeginFlashLoanEvent<phantom T0> has drop, store {
        user_addr: address,
        profile_name: string::String,
        amount_in: u64,
        withdraw_amount: u64,
        borrow_amount: u64,
    }
    struct ClaimRewardEvent<phantom T0> has drop, store {
        user_addr: address,
        profile_name: string::String,
        reserve_type: type_info::TypeInfo,
        farming_type: type_info::TypeInfo,
        reward_amount: u64,
    }
    struct DepositEvent<phantom T0> has drop, store {
        sender: address,
        receiver: address,
        profile_name: string::String,
        amount_in: u64,
        repay_only: bool,
        repay_amount: u64,
        deposit_amount: u64,
    }
    struct DepositRepayForEvent<phantom T0> has drop, store {
        receiver: address,
        receiver_profile_name: string::String,
        deposit_amount: u64,
        repay_amount: u64,
    }
    struct EModeCategorySet has drop, store {
        signer_addr: address,
        id: string::String,
        label: string::String,
        loan_to_value: u8,
        liquidation_threshold: u8,
        liquidation_bonus_bips: u64,
        oracle_key_type: string::String,
    }
    struct EndFlashLoanEvent<phantom T0> has drop, store {
        user_addr: address,
        profile_name: string::String,
        amount_in: u64,
        repay_amount: u64,
        deposit_amount: u64,
    }
    struct LiquidateEvent<phantom T0, phantom T1> has drop, store {
        liquidator: address,
        liquidatee: address,
        liquidatee_profile_name: string::String,
        repay_amount_in: u64,
        redeem_lp: bool,
        repay_amount: u64,
        withdraw_lp_amount: u64,
        liquidation_fee_amount: u64,
        redeem_lp_amount: u64,
    }
    struct MintLPShareEvent<phantom T0> has drop, store {
        user_addr: address,
        amount: u64,
        lp_amount: u64,
    }
    struct ProfileEModeSet has drop, store {
        user_addr: address,
        profile_name: string::String,
        emode_id: string::String,
    }
    struct RedeemLPShareEvent<phantom T0> has drop, store {
        user_addr: address,
        amount: u64,
        lp_amount: u64,
    }
    struct RegisterUserEvent has drop, store {
        user_addr: address,
        default_profile_name: string::String,
        referrer_addr: option::Option<address>,
    }
    struct RemoveLPShareEvent<phantom T0> has drop, store {
        user_addr: address,
        profile_name: string::String,
        lp_amount: u64,
    }
    struct RemoveRewardEvent<phantom T0, phantom T1, phantom T2> has drop, store {
        signer_addr: address,
        amount: u64,
    }
    struct ReserveEModeSet has drop, store {
        signer_addr: address,
        reserve_str: string::String,
        emode_id: string::String,
    }
    struct SwapEvent<phantom T0, phantom T1> has drop, store {
        sender: address,
        profile_name: string::String,
        amount_in: u64,
        amount_min_out: u64,
        allow_borrow: bool,
        in_withdraw_amount: u64,
        in_borrow_amount: u64,
        out_deposit_amount: u64,
        out_repay_amount: u64,
    }
    struct UpdateInterestRateConfigEvent<phantom T0> has drop, store {
        signer_addr: address,
        config: interest_rate_config::InterestRateConfig,
    }
    struct UpdateReserveConfigEvent<phantom T0> has drop, store {
        signer_addr: address,
        config: reserve_config::ReserveConfig,
    }
    struct UpdateRewardConfigEvent<phantom T0, phantom T1, phantom T2> has drop, store {
        signer_addr: address,
        config: reserve_farm::RewardConfig,
    }
    struct UpsertPrivilegedReferrerConfigEvent has drop, store {
        signer_addr: address,
        claimant_addr: address,
        fee_sharing_percentage: u8,
    }
    struct WithdrawEvent<phantom T0> has drop, store {
        sender: address,
        profile_name: string::String,
        amount_in: u64,
        allow_borrow: bool,
        withdraw_amount: u64,
        borrow_amount: u64,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public entry fun add_collateral<T0>(a0: &signer, a1: vector<u8>, a2: u64);
    #[native_interface]
    native public entry fun add_reserve<T0>(a0: &signer);
    #[native_interface]
    native public entry fun add_reward<T0, T1, T2>(a0: &signer, a1: u64);
    #[native_interface]
    native public entry fun add_subaccount(a0: &signer, a1: vector<u8>);
    #[native_interface]
    native public entry fun admin_sync_available_cash<T0>(a0: &signer);
    #[native_interface]
    native public fun begin_flash_loan<T0>(a0: &signer, a1: string::String, a2: u64): (profile::CheckEquity, coin::Coin<T0>);
    #[native_interface]
    native public entry fun claim_reward<T0, T1, T2>(a0: &signer, a1: vector<u8>);
    #[native_interface]
    native public entry fun claim_reward_for_profile<T0, T1, T2>(a0: &signer, a1: string::String);
    #[native_interface]
    native public fun claim_reward_ti<T0>(a0: &signer, a1: vector<u8>, a2: type_info::TypeInfo, a3: type_info::TypeInfo);
    #[native_interface]
    native public entry fun deposit<T0>(a0: &signer, a1: vector<u8>, a2: u64, a3: bool);
    #[native_interface]
    native public fun deposit_and_repay_for<T0>(a0: address, a1: &string::String, a2: coin::Coin<T0>): (u64, u64);
    #[native_interface]
    native public fun deposit_coin_for<T0>(a0: address, a1: &string::String, a2: coin::Coin<T0>);
    #[native_interface]
    native public entry fun deposit_fa<T0>(a0: &signer, a1: vector<u8>, a2: u64);
    #[native_interface]
    native public fun deposit_for<T0>(a0: &signer, a1: vector<u8>, a2: u64, a3: address, a4: bool);
    #[native_interface]
    native public fun end_flash_loan<T0>(a0: profile::CheckEquity, a1: coin::Coin<T0>);
    #[native_interface]
    native public entry fun enter_emode(a0: &signer, a1: string::String, a2: string::String);
    #[native_interface]
    native public entry fun exit_emode(a0: &signer, a1: string::String);
    #[native_interface]
    native public entry fun hippo_swap<T0, T1, T2, T3, T4, T5, T6>(a0: &signer, a1: vector<u8>, a2: bool, a3: u64, a4: u64, a5: u8, a6: u8, a7: u64, a8: bool, a9: u8, a10: u64, a11: bool, a12: u8, a13: u64, a14: bool);
    #[native_interface]
    native public entry fun init(a0: &signer, a1: address);
    #[native_interface]
    native public entry fun init_emode(a0: &signer);
    #[native_interface]
    native public entry fun init_reward_container<T0>(a0: &signer);
    #[native_interface]
    native public entry fun init_wrapper_coin<T0>(a0: &signer, a1: object::Object<fungible_asset::Metadata>);
    #[native_interface]
    native public entry fun init_wrapper_fa_signer(a0: &signer);
    #[native_interface]
    native public entry fun liquidate<T0, T1>(a0: &signer, a1: address, a2: vector<u8>, a3: u64);
    #[native_interface]
    native public entry fun liquidate_and_redeem<T0, T1>(a0: &signer, a1: address, a2: vector<u8>, a3: u64);
    #[native_interface]
    native public entry fun mint<T0>(a0: &signer, a1: u64);
    #[native_interface]
    native public entry fun redeem<T0>(a0: &signer, a1: u64);
    #[native_interface]
    native public entry fun register_or_update_privileged_referrer(a0: &signer, a1: address, a2: u8);
    #[native_interface]
    native public entry fun register_user(a0: &signer, a1: vector<u8>);
    #[native_interface]
    native public entry fun register_user_with_referrer(a0: &signer, a1: vector<u8>, a2: address);
    #[native_interface]
    native public entry fun remove_collateral<T0>(a0: &signer, a1: vector<u8>, a2: u64);
    #[native_interface]
    native public entry fun remove_reward<T0, T1, T2>(a0: &signer, a1: u64);
    #[native_interface]
    native public entry fun reserve_enter_emode<T0>(a0: &signer, a1: string::String);
    #[native_interface]
    native public entry fun reserve_exit_emode<T0>(a0: &signer);
    #[native_interface]
    native public entry fun set_emode_category<T0>(a0: &signer, a1: string::String, a2: string::String, a3: u8, a4: u8, a5: u64);
    #[native_interface]
    native public entry fun update_interest_rate_config<T0>(a0: &signer, a1: u64, a2: u64, a3: u64, a4: u64);
    #[native_interface]
    native public entry fun update_reserve_config<T0>(a0: &signer, a1: u8, a2: u8, a3: u64, a4: u64, a5: u8, a6: u8, a7: u64, a8: u64, a9: u64, a10: u64, a11: bool, a12: bool, a13: u64);
    #[native_interface]
    native public entry fun update_reward_rate<T0, T1, T2>(a0: &signer, a1: u128);
    #[native_interface]
    native public entry fun withdraw<T0>(a0: &signer, a1: vector<u8>, a2: u64, a3: bool);
    #[native_interface]
    native public entry fun withdraw_borrow_fee<T0>(a0: &signer);
    #[native_interface]
    native public entry fun withdraw_fa<T0>(a0: &signer, a1: vector<u8>, a2: u64, a3: bool);
    #[native_interface]
    native public entry fun withdraw_reserve_fee<T0>(a0: &signer);

}

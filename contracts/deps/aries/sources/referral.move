module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::referral {

    use 0x1::option;
    use 0x1::table_with_length;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller_config;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::referral;

    friend controller_config;

    struct ReferralConfig has copy, drop, store {
        fee_sharing_percentage: u8,
    }
    struct ReferralDetails has store {
        configs: table_with_length::TableWithLength<address, referral::ReferralConfig>,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun fee_sharing_percentage(a0: &referral::ReferralConfig): u8;
    #[native_interface]
    native public fun find_fee_sharing_percentage(a0: &referral::ReferralDetails, a1: address): u8;
    #[native_interface]
    native public fun find_referral_config(a0: &referral::ReferralDetails, a1: address): option::Option<referral::ReferralConfig>;
    #[native_interface]
    native public fun new_referral_details(): referral::ReferralDetails;
    #[native_interface]
    native public(friend) fun register_or_update_privileged_referrer(a0: &mut referral::ReferralDetails, a1: address, a2: u8);

}

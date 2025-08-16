module 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller_config {

    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::controller;
    use 0x9770FA9C725CBD97EB50B2BE5F7416EFDFD1F1554BEB0750D4DAE4C64E860DA3::referral;

    friend controller;

    struct ControllerConfig has key {
        admin: address,
        referral: referral::ReferralDetails,
    }

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun assert_is_admin(a0: address);
    #[native_interface]
    native public fun find_referral_fee_sharing_percentage(a0: address): u8;
    #[native_interface]
    native public(friend) fun init_config(a0: &signer, a1: address);
    #[native_interface]
    native public fun is_admin(a0: address): bool;
    #[native_interface]
    native public(friend) fun register_or_update_privileged_referrer(a0: &signer, a1: address, a2: u8);

}

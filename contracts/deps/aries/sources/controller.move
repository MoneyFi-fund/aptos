module aries::controller {
    use std::string;
    use aptos_std::type_info;

    // NOTE: Functions are 'native' for simplicity. They may or may not be native in actuality.
    #[native_interface]
    native public fun claim_reward_ti<T0>(
        a0: &signer,
        a1: vector<u8>,
        a2: type_info::TypeInfo,
        a3: type_info::TypeInfo
    );
    #[native_interface]
    native public entry fun deposit_fa<T0>(
        a0: &signer, a1: vector<u8>, a2: u64
    );
    #[native_interface]
    native public entry fun enter_emode(
        a0: &signer, a1: string::String, a2: string::String
    );
    #[native_interface]
    native public entry fun exit_emode(a0: &signer, a1: string::String);
    #[native_interface]
    native public entry fun withdraw_fa<T0>(
        a0: &signer, a1: vector<u8>, a2: u64, a3: bool
    );
}

module moneyfi::aries_strategy {
	use std::bcs;
	use std::signer;
	use std::vector;
	use std::string::String;
	use aptos_std::string_utils;
	use aptos_framework::object;

	use aries::profile;

	use moneyfi::access_control;

	const PROFILE_SEED: vector<u8> = b"ARIES_PROFILE";

	struct Profile {
		wallet_id: vector<u8>,
	}

	// -- Entry functions

	public entry fun create_profile_for_wallet(sender: &signer, wallet_id: vector<u8>) {
		assert!(access_control::is_operator(sender));

		// TODO
	}

	public entry fun deposit_for_wallet<Token>(sender: &signer, wallet_id: vector<u8>, amount: u64) {
		assert!(access_control::is_operator(sender));

		// TODO
	}


	public entry fun withdraw_for_wallet<Token>(sender: &signer, wallet_id: vector<u8>, amount: u64) {
		assert!(access_control::is_operator(sender));

		// TODO
	}
	
	// -- View function

	#[view]
	public fun get_profile_object_address(wallet_id: vector<u8>): address {
		object::create_object_address(&@moneyfi, get_profile_object_seed(wallet_id))
	}
 

	//  -- Private functions

	fun get_profile_object_seed(wallet_id: vector<u8>): vector<u8> {
		bcs::to_bytes(&string_utils::format2(&b"{}_{}", PROFILE_SEED, wallet_id))
	}
}
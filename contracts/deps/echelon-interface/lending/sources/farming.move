module lending::farming {
    use std::string;
    use std::signer;
    use aptos_std::string_utils;

    // arg1: asset name
    // arg2: farming identifier
    // return: claimable reward amount
    public fun claimable_reward_amount(
        arg0: address, arg1: 0x1::string::String, arg2: 0x1::string::String
    ): u64 {
        0
    }

    // arg1: reward_id
    public fun farming_identifier(arg0: address, arg1: u64): 0x1::string::String {
        let v0 = 0x1::string_utils::to_string<address>(&arg0);
        0x1::string::append(&mut v0, 0x1::string_utils::to_string<u64>(&arg1));
        v0
    }
}

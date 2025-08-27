module stable::stable {
    struct Position has copy, drop, store {
        index: u64,
        shares: u256
    }

    struct CampaignReward has copy, drop, store {
        token: address,
        amount: u64
    }

    public fun calc_token_amount(
        arg0: address, arg1: vector<u256>, arg2: bool
    ): u256 {
        0
    }

    public fun calculate_pending_rewards(// pool address, position index
        arg0: address, arg1: u64
    ): vector<CampaignReward> {
        vector[]
    }

    public fun campaign_reward_amount(arg0: &CampaignReward): u64 {
        arg0.amount
    }

    public fun campaign_reward_token(arg0: &CampaignReward): address {
        arg0.token
    }
}

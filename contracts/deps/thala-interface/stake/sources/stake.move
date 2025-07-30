module thala_staked_lpt::staked_lpt {
    use std::string;
    use aptos_std::simple_map;
    use aptos_framework::object;
    use aptos_framework::fungible_asset;
    use aptos_framework::function_info;
    use rate_limiter::rate_limiter;
    use masterchef_lib::masterchef;

    struct NewRewardEvent has drop, store {
        reward_id: string::String,
        reward_metadata: object::Object<fungible_asset::Metadata>
    }

    struct StakeEvent has drop, store {
        pool_id: string::String,
        lpt_metadata: object::Object<fungible_asset::Metadata>,
        staked_lpt_metadata: object::Object<fungible_asset::Metadata>,
        amount: u64
    }

    struct UnstakeEvent has drop, store {
        pool_id: string::String,
        lpt_metadata: object::Object<fungible_asset::Metadata>,
        staked_lpt_metadata: object::Object<fungible_asset::Metadata>,
        amount: u64
    }

    struct Farming has key {
        deposit_updating_farming: function_info::FunctionInfo,
        withdraw_updating_farming: function_info::FunctionInfo,
        farming: masterchef::FarmingCore,
        boost_scaling_factor_bps: u64,
        max_boost_multiplier_bps: u64,
        reward_store_extend_ref: object::ExtendRef,
        reward_id_to_reward_metadata: simple_map::SimpleMap<string::String, object::Object<
            fungible_asset::Metadata>>,
        pool_id_to_staked_lpt_metadata: simple_map::SimpleMap<string::String, object::Object<
            fungible_asset::Metadata>>,
        lpt_metadata_to_staked_lpt_metadata: simple_map::SimpleMap<object::Object<
            fungible_asset::Metadata>, object::Object<fungible_asset::Metadata>>,
        stake_paused: bool,
        unstake_paused: bool
    }

    struct Management has key {
        extend_ref: object::ExtendRef,
        mint_ref: fungible_asset::MintRef,
        burn_ref: fungible_asset::BurnRef,
        transfer_ref: fungible_asset::TransferRef,
        lpt_metadata: object::Object<fungible_asset::Metadata>
    }

    struct RateLimitUpdateEvent has drop, store {
        staked_lpt_metadata: object::Object<fungible_asset::Metadata>,
        rate_limit_type: u8,
        window_max_qty: u128,
        window_duration_seconds: u64
    }

    struct RateLimitWhitelist has key {
        whitelisted_users: vector<address>
    }

    struct StakedLPTCreationEvent has drop, store {
        pool_id: string::String,
        lpt_metadata: object::Object<fungible_asset::Metadata>,
        staked_lpt_metadata: object::Object<fungible_asset::Metadata>
    }

    struct StakedLPTParamChangeEvent has drop, store {
        name: string::String,
        prev_value: u64,
        new_value: u64
    }

    struct StakedLptRateLimit has key {
        stake: rate_limiter::RateLimiter,
        unstake: rate_limiter::RateLimiter
    }

    public entry fun stake_entry(
        arg0: &signer, arg1: object::Object<fungible_asset::Metadata>, arg2: u64
    ) {
        abort(0)
    }

    public entry fun claim_reward(
        arg0: &signer,
        arg1: address,
        arg2: object::Object<fungible_asset::Metadata>,
        arg3: string::String
    ) {
        abort(0)
    }

    public entry fun unstake_entry(
        arg0: &signer, arg1: object::Object<fungible_asset::Metadata>, arg2: u64
    ) {
        abort(0)
    }

    public fun claimable_reward(
        arg0: address, arg1: object::Object<fungible_asset::Metadata>, arg2: string::String
    ): u64 {
        0
    }
}

module thala_staked_lpt::staked_lpt {
    use thala_v2_rate_limiter::rate_limiter;
    use thala_v2_famring::masterchef;

    struct NewRewardEvent has drop, store {
        reward_id: 0x1::string::String,
        reward_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
    }
    
    struct StakeEvent has drop, store {
        pool_id: 0x1::string::String,
        lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
        staked_lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
        amount: u64,
    }
    
    struct UnstakeEvent has drop, store {
        pool_id: 0x1::string::String,
        lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
        staked_lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
        amount: u64,
    }
    
    struct Farming has key {
        deposit_updating_farming: 0x1::function_info::FunctionInfo,
        withdraw_updating_farming: 0x1::function_info::FunctionInfo,
        farming: masterchef::FarmingCore,
        boost_scaling_factor_bps: u64,
        max_boost_multiplier_bps: u64,
        reward_store_extend_ref: 0x1::object::ExtendRef,
        reward_id_to_reward_metadata: 0x1::simple_map::SimpleMap<0x1::string::String, 0x1::object::Object<0x1::fungible_asset::Metadata>>,
        pool_id_to_staked_lpt_metadata: 0x1::simple_map::SimpleMap<0x1::string::String, 0x1::object::Object<0x1::fungible_asset::Metadata>>,
        lpt_metadata_to_staked_lpt_metadata: 0x1::simple_map::SimpleMap<0x1::object::Object<0x1::fungible_asset::Metadata>, 0x1::object::Object<0x1::fungible_asset::Metadata>>,
        stake_paused: bool,
        unstake_paused: bool,
    }
    
    struct Management has key {
        extend_ref: 0x1::object::ExtendRef,
        mint_ref: 0x1::fungible_asset::MintRef,
        burn_ref: 0x1::fungible_asset::BurnRef,
        transfer_ref: 0x1::fungible_asset::TransferRef,
        lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
    }
    
    struct RateLimitUpdateEvent has drop, store {
        staked_lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
        rate_limit_type: u8,
        window_max_qty: u128,
        window_duration_seconds: u64,
    }
    
    struct RateLimitWhitelist has key {
        whitelisted_users: vector<address>,
    }
    
    struct StakedLPTCreationEvent has drop, store {
        pool_id: 0x1::string::String,
        lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
        staked_lpt_metadata: 0x1::object::Object<0x1::fungible_asset::Metadata>,
    }
    
    struct StakedLPTParamChangeEvent has drop, store {
        name: 0x1::string::String,
        prev_value: u64,
        new_value: u64,
    }
    
    struct StakedLptRateLimit has key {
        stake: rate_limiter::RateLimiter,
        unstake: rate_limiter::RateLimiter,
    }

    public entry fun stake_entry(arg0: &signer, arg1: 0x1::object::Object<0x1::fungible_asset::Metadata>, arg2: u64) acquires Farming, Management, StakedLptRateLimit {
    }

    public entry fun claim_reward(arg0: &signer, arg1: address, arg2: 0x1::object::Object<0x1::fungible_asset::Metadata>, arg3: 0x1::string::String) acquires Farming {
    }

    public entry fun unstake_entry(arg0: &signer, arg1: 0x1::object::Object<0x1::fungible_asset::Metadata>, arg2: u64) acquires Farming, Management, RateLimitWhitelist, StakedLptRateLimit {
    }

    public fun claimable_reward(arg0: address, arg1: 0x1::object::Object<0x1::fungible_asset::Metadata>, arg2: 0x1::string::String) : u64 acquires Farming {
    }
}
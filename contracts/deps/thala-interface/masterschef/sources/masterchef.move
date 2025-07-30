module thala_masterchef_lib::masterchef {
    use std::string::String;
    use std::simple_map::SimpleMap;
    use std::smart_table::SmartTable;

    struct FarmingCore has key, store {
        retroactive: bool,
        pools: SimpleMap<String, Pool>,
        rewards: SimpleMap<String, Reward>,
        stakers: SmartTable<address, SimpleMap<String, UserPool>>,
    }

     struct Pool has store {
        pool_id: String,
        stake_amount: u64,
        remaining_retroactive_stake: u64,
        rewards: SimpleMap<String, PoolReward>,
    }

     struct Reward has copy, drop, store {
        reward_id: String,
        total_alloc_point: u64,
        epoch_start_sec: u64,
        epoch_end_sec: u64,
        epoch_reward_per_sec: u64,
    }
     struct UserPool has copy, drop, store {
        account_addr: address,
        pool_id: String,
        stake_amount: u64,
        retroactive_stake_amount: u64,
        rewards: SimpleMap<String, UserPoolReward>,
    }

      struct PoolReward has store {
        reward_id: String,
        alloc_point: u64,
        last_rewards_sec: u64,
        acc_rewards_per_share: u256,
    }


    struct UserPoolReward has copy, drop, store {
        reward_id: String,
        last_acc_rewards_per_share: u256,
        reward_amount: u64,
    }
}

use std::str::FromStr;

use aptos_sdk::types::account_config::Object;
use serde::{Deserialize, Serialize};

use crate::{strategy::StrategyID, types::TypeInfo};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct DepositedToStrategyEvent {
    wallet_id: Vec<u8>,
    asset: Object,
    strategy: TypeInfo,
    amount: u64,
    timestamp: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct WithdrawnFromStrategyEvent {
    wallet_id: Vec<u8>,
    asset: Object,
    strategy: TypeInfo,
    amount: u64,
    timestamp: u64,
}

pub trait HasStrategyTypeInfo {
    fn strategy_type_info(&self) -> &TypeInfo;

    fn get_strategy_id(&self) -> Option<StrategyID> {
        StrategyID::from_str(&self.strategy_type_info().module_name.as_str()).ok()
    }
}

impl HasStrategyTypeInfo for DepositedToStrategyEvent {
    fn strategy_type_info(&self) -> &TypeInfo {
        &self.strategy
    }
}

impl HasStrategyTypeInfo for WithdrawnFromStrategyEvent {
    fn strategy_type_info(&self) -> &TypeInfo {
        &self.strategy
    }
}

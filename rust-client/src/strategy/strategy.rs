use std::{str::FromStr, sync::Arc};

use anyhow::{Result, anyhow};
use aptos_sdk::{
    move_types::{
        account_address::AccountAddress, 
    },
    rest_client::aptos_api_types::{
        Address, EntryFunctionId, IdentifierWrapper, MoveModuleId, TransactionInfo, ViewRequest,
    },
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::Client;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub enum StrategyID {
    Hyperion = 1,
    AriesMarket,
    ThalaSwap,
    TappExchange,
}

impl FromStr for StrategyID {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "strategy_hyperion" => Ok(StrategyID::Hyperion),
            "strategy_aries" => Ok(StrategyID::AriesMarket),
            "strategy_thala" => Ok(StrategyID::ThalaSwap),
            "strategy_tapp" => Ok(StrategyID::TappExchange),
            _ => Err(anyhow!("unknown strategy: {}", s)),
        }
    }
}

pub struct AssetState {
    pub pending_amount: u64,
    pub deposited_amount: u64,
    pub est_withdrawable_amount: u64,
}

pub struct StrategyOptions {
    swap_slippage: Option<u64>,
    // TODO: add more opt here
}

#[async_trait]
pub trait Strategy: Send + Sync {
    fn module_name(&self) -> String;
    fn client(&self) -> Arc<Client>;

    /// Deposit fund from wallet account to strategy vault
    async fn deposit(
        &self,
        wallet_id: Vec<u8>,
        asset: AccountAddress,
        amount: u64,
    ) -> Result<TransactionInfo>;

    /// Withdraw fund from strategy vault to wallet account
    async fn withdraw(
        &self,
        wallet_id: Vec<u8>,
        asset: AccountAddress,
        amount: u64,
        gas_fee: u64,
    ) -> Result<TransactionInfo>;

    async fn get_account_state(
        &self,
        wallet_id: Vec<u8>,
        asset: AccountAddress,
    ) -> Result<AssetState>;
}
//
#[async_trait]
pub trait LendingStrategy: Strategy {
    /// Return amount should be repaid
    async fn check_for_repay(&self) -> Result<u64>;

    async fn check_for_borrow(&self) -> Result<u64>;

    async fn loop_borrow(&self, max: u8) -> Result<()> {
        let mut i = 0;
        while i < max {
            let amount = self.check_for_borrow().await?;
            if amount == 0 {
                break;
            }

            self.borrow_and_deposit(amount);

            i+= 1;
        }

        Ok(())
    }

    async fn loop_repay(&self) -> Result<()>;

    async fn get_deposited_amount(&self) -> Result<u64>; 
    async fn get_loan_amount(&self) -> Result<u64>; 

    /// Return deposit APR and reward APR
    async fn get_deposit_apr(&self) -> Result<u64, u64>;

    /// Return borrow APR and reward APR
    async fn get_borrow_apr(&self) -> Result<u64, u64>;

    async fn borrow_and_deposit(&self, amount: u64) -> Result<TransactionInfo>;

    async fn repay(&self, asset: AccountAddress, amount: u64) -> Result<TransactionInfo>;

    async fn get_max_borrow_amount(&self,) -> Result<u64> {
        let client = self.client();

        let data = client
            .aptos_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId {
                        module: MoveModuleId {
                            address: Address::from(client.contract_address),
                            name: IdentifierWrapper::from_str(self.module_name().as_str())?,
                        },
                        name: IdentifierWrapper::from_str("get_max_borrow_amount")?,
                    },
                    type_arguments: vec![],
                    arguments: vec![],
                },
                None,
            )
            .await?
            .into_inner();
        assert!(data.len() == 1);

        let amount = serde_json::from_value::<String>(data[0].clone())?.parse::<u64>()?;

        Ok(amount)
    }
}

#[async_trait]
pub trait DexStrategy: Strategy {
    async fn rebalance(&self, lower_tick: i64, upper_tick: i64) -> Result<TransactionInfo>;
}

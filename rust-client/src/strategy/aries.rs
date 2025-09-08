use std::{str::FromStr, sync::Arc};

use anyhow::Result;
use aptos_sdk::{
    bcs,
    move_types::{
        account_address::AccountAddress, identifier::Identifier, language_storage::ModuleId,
    },
    rest_client::aptos_api_types::{EntryFunctionId, TransactionInfo, ViewRequest},
    types::transaction::EntryFunction,
};
use async_trait::async_trait;

use crate::{
    Client,
    strategy::{AssetState, LendingStrategy, Strategy},
};

const MODULE_NAME: &str = "strategy_aries";

pub struct Aries {
    client: Arc<Client>,
    vault_name: String,
}

impl Aries {
    pub fn new(client: Arc<Client>) -> Self {
        Aries {
            client,
            vault_name: String::new(),
        }
    }

    pub fn with_vault_name(&mut self, vault_name: String) -> &mut Self {
        self.vault_name = vault_name;

        self
    }
}

#[async_trait]
impl Strategy for Aries {
    fn module_name(&self) -> String {
        MODULE_NAME.to_string()
    }

    fn client(&self) -> Arc<Client> {
        self.client.clone()
    }

    async fn deposit(
        &self,
        wallet_id: Vec<u8>,
        asset: AccountAddress,
        amount: u64,
    ) -> Result<TransactionInfo> {
        let efn = EntryFunction::new(
            ModuleId {
                address: self.client.contract_address,
                name: Identifier::from_str(MODULE_NAME)?,
            },
            Identifier::from_str("deposit")?,
            vec![],
            vec![
                bcs::to_bytes(&self.vault_name)?,
                bcs::to_bytes(&wallet_id)?,
                bcs::to_bytes(&asset)?,
                bcs::to_bytes(&amount)?,
            ],
        );

        self.client.send_tx(efn).await
    }

    async fn withdraw(
        &self,
        wallet_id: Vec<u8>,
        asset: AccountAddress,
        amount: u64,
        gas_fee: u64,
    ) -> Result<TransactionInfo> {
        let swap_slippage = 100; // TODO: determine correct value

        let efn = EntryFunction::new(
            ModuleId {
                address: self.client.contract_address,
                name: Identifier::from_str(self.module_name().as_str())?,
            },
            Identifier::from_str("withdraw")?,
            vec![],
            vec![
                bcs::to_bytes(&self.vault_name)?,
                bcs::to_bytes(&wallet_id)?,
                bcs::to_bytes(&asset)?,
                bcs::to_bytes(&amount)?,
                bcs::to_bytes(&gas_fee)?,
                bcs::to_bytes(&swap_slippage)?,
            ],
        );

        self.client.send_tx(efn).await
    }

    async fn get_account_state(
        &self,
        wallet_id: Vec<u8>,
        asset: AccountAddress,
    ) -> Result<AssetState> {
        todo!()
    }
}

#[async_trait]
impl LendingStrategy for Aries {
    async fn borrow_and_deposit(
        &self,
        asset: aptos_sdk::types::PeerId,
        amount: u64,
    ) -> Result<TransactionInfo> {
        todo!()
    }

    // TODO: 
}

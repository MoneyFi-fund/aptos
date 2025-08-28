use std::{str::FromStr, sync::Arc, u64};

use anyhow::{Result, anyhow};
use aptos_sdk::{
    bcs,
    move_types::account_address::AccountAddress,
    rest_client::{
        self,
        aptos_api_types::{EntryFunctionId, TransactionInfo, ViewRequest},
    },
    transaction_builder::TransactionFactory,
    types::{
        LocalAccount,
        chain_id::{ChainId, NamedChain},
        transaction::{EntryFunction, TransactionPayload},
    },
};
use url::Url;

use crate::{
    strategy::{Aries, Strategy, StrategyOptions},
    utils::{get_indexer_api_endpoint, get_rest_api_endpoint},
};

#[derive(Debug)]
pub struct Client {
    pub aptos_client: rest_client::Client,
    pub chain_id: ChainId,
    indexer_url: &'static str,
    pub contract_address: AccountAddress,
    account: Option<LocalAccount>,
}

impl Clone for Client {
    fn clone(&self) -> Self {
        Client {
            aptos_client: self.aptos_client.clone(),
            chain_id: self.chain_id,
            indexer_url: self.indexer_url,
            contract_address: self.contract_address,
            account: None,
        }
    }
}

impl Client {
    pub fn new(network: String, contract_address: String) -> Self {
        let chain = NamedChain::from_str(network.as_str()).unwrap();
        let aptos_client =
            rest_client::Client::new(Url::from_str(get_rest_api_endpoint(chain)).unwrap());

        Client {
            aptos_client,
            chain_id: ChainId::new(chain.id()),
            indexer_url: get_indexer_api_endpoint(chain),
            contract_address: AccountAddress::from_str(contract_address.as_str()).unwrap(),
            account: None,
        }
    }

    pub fn connect(&mut self, private_key: String) -> &Self {
        self.account = Some(LocalAccount::from_private_key(private_key.as_str(), 0).unwrap());
        self
    }

    pub fn strategy_aries(&self) -> Aries {
        Aries::new(Arc::new(self.clone()))
    }

    /// Returns (total_fee, pending_fee)
    pub async fn get_fee(&self, asset: AccountAddress) -> Result<(u64, u64)> {
        let data = self
            .aptos_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::vault::get_fee", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![],
                    arguments: vec![serde_json::to_value(asset)?],
                },
                None,
            )
            .await?
            .into_inner();

        assert!(data.len() == 2);

        let total_fee = serde_json::from_value::<String>(data[0].clone())?.parse::<u64>()?;
        let pending_fee = serde_json::from_value::<String>(data[1].clone())?.parse::<u64>()?;

        Ok((total_fee, pending_fee))
    }

    pub async fn deposit_to_strategy<S: Strategy>(
        &self,
        wallet_id: Vec<u8>,
        strategy: S,
        asset: AccountAddress,
        amount: u64,
    ) -> Result<TransactionInfo> {
        strategy.deposit(wallet_id, asset, amount).await
    }

    pub async fn withdraw_from_strategy<S: Strategy>(
        &self,
        wallet_id: Vec<u8>,
        strategy: S,
        asset: AccountAddress,
        amount: u64,
        gas_fee: u64,
    ) -> Result<TransactionInfo> {
        strategy
            .withdraw(wallet_id, asset, amount, gas_fee)
            .await
    }

    async fn get_sequence_number(&self, addr: AccountAddress) -> Result<u64> {
        let account = self.aptos_client.get_account(addr).await?.into_inner();

        Ok(account.sequence_number)
    }

    pub(crate) async fn send_tx(&self, efn: EntryFunction) -> Result<TransactionInfo> {
        let account = self
            .account
            .as_ref()
            .ok_or_else(|| anyhow!("No account connected"))?;

        let sequence_number = self.get_sequence_number(account.address()).await?;

        let tx = TransactionFactory::new(self.chain_id)
            .payload(TransactionPayload::EntryFunction(efn))
            .sequence_number(sequence_number)
            .sender(account.address())
            // .max_gas_amount(MAX_GAS_AMOUNT)
            .build();

        let signed_txn = tx.sign(account.private_key(), account.public_key().clone())?;
        let pending_txn = self.aptos_client.submit(&signed_txn).await?;
        let tx = self
            .aptos_client
            .wait_for_transaction(&pending_txn.inner())
            .await?;

        Ok(tx.inner().transaction_info().unwrap().clone())
    }
}

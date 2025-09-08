use std::str::FromStr;

use anyhow::{Ok, Result};
use aptos_sdk::{
    bcs,
    crypto::HashValue,
    move_types::{
        account_address::AccountAddress,
        identifier::Identifier,
        language_storage::{ModuleId, StructTag, TypeTag},
        move_resource::MoveStructType,
    },
    rest_client::{
        self,
        aptos_api_types::{
            EntryFunctionId, Event, MoveStructTag, MoveType, TransactionInfo, ViewRequest,
        },
    },
    transaction_builder::TransactionFactory,
    types::{
        LocalAccount,
        chain_id::{ChainId, NamedChain},
        transaction::{EntryFunction, TransactionPayload},
    },
};
use serde::Deserialize;

use crate::types::TypeInfo;

pub struct Client {
    rest_client: rest_client::Client,
}

impl Client {
    pub fn new(rest_client: rest_client::Client) -> Self {
        Client { rest_client }
    }

    pub async fn get_events_from_tx_hash(&self, tx_hash: &str) -> Result<Vec<Event>> {
        let hash = HashValue::from_str(tx_hash)
            .map_err(|e| anyhow::anyhow!("Invalid transaction hash: {:?}", e))?;
        let response = self
            .rest_client
            .get_transaction_by_hash(hash)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to fetch transaction: {:?}", e))?;

        let tx = response.into_inner();
        let events = match tx {
            rest_client::Transaction::UserTransaction(user_tx) => Ok(user_tx.events),
            rest_client::Transaction::GenesisTransaction(genesis_tx) => Ok(genesis_tx.events),
            rest_client::Transaction::BlockMetadataTransaction(_) => Ok(vec![]),
            rest_client::Transaction::PendingTransaction(_) => Ok(vec![]),
            rest_client::Transaction::StateCheckpointTransaction(_) => Ok(vec![]),
            rest_client::Transaction::BlockEpilogueTransaction(_) => Ok(vec![]),
            rest_client::Transaction::ValidatorTransaction(_) => Ok(vec![]),
        }?;

        // Find event with type "7ab5645cb2aaa32df3fba5af90aed73678fe668afdbc8d2a60308ed175b5fe78::x::HiEvent" in list of events
        // This code assumes you want to return the first matching event, or None if not found.
        // If you want all matching events, collect them into a Vec instead.
        // Uncomment and adjust as needed.
        //

        let target_type =
            "0x7ab5645cb2aaa32df3fba5af90aed73678fe668afdbc8d2a60308ed175b5fe78::x::HiEvent";
        let matching_event = events
            .iter()
            .find(|event| dbg!(event.typ.to_string()) == target_type);
        if let Some(event) = matching_event {
            #[derive(Debug, Deserialize)]
            struct Data {
                r#type: TypeInfo,
            }
            let data: Data = serde_json::from_value(event.data.clone())?;
            println!("Deserialized event data: {:?}", data);
        } else {
            println!("No matching event found.");
        };

        Ok(events)
    }
}

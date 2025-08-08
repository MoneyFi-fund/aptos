use std::str::FromStr;

use anyhow::{Ok, Result, anyhow};
use aptos_sdk::move_types::account_address::AccountAddress;
use aptos_sdk::types::chain_id::NamedChain;
use serde_json::Value;

use crate::{TableKey, TableObject};

pub fn get_indexer_api_endpoint(chain: NamedChain) -> &'static str {
    match chain {
        NamedChain::MAINNET => "https://api.mainnet.aptoslabs.com/v1/graphql",
        NamedChain::TESTNET => "https://api.testnet.aptoslabs.com/v1/graphql",
        NamedChain::DEVNET => "https://api.devnet.aptoslabs.com/v1/graphql",
        NamedChain::TESTING => todo!(),
        NamedChain::PREMAINNET => todo!(),
    }
}

pub fn get_rest_api_endpoint(chain: NamedChain) -> &'static str {
    match chain {
        NamedChain::MAINNET => "https://api.mainnet.aptoslabs.com/v1",
        NamedChain::TESTNET => "https://api.testnet.aptoslabs.com/v1",
        NamedChain::DEVNET => "https://api.devnet.aptoslabs.com/v1",
        NamedChain::TESTING => todo!(),
        NamedChain::PREMAINNET => todo!(),
    }
}

pub fn get_contract_address(chain: NamedChain) -> &'static str {
    match chain {
        NamedChain::MAINNET => "0x9770fa9c725cbd97eb50b2be5f7416efdfd1f1554beb0750d4dae4c64e860da3",
        NamedChain::TESTNET => "0xeef200f2a06957a1548685c0feec9f1a04db27598fadab7f6daf30428fd064d3",
        NamedChain::DEVNET => todo!(),
        NamedChain::TESTING => todo!(),
        NamedChain::PREMAINNET => todo!(),
    }
}

pub fn parse_table_data(data: &Value) -> Result<TableObject> {
    let inner = data
        .get("inner")
        .ok_or_else(|| anyhow!("field inner not found"))?;

    let handle = inner
        .get("inner")
        .ok_or_else(|| anyhow!("field inner not found"))?
        .get("handle")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("field handle not found"))?;

    let length: u32 = inner
        .get("length")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("field length not found"))?
        .parse()
        .unwrap_or_default();

    let head: Vec<TableKey> = serde_json::from_value(
        data.get("head")
            .ok_or_else(|| anyhow!("field head not found"))?
            .get("vec")
            .unwrap_or(&Value::Array(vec![]))
            .clone(),
    )?;

    let tail: Vec<TableKey> = serde_json::from_value(
        data.get("tail")
            .ok_or_else(|| anyhow!("field tail not found"))?
            .get("vec")
            .unwrap_or(&Value::Array(vec![]))
            .clone(),
    )?;

    let table = TableObject {
        handle: AccountAddress::from_str(handle)?,
        length,
        head: head.into_iter().next(),
        tail: tail.into_iter().next(),
    };

    Ok(table)
}

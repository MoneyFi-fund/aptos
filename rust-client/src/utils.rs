use aptos_sdk::types::chain_id::NamedChain;
use serde::{Deserialize, Deserializer};

pub fn get_indexer_api_endpoint(chain: NamedChain) -> &'static str {
    match chain {
        NamedChain::MAINNET => "https://api.mainnet.aptoslabs.com/v1/graphql",
        NamedChain::TESTNET => "https://api.testnet.aptoslabs.com/v1/graphql",
        NamedChain::DEVNET => "https://api.devnet.aptoslabs.com/v1/graphql",
        NamedChain::TESTING => "http://127.0.0.1:8080/v1/graphql",
        NamedChain::PREMAINNET => todo!(),
    }
}

pub fn get_rest_api_endpoint(chain: NamedChain) -> &'static str {
    match chain {
        NamedChain::MAINNET => "https://api.mainnet.aptoslabs.com/v1",
        NamedChain::TESTNET => "https://api.testnet.aptoslabs.com/v1",
        NamedChain::DEVNET => "https://api.devnet.aptoslabs.com/v1",
        NamedChain::TESTING => "http://127.0.0.1:8080/v1/",
        NamedChain::PREMAINNET => todo!(),
    }
}

pub fn deserialize_string_from_hexstring<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = <String>::deserialize(deserializer)?;
    Ok(hex_to_string(s.clone()).unwrap_or(s))
}

pub fn hex_to_string(val: String) -> Option<String> {
    let decoded = hex::decode(val.strip_prefix("0x").unwrap_or(&*val)).ok()?;
    String::from_utf8(decoded).ok()
}

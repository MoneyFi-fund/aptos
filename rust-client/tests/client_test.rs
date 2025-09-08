use std::str::FromStr;

use anyhow::Result;
use aptos_sdk::move_types::account_address::AccountAddress;
use aptos_sdk::types::chain_id::NamedChain;
use moneyfi_client::Client;

#[tokio::test]
async fn basic_usage() -> Result<()> {
    // create client
    let mut client = Client::new(
        NamedChain::MAINNET.to_string(),
        "0x97c9ffc7143c5585090f9ade67d19ac95f3b3e7008ed86c73c947637e2862f56".to_string(),
    );

    let usdc = AccountAddress::from_str(
        "0xbae207659db88bea0cbead6da0ed00aac12edcdda169e591cd41c94180b46f3b",
    )?;
    // read data
    let fee_data = client.get_fee(usdc).await?;
    dbg!(fee_data);

    //send tx
    let mut strategy = client.strategy_aries();
    strategy.with_vault_name("USDTVault".to_string());

    client
        .connect("0x1234".to_string())
        .deposit_to_strategy(
            "wallet_1".into(),
            strategy,
            AccountAddress::from_str("0xa")?,
            1000,
        )
        .await?;

    Ok(())
}

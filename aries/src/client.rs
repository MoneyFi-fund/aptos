use std::{collections::HashMap, str::FromStr, u64, vec};

use anyhow::{Ok, Result};
use aptos_sdk::{
    bcs,
    move_types::{
        account_address::AccountAddress,
        identifier::Identifier,
        language_storage::{ModuleId, StructTag, TypeTag},
    },
    rest_client::{
        self,
        aptos_api_types::{EntryFunctionId, MoveStructTag, MoveType, TransactionInfo, ViewRequest},
    },
    transaction_builder::TransactionFactory,
    types::{
        LocalAccount,
        chain_id::{ChainId, NamedChain},
        transaction::{EntryFunction, TransactionPayload},
    },
};
use serde::Deserialize;
use serde_json::Value;
use tokio::runtime::Handle;
use url::Url;

use crate::{types::*, utils::*};

const MAX_GAS_AMOUNT: u64 = 100_000;

pub struct Client {
    rest_client: rest_client::Client,
    wallet: LocalAccount,
    chain_id: ChainId,
    indexer_url: &'static str,
    contract_address: AccountAddress,
}

impl Client {
    pub fn new(network: String, private_key: String) -> Self {
        let chain = NamedChain::from_str(network.as_str()).unwrap();
        let rest_client =
            rest_client::Client::new(Url::from_str(get_rest_api_endpoint(chain)).unwrap());
        let wallet = LocalAccount::from_private_key(&private_key, 0).unwrap();

        Client {
            rest_client,
            wallet,
            chain_id: ChainId::new(chain.id()),
            indexer_url: get_indexer_api_endpoint(chain),
            contract_address: AccountAddress::from_str(get_contract_address(chain)).unwrap(),
        }
    }

    pub async fn get_profile(&self, profile_address: Option<String>) -> Result<Profile> {
        let wallet_addr = self.wallet.address();
        let resp = self
            .rest_client
            .get_account_resource(
                wallet_addr,
                format!("{}::profile::Profiles", self.contract_address).as_str(),
            )
            .await?;
        let res = match resp.inner() {
            Some(r) => r,
            None => return Err(anyhow::anyhow!("Resource not found")),
        };

        #[derive(Debug, Deserialize)]
        struct AccountValue {
            pub account: String,
        }
        #[derive(Debug, Deserialize)]
        struct ProfileValue {
            pub key: String,
            pub value: AccountValue,
        }

        let profiles = serde_json::from_value::<Vec<ProfileValue>>(
            res.data
                .get("profile_signers")
                .and_then(|ps| ps.get("data"))
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("Missing profile_signers.data"))?,
        )?
        .into_iter()
        .map(|v| Profile {
            name: v.key.strip_prefix("profile").unwrap_or(&v.key).to_string(),
            profile_address: AccountAddress::from_str(&v.value.account).unwrap(),
            wallet_address: self.wallet.address(),
            emode: None,
        })
        .collect::<Vec<Profile>>();

        let profile = if let Some(ref addr) = profile_address {
            profiles
                .into_iter()
                .find(|p| p.profile_address.to_string() == *addr)
        } else {
            profiles.into_iter().next()
        };

        if profile.is_none() {
            return Err(anyhow::anyhow!("Profile not found"));
        }

        let mut profile = profile.as_ref().unwrap().clone();
        let emode = self.get_profile_emode(&profile).await?;
        profile.emode = emode;

        Ok(profile)
    }

    async fn get_profile_emode(&self, profile: &Profile) -> Result<Option<String>> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::emode_category::profile_emode", self.contract_address)
                            .as_str(),
                    )?,
                    type_arguments: vec![],
                    arguments: vec![serde_json::to_value(profile.profile_address)?],
                },
                None,
            )
            .await?;

        #[derive(Debug, Deserialize)]
        struct Response {
            pub vec: Vec<String>,
        }

        let res: Response = serde_json::from_value(
            resp.inner()
                .get(0)
                .unwrap_or(&serde_json::Value::String("{}".to_string()))
                .clone(),
        )?;

        Ok(res.vec.get(0).cloned())
    }

    async fn get_reserve_emode(&self, token: &String) -> Result<Option<String>> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::emode_category::reserve_emode", self.contract_address)
                            .as_str(),
                    )?,
                    type_arguments: vec![MoveType::Struct(MoveStructTag::from_str(
                        token.as_str(),
                    )?)],
                    arguments: vec![],
                },
                None,
            )
            .await?;

        #[derive(Debug, Deserialize)]
        struct Response {
            pub vec: Vec<String>,
        }

        let res: Response = serde_json::from_value(
            resp.inner()
                .get(0)
                .unwrap_or(&serde_json::Value::String("{}".to_string()))
                .clone(),
        )?;

        Ok(res.vec.get(0).cloned())
    }

    async fn get_emode_config(&self, emode: &String) -> Result<EmodeConfig> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::emode_category::emode_config", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![],
                    arguments: vec![serde_json::Value::String(emode.clone())],
                },
                None,
            )
            .await?;

        let res: EmodeConfig = serde_json::from_value(
            resp.inner()
                .get(0)
                .ok_or_else(|| anyhow::anyhow!("emode not found"))?
                .clone(),
        )?;

        Ok(res)
    }

    pub async fn get_price(&self, token_address: &String) -> Result<u64> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::oracle::get_reserve_price", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![MoveType::Struct(MoveStructTag::from_str(
                        token_address.as_str(),
                    )?)],
                    arguments: vec![],
                },
                None,
            )
            .await?;

        let price = resp
            .inner()
            .get(0)
            .and_then(|v| v.get("val"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("Invalid price format"))?
            .parse::<u64>()?;

        Ok(price)
    }

    async fn is_wrapped_coin(&self, token_address: &String) -> Result<bool> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!(
                            "{}::fa_to_coin_wrapper::is_fa_wrapped_coin",
                            self.contract_address
                        )
                        .as_str(),
                    )?,
                    type_arguments: vec![MoveType::Struct(MoveStructTag::from_str(
                        token_address.as_str(),
                    )?)],
                    arguments: vec![],
                },
                None,
            )
            .await?;

        let is_wrapped = resp
            .inner()
            .get(0)
            .unwrap_or(&Value::Bool(false))
            .as_bool()
            .unwrap_or(false);

        Ok(is_wrapped)
    }

    pub async fn deposit(
        &self,
        profile: &Profile,
        token: &String,
        amount: u64,
        repay_only: bool,
    ) -> Result<TransactionInfo> {
        let is_wrapped_token = self.is_wrapped_coin(token).await?;
        let mut args = vec![bcs::to_bytes(&profile.name)?, bcs::to_bytes(&amount)?];
        let method = if is_wrapped_token {
            "deposit_fa"
        } else {
            args.push(bcs::to_bytes(&repay_only)?);
            "deposit"
        };

        let token_struct_tag = StructTag::from_str(token.as_str())?;
        let efn = EntryFunction::new(
            ModuleId {
                address: self.contract_address,
                name: Identifier::from_str("controller")?,
            },
            Identifier::from_str(method)?,
            vec![TypeTag::Struct(token_struct_tag.into())],
            args,
        );

        let sequence_number = self.get_sequence_number(self.wallet.address()).await?;

        let tx = TransactionFactory::new(self.chain_id)
            .payload(TransactionPayload::EntryFunction(efn))
            .sequence_number(sequence_number)
            .sender(self.wallet.address())
            .max_gas_amount(MAX_GAS_AMOUNT)
            .build();

        let signed_txn = tx.sign(&self.wallet.private_key(), self.wallet.public_key().clone())?;
        let pending_txn = self.rest_client.submit(&signed_txn).await?;
        let tx = self
            .rest_client
            .wait_for_transaction(&pending_txn.inner())
            .await?;

        Ok(tx.inner().transaction_info().unwrap().clone())
    }

    pub async fn withdraw(
        &self,
        profile: &Profile,
        token: &String,
        amount: u64,
        allow_borrow: bool,
    ) -> Result<TransactionInfo> {
        let is_wrapped_token = self.is_wrapped_coin(token).await?;
        let mut args = vec![bcs::to_bytes(&profile.name)?, bcs::to_bytes(&amount)?];
        let method = if is_wrapped_token {
            "withdraw_fa"
        } else {
            args.push(bcs::to_bytes(&false)?);
            "withdraw"
        };

        let token_struct_tag = StructTag::from_str(token.as_str())?;
        // let amount = if amount > 0 { amount } else { u64::MAX };
        let efn = EntryFunction::new(
            ModuleId {
                address: self.contract_address,
                name: Identifier::from_str("controller")?,
            },
            Identifier::from_str(method)?,
            vec![TypeTag::Struct(token_struct_tag.into())],
            vec![
                bcs::to_bytes(&profile.name)?,
                bcs::to_bytes(&amount)?,
                bcs::to_bytes(&allow_borrow)?,
            ],
        );

        let sequence_number = self.get_sequence_number(self.wallet.address()).await?;

        let tx = TransactionFactory::new(self.chain_id)
            .payload(TransactionPayload::EntryFunction(efn))
            .sequence_number(sequence_number)
            .sender(self.wallet.address())
            .max_gas_amount(MAX_GAS_AMOUNT)
            .build();

        let signed_txn = tx.sign(&self.wallet.private_key(), self.wallet.public_key().clone())?;
        let pending_txn = self.rest_client.submit(&signed_txn).await?;
        let tx = self
            .rest_client
            .wait_for_transaction(&pending_txn.inner())
            .await?;

        Ok(tx.inner().transaction_info().unwrap().clone())
    }

    pub async fn get_deposited_amount(
        &self,
        profile: &Profile,
        token_address: &String,
    ) -> Result<(u64, u64)> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::profile::profile_deposit", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![MoveType::Struct(MoveStructTag::from_str(
                        token_address.as_str(),
                    )?)],
                    arguments: vec![
                        serde_json::to_value(profile.wallet_address)?,
                        serde_json::to_value(profile.name.clone())?,
                    ],
                },
                None,
            )
            .await?;

        let res = resp.inner();
        let collateral: u64 = res.get(0).unwrap().as_str().unwrap().parse()?;
        let underlying: u64 = res.get(1).unwrap().as_str().unwrap().parse()?;

        Ok((collateral, underlying))
    }
    pub async fn get_loan_amount(
        &self,
        profile: &Profile,
        token_address: &String,
    ) -> Result<(u128, u128)> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::profile::profile_loan", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![MoveType::Struct(MoveStructTag::from_str(
                        token_address.as_str(),
                    )?)],
                    arguments: vec![
                        serde_json::to_value(profile.wallet_address)?,
                        serde_json::to_value(profile.name.clone())?,
                    ],
                },
                None,
            )
            .await?;

        let res = resp.inner();
        let borrowed_share: u128 = res.get(0).unwrap().as_str().unwrap().parse()?;
        let borrowed_amount: u128 = res.get(1).unwrap().as_str().unwrap().parse()?;
        let borrowed_share = borrowed_share.div_ceil(10i128.pow(BORROW_DECIMALS) as u128);
        let borrowed_amount = borrowed_amount.div_ceil(10i128.pow(BORROW_DECIMALS) as u128);

        Ok((borrowed_share, borrowed_amount))
    }
    async fn get_sequence_number(&self, account: AccountAddress) -> Result<u64> {
        let resp = self
            .rest_client
            .get_account_resource(account, "0x1::account::Account")
            .await?;

        let res = resp
            .inner()
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Resource not found"))?;
        let n = res
            .data
            .get("sequence_number")
            .ok_or_else(|| anyhow::anyhow!("sequence_number not found"))?
            .as_str()
            .ok_or_else(|| anyhow::anyhow!("sequence_number is not a string"))?
            .parse::<u64>()?;

        Ok(n)
    }

    async fn query_indexer<T>(&self, query: String) -> Result<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let mut map = HashMap::new();
        map.insert("query", query);

        let res = reqwest::Client::new()
            .post(self.indexer_url)
            .json(&map)
            .send()
            .await?;

        let json: serde_json::Value = res.json().await?;
        let data = json.get("data").ok_or_else(|| anyhow::anyhow!("no data"))?;
        let data: T = serde_json::from_value(data.clone())?;

        Ok(data)
    }

    pub async fn get_token_balance(&self, account: AccountAddress, token: &String) -> Result<u64> {
        let query = format!(
            r#"query MyQuery {{
                current_fungible_asset_balances(
                    where: {{owner_address: {{_eq: "{}"}} }}
                ) {{
                    amount
                    asset_type
                    storage_id
                }}
            }}"#,
            account
        );
        #[derive(Debug, Deserialize)]
        struct Asset {
            amount: u64,
            asset_type: String,
            storage_id: String,
        }
        #[derive(Debug, Deserialize)]
        struct Assets {
            current_fungible_asset_balances: Vec<Asset>,
        }
        let assets: Assets = self.query_indexer(query).await?;
        // dbg!(&assets);
        let balance = assets
            .current_fungible_asset_balances
            .iter()
            .find(|asset| asset.asset_type == *token)
            .map(|asset| asset.amount)
            .unwrap_or(0);

        Ok(balance)
    }

    pub async fn get_reserve_detail(&self, token: &String) -> Result<ReserveDetail> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::reserve::reserve_state", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![MoveType::Struct(MoveStructTag::from_str(
                        token.as_str(),
                    )?)],
                    arguments: vec![],
                },
                None,
            )
            .await?;

        let res = resp.inner();

        let mut reserve: ReserveDetail = serde_json::from_value(res.get(0).unwrap().clone())?;
        let emode = self.get_reserve_emode(token).await?;
        reserve.emode = emode;
        reserve.token_address = token.clone();

        Ok(reserve)
    }

    pub async fn get_profile_data(&self, profile: &Profile) -> Result<ProfileData> {
        let resp = self
            .rest_client
            .get_account_resource(
                profile.profile_address,
                format!("{}::profile::Profile", self.contract_address).as_str(),
            )
            .await?;

        let res = resp
            .inner()
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("response not found"))?;

        let borrowed_reserves_table = parse_table_data(
            res.data
                .get("borrowed_reserves")
                .ok_or_else(|| anyhow::anyhow!("field borrowed_reserves not found"))?,
        )?;

        let deposited_reserves_table = parse_table_data(
            res.data
                .get("deposited_reserves")
                .ok_or_else(|| anyhow::anyhow!("field deposited_reserves not found"))?,
        )?;

        Ok(ProfileData {
            borrowed_reserves_table,
            deposited_reserves_table,
        })
    }

    pub async fn get_total_borrow_power(&self, profile: &Profile) -> Result<u128> {
        let profile_data = self.get_profile_data(profile).await?;

        let deposited_reserves_table = profile_data.deposited_reserves_table;
        if deposited_reserves_table.head.is_none() {
            return Ok(0);
        }

        let mut power = 0_u128;

        let mut next = deposited_reserves_table.head.unwrap();
        loop {
            let resp = self.rest_client.get_table_item(
                deposited_reserves_table.handle,
                "0x1::type_info::TypeInfo",
                format!("{}::iterable_table::IterableValue<0x1::type_info::TypeInfo, {}::profile::Deposit>", self.contract_address, self.contract_address).as_str(),
                next.clone(),
            ).await?;

            let reserve = self.get_reseve_detail(&next.decode()).await?;
            let mut ltv = reserve.reserve_config.loan_to_value;
            let emode = profile.emode.clone();
            if emode.eq(&reserve.emode) {
                let emode_config = self.get_emode_config(&emode.unwrap()).await?;
                ltv = emode_config.loan_to_value;
            }
            let price = self.get_price(&reserve.token_address).await?;

            let item = resp.inner();
            let amount: u64 = item
                .get("val")
                .unwrap()
                .get("collateral_amount")
                .unwrap()
                .as_str()
                .unwrap()
                .parse()?;

            power += reserve.lp_to_amount(amount) as u128 * price as u128 * ltv as u128 / 100;

            let keys: Vec<TableKey> =
                serde_json::from_value(item.get("next").unwrap().get("vec").unwrap().clone())?;
            if keys.is_empty() {
                break;
            }

            next = keys.first().unwrap().clone();
        }

        Ok(power)
    }

    pub async fn get_total_borrowed_value(&self, profile: &Profile) -> Result<u128> {
        let profile_data = self.get_profile_data(profile).await?;

        let borrowed_reserves_table = profile_data.borrowed_reserves_table;
        if borrowed_reserves_table.head.is_none() {
            return Ok(0);
        }

        let mut value = 0_u128;

        let mut next = borrowed_reserves_table.head.unwrap();
        loop {
            let resp = self.rest_client.get_table_item(
                borrowed_reserves_table.handle,
                "0x1::type_info::TypeInfo",
                format!("{}::iterable_table::IterableValue<0x1::type_info::TypeInfo, {}::profile::Loan>", self.contract_address, self.contract_address).as_str(),
                next.clone(),
            ).await?;

            let reserve = self.get_reseve_detail(&next.decode()).await?;
            let price = self.get_price(&reserve.token_address).await?;

            let item = resp.inner();
            let shares: u128 = item
                .get("val")
                .unwrap()
                .get("borrowed_share")
                .unwrap()
                .get("val")
                .unwrap()
                .as_str()
                .unwrap()
                .parse()?;

            value += reserve.borrow_share_to_amount(shares) as u128 * price as u128;

            let keys: Vec<TableKey> =
                serde_json::from_value(item.get("next").unwrap().get("vec").unwrap().clone())?;
            if keys.is_empty() {
                break;
            }

            next = keys.first().unwrap().clone();
        }

        Ok(value)
    }

    /// returns `(avail_borrow_amount, borrowed_amount)`
    pub async fn get_available_borrow_amount(
        &self,
        profile: &Profile,
        reserve: &ReserveDetail,
    ) -> Result<(u64, u128)> {
        let (_, borrowed_amount) = self
            .get_loan_amount(&profile, &reserve.token_address)
            .await?;

        let price = self.get_price(&reserve.token_address).await?;
        let total_power = self.get_total_borrow_power(profile).await?;
        let total_borrowed_value = self.get_total_borrowed_value(profile).await?;
        dbg!(total_power, total_borrowed_value);
        let borrow_factor = reserve.reserve_config.borrow_factor;

        let mut avail_borrow = (total_power
            .checked_sub(total_borrowed_value)
            .unwrap_or_default()
            * borrow_factor as u128
            / 100
            / price as u128)
            .checked_sub(10_u128.pow(5)) // TODO: decimals - 1, get decimals from coin info
            .unwrap_or_default();

        let max_borrow = reserve.get_max_borrowable();
        if avail_borrow > max_borrow as u128 {
            avail_borrow = max_borrow as u128;
        }
        let avail_borrow = reserve.get_borrow_amount_without_fee(avail_borrow as u64);

        Ok((avail_borrow, borrowed_amount))
    }

    /// returns `(avail_withdraw_amount, deposited_amount)`
    pub async fn get_available_withdraw_amount(
        &self,
        profile: &Profile,
        reserve: &ReserveDetail,
    ) -> Result<(u64, u64)> {
        let (_, deposited_amount) = self
            .get_deposited_amount(&profile, &reserve.token_address)
            .await?;

        let mut avail_withdraw = deposited_amount;
        let total_borrowed = self.get_total_borrowed_value(profile).await?;
        if total_borrowed > 0 {
            let total_power = self.get_total_borrow_power(profile).await?;
            let avail_value = total_power.checked_sub(total_borrowed).unwrap_or_default();

            let price = self.get_price(&reserve.token_address).await?;
            // TODO: liq threshold
            avail_withdraw = (avail_value / price as u128) as u64;
            avail_withdraw = avail_withdraw.min(deposited_amount);
        }

        Ok((avail_withdraw, deposited_amount))
    }

    async fn get_reserve_handle(&self) -> Result<AccountAddress> {
        let account = self.contract_address;
        let resp = self
            .rest_client
            .get_account_resource(account, format!("{}::reserve::Reserves", account).as_str())
            .await?;

        let res = resp
            .inner()
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("response not found"))?;

        let handle = res
            .data
            .get("stats")
            .and_then(|stats| stats.get("handle"))
            .and_then(|h| h.as_str())
            .ok_or_else(|| anyhow::anyhow!("handle not found"))?;

        Ok(AccountAddress::from_str(handle)?)
    }

    pub async fn borrow(
        &self,
        profile: &Profile,
        token: &String,
        amount: u64,
    ) -> Result<TransactionInfo> {
        self.withdraw(profile, token, amount, true).await
    }

    pub async fn swap(
        &self,
        from: &String,
        to: &String,
        from_amount: u64,
    ) -> Result<TransactionInfo> {
        let mut u = Url::parse("https://api.panora.exchange/swap")?;
        u.query_pairs_mut()
            .append_pair("chainId", "1")
            .append_pair("fromTokenAddress", from.as_str())
            .append_pair(
                "fromTokenAmount",
                (from_amount as f64 / 10_i32.pow(6) as f64)
                    .to_string()
                    .as_str(),
            ) // TODO:get token decimal
            .append_pair("toTokenAddress", to.as_str())
            .append_pair("slippagePercentage", "0.5")
            .append_pair("numberOfRoutes", "1")
            .append_pair("integratorFeePercentage", "0")
            .append_pair(
                "toWalletAddress",
                self.wallet.address().to_string().as_str(),
            );
        let resp = reqwest::Client::new()
            .post(u)
            .header(
                "x-api-key",
                "a4^KV_EaTf4MW#ZdvgGKX#HUD^3IFEAOV_kzpIE^3BQGA8pDnrkT7JcIy#HNlLGi",
            )
            .body("{}")
            .send()
            .await?;

        let json: serde_json::Value = resp.json().await?;
        if json
            .get("status")
            .unwrap_or(&Value::String("".to_string()))
            .as_str()
            .unwrap_or("")
            == "error"
        {
            return Err(anyhow::anyhow!(
                "API error: {}",
                json.get("message")
                    .unwrap_or(&Value::String("unknown error".to_string()))
            ));
        }

        let tx_data = json
            .get("quotes")
            .and_then(|q| q.get(0))
            .and_then(|q0| q0.get("txData"))
            .ok_or_else(|| anyhow::anyhow!("txData not found in response"))?;

        let function = tx_data
            .get("function")
            .and_then(|f| f.as_str())
            .ok_or_else(|| anyhow::anyhow!("function not found in txData"))?;
        let type_arguments = tx_data
            .get("type_arguments")
            .and_then(|ta| ta.as_array())
            .ok_or_else(|| anyhow::anyhow!("type_arguments not found in txData"))?
            .iter()
            .map(|s| {
                let s = s
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("type_argument is not a string"))?;
                Ok(TypeTag::Struct(StructTag::from_str(s)?.into()))
            })
            .collect::<Result<Vec<TypeTag>>>()?;

        #[derive(Deserialize, Debug)]
        struct Args(
            Option<AccountAddress>,
            AccountAddress,
            u64,
            u8,
            Vec<u8>,
            Vec<Vec<Vec<u8>>>,
            Vec<Vec<Vec<u64>>>,
            Vec<Vec<Vec<bool>>>,
            Vec<Vec<u8>>,
            Vec<Vec<Vec<AccountAddress>>>,
            Vec<Vec<AccountAddress>>,
            Vec<Vec<AccountAddress>>,
            Option<Vec<Vec<Vec<Vec<Vec<u8>>>>>>,
            Vec<Vec<Vec<u64>>>,
            Option<Vec<Vec<Vec<u8>>>>,
            AccountAddress,
            Vec<u64>,
            u64,
            u64,
            AccountAddress,
        );
        let args: Args = serde_json::from_value(
            tx_data
                .get("arguments")
                .ok_or_else(|| anyhow::anyhow!("no arguments found"))?
                .clone(),
        )?;

        let (module_str, function_str) = function
            .rsplit_once("::")
            .ok_or_else(|| anyhow::anyhow!("Invalid function format"))?;
        let (address_str, module_name) = module_str
            .rsplit_once("::")
            .ok_or_else(|| anyhow::anyhow!("Invalid module format"))?;

        let entry_function = EntryFunction::new(
            ModuleId {
                address: AccountAddress::from_str(address_str)?,
                name: Identifier::from_str(module_name)?,
            },
            Identifier::from_str(function_str)?,
            type_arguments,
            vec![
                bcs::to_bytes(&args.0)?,
                bcs::to_bytes(&args.1)?,
                bcs::to_bytes(&args.2)?,
                bcs::to_bytes(&args.3)?,
                bcs::to_bytes(&args.4)?,
                bcs::to_bytes(&args.5)?,
                bcs::to_bytes(&args.6)?,
                bcs::to_bytes(&args.7)?,
                bcs::to_bytes(&args.8)?,
                bcs::to_bytes(&args.9)?,
                bcs::to_bytes(&args.10)?,
                bcs::to_bytes(&args.11)?,
                bcs::to_bytes(&args.12)?,
                bcs::to_bytes(&args.13)?,
                bcs::to_bytes(&args.14)?,
                bcs::to_bytes(&args.15)?,
                bcs::to_bytes(&args.16)?,
                bcs::to_bytes(&args.17)?,
                bcs::to_bytes(&args.18)?,
                bcs::to_bytes(&args.19)?,
            ],
        );

        let sequence_number = self.get_sequence_number(self.wallet.address()).await?;
        let tx = TransactionFactory::new(self.chain_id)
            .payload(TransactionPayload::EntryFunction(entry_function))
            .sequence_number(sequence_number)
            .sender(self.wallet.address())
            .max_gas_amount(MAX_GAS_AMOUNT)
            .build();

        // dbg!(&tx);
        let signed_txn = tx.sign(&self.wallet.private_key(), self.wallet.public_key().clone())?;
        let pending_txn = self.rest_client.submit(&signed_txn).await?;
        let tx = self
            .rest_client
            .wait_for_transaction(&pending_txn.inner())
            .await?;

        Ok(tx.inner().transaction_info().unwrap().clone())
    }

    async fn get_rewards(&self, token: &String, farm_type: FarmType) -> Result<Vec<Reward>> {
        let resp = self
            .rest_client
            .view(
                &ViewRequest {
                    function: EntryFunctionId::from_str(
                        format!("{}::reserve::reserve_farm", self.contract_address).as_str(),
                    )?,
                    type_arguments: vec![
                        MoveType::Struct(MoveStructTag::from_str(token.as_str())?),
                        MoveType::Struct(MoveStructTag::from_str(
                            format!("{}::reserve_config::{}", self.contract_address, farm_type)
                                .as_str(),
                        )?),
                    ],
                    arguments: vec![],
                },
                None,
            )
            .await?;

        let res = resp.inner();

        let items: Vec<RewardItem> = serde_json::from_value(
            res.get(0)
                .unwrap()
                .get("vec")
                .ok_or_else(|| anyhow::anyhow!("invalid data"))?
                .clone(),
        )?;

        let rewards: Vec<Reward> = items
            .into_iter()
            .filter_map(|item| {
                if let (Some(reward), Some(reward_type)) =
                    (item.rewards.into_iter().next(), item.reward_types.get(0))
                {
                    let mut reward = reward;
                    reward.token_address = reward_type.decode();
                    reward.farm_type = farm_type;
                    reward.total_shares = item.share.parse().unwrap_or_default();
                    Some(reward)
                } else {
                    None
                }
            })
            .collect();

        Ok(rewards)
    }

    pub async fn get_borrow_reward_apr(&self, reserve: &ReserveDetail) -> Result<f64> {
        let reserve_price = self.get_price(&reserve.token_address).await?;
        let rewards = self
            .get_rewards(&reserve.token_address, FarmType::BorrowFarming)
            .await?;
        if rewards.is_empty() {
            return Ok(0.0);
        }

        let rw = rewards.get(0).unwrap(); // TODO: handle multi rewards
        let rw_price = self.get_price(&rw.token_address).await?;

        let apr = reserve.get_reward_apr(rw, reserve_price, rw_price);

        Ok(apr)
    }

    pub async fn get_deposit_reward_apr(&self, reserve: &ReserveDetail) -> Result<f64> {
        let reserve_price = self.get_price(&reserve.token_address).await?;
        let rewards = self
            .get_rewards(&reserve.token_address, FarmType::DepositFarming)
            .await?;
        if rewards.is_empty() {
            return Ok(0.0);
        }

        let rw = rewards.get(0).unwrap(); // TODO: handle multi rewards
        let rw_price = self.get_price(&rw.token_address).await?;

        let apr = reserve.get_reward_apr(rw, reserve_price, rw_price);

        Ok(apr)
    }

    pub async fn get_wrapped_fa(&self, coin_token: &String) -> Result<String> {
        if !self.is_wrapped_coin(&coin_token).await? {
            return Err(anyhow::anyhow!("Not wrapped coin"));
        }

        let resp = self
            .rest_client
            .get_account_resource(
                self.contract_address,
                format!(
                    "{}::fa_to_coin_wrapper::WrapperCoinInfo<{}>",
                    self.contract_address, coin_token
                )
                .as_str(),
            )
            .await?;

        let res = match resp.inner() {
            Some(r) => r,
            None => return Err(anyhow::anyhow!("Resource not found")),
        };

        let fa = res
            .data
            .get("metadata")
            .ok_or_else(|| anyhow::anyhow!("field metadata not exists"))?
            .get("inner")
            .ok_or_else(|| anyhow::anyhow!("field inner not exists"))?
            .as_str()
            .unwrap_or_default();

        Ok(fa.to_string())
    }
}

#[derive(Debug, Deserialize)]
struct RewardItem {
    reward_types: Vec<TableKey>,
    rewards: Vec<Reward>,
    share: String,
    timestamp: String,
}

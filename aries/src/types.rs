use aptos_sdk::move_types::account_address::AccountAddress;
use serde::{Deserialize, Serialize};

pub const BORROW_DECIMALS: u32 = 18;

#[derive(Debug, Clone, Deserialize)]
pub struct Profile {
    pub wallet_address: AccountAddress,
    pub name: String,
    pub profile_address: AccountAddress,
    pub emode: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProfileData {
    pub borrowed_reserves_table: TableObject,
    pub deposited_reserves_table: TableObject,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EmodeConfig {
    pub liquidation_bonus_bips: String,
    pub liquidation_threshold: u64,
    pub loan_to_value: u64,
}

#[derive(Debug, Deserialize)]
pub struct ReserveDetail {
    #[serde(skip_deserializing)]
    pub token_address: String,
    pub initial_exchange_rate: AmountValue,
    pub reserve_config: ReserveConfig,
    pub interest_rate_config: InterestConfig,
    pub total_borrowed: AmountValue,
    pub total_borrowed_share: AmountValue,
    pub reserve_amount: AmountValue,
    pub total_cash_available: String,
    pub total_lp_supply: String,
    pub emode: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AmountValue {
    pub val: String,
}

#[derive(Debug, Deserialize)]
struct InterestConfig {
    pub max_borrow_rate: String,
    pub min_borrow_rate: String,
    pub optimal_borrow_rate: String,
    pub optimal_utilization: String,
}

#[derive(Debug, Deserialize)]
pub struct ReserveConfig {
    pub allow_collateral: bool,
    pub allow_redeem: bool,
    pub borrow_factor: u64,
    pub borrow_fee_hundredth_bips: String,
    pub borrow_limit: String,
    pub deposit_limit: String,
    pub flash_loan_fee_hundredth_bips: String,
    pub liquidation_bonus_bips: String,
    pub liquidation_fee_hundredth_bips: String,
    pub liquidation_threshold: u64,
    pub loan_to_value: u64,
    pub reserve_ratio: u64,
    pub withdraw_fee_hundredth_bips: String,
}

impl ReserveDetail {
    fn get_total_assets(&self) -> u64 {
        let total_borrowed = self
            .total_borrowed
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS)) as u64;
        let total_cash_avail: u64 = self.total_cash_available.parse().unwrap_or_default();
        let reserve_amount = self
            .reserve_amount
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS)) as u64;

        total_borrowed + total_cash_avail - reserve_amount
    }

    pub fn lp_to_amount(&self, lp_amount: u64) -> u64 {
        let (rate, _) = self.get_exchange_rates();

        const PRECISION: u64 = 1_000_000;
        (lp_amount * (rate * PRECISION as f64) as u64) / PRECISION
    }

    pub fn borrow_share_to_amount(&self, shares: u128) -> u64 {
        let (_, rate) = self.get_exchange_rates();
        const PRECISION: u128 = 1_000_000;
        ((shares * (rate * PRECISION as f64) as u128) / PRECISION / 10_u128.pow(BORROW_DECIMALS))
            as u64
    }

    pub fn get_borrow_apr(&self) -> f64 {
        let optimal_borrow_rate = self
            .interest_rate_config
            .optimal_borrow_rate
            .parse::<f64>()
            .unwrap_or_default()
            / 100.0;
        let min_borrow_rate = self
            .interest_rate_config
            .min_borrow_rate
            .parse::<f64>()
            .unwrap_or_default()
            / 100.0;
        let max_borrow_rate = self
            .interest_rate_config
            .max_borrow_rate
            .parse::<f64>()
            .unwrap_or_default()
            / 100.0;
        let optimal_utilization_rate = self
            .interest_rate_config
            .optimal_utilization
            .parse::<f64>()
            .unwrap_or_default()
            / 100.0;
        let total_borrowed = self
            .total_borrowed
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS)) as u64;
        let total_assets = self.get_total_assets();

        let utilization_rate = if total_assets == 0 {
            0.0
        } else {
            total_borrowed as f64 / total_assets as f64
        };

        if optimal_utilization_rate == 1.0 || utilization_rate < optimal_utilization_rate {
            let apr = utilization_rate / optimal_utilization_rate
                * (optimal_borrow_rate - min_borrow_rate)
                + min_borrow_rate;

            return apr;
        }

        let apr = (utilization_rate - optimal_utilization_rate) / (1.0 - optimal_utilization_rate)
            * (max_borrow_rate - optimal_borrow_rate)
            + optimal_borrow_rate;

        apr
    }

    pub fn get_deposit_apr(&self) -> f64 {
        let borrow_apr = self.get_borrow_apr();

        let total_borrowed = self
            .total_borrowed
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS) as u128) as u64;
        let total_assets = self.get_total_assets();

        let utilization_rate = if total_assets == 0 {
            0.0
        } else {
            total_borrowed as f64 / total_assets as f64
        };

        borrow_apr * utilization_rate * (100.0 - self.reserve_config.reserve_ratio as f64) / 100.0
    }

    pub fn get_max_borrowable(&self) -> u64 {
        let total_cash_avail: u64 = self.total_cash_available.parse().unwrap_or_default();
        let reserve_amount = self
            .reserve_amount
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS) as u128) as u64;

        let total_borrowed = self
            .total_borrowed
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS) as u128) as u64;

        let borrow_limit: u64 = self.reserve_config.borrow_limit.parse().unwrap_or_default();

        (borrow_limit - total_borrowed).min(total_cash_avail - reserve_amount)
    }

    pub fn get_borrow_amount_without_fee(&self, amount: u64) -> u64 {
        amount
            .checked_sub(
                amount
                    * self
                        .reserve_config
                        .borrow_fee_hundredth_bips
                        .parse::<u64>()
                        .unwrap_or_default()
                    / 1000000,
            )
            .unwrap_or_default()
    }

    fn get_exchange_rates(&self) -> (f64, f64) {
        let total_assets = self.get_total_assets();
        let total_lp: u64 = self.total_lp_supply.parse().unwrap_or_default();
        let lp_rate = if total_lp == 0 {
            (self
                .initial_exchange_rate
                .val
                .parse::<u128>()
                .unwrap_or_default()
                * 1000
                / 10_u128.pow(BORROW_DECIMALS) as u128) as f64
                / 1000.0
        } else {
            total_assets as f64 / total_lp as f64
        };

        let total_borrowed = self
            .total_borrowed
            .val
            .parse::<u128>()
            .unwrap_or_default()
            .div_ceil(10_u128.pow(BORROW_DECIMALS) as u128) as u64;
        let total_borrow_shares =
            self.total_borrowed_share
                .val
                .parse::<u128>()
                .unwrap_or_default()
                .div_ceil(10_u128.pow(BORROW_DECIMALS) as u128) as u64;

        let share_rate = if total_borrow_shares == 0 {
            0.0
        } else {
            total_borrowed as f64 / total_borrow_shares as f64
        };

        (lp_rate, share_rate)
    }

    pub fn get_reward_apr(&self, reward: &Reward, reserve_price: u64, reward_price: u64) -> f64 {
        let daily_reward = reward
            .reward_per_day
            .parse::<u64>()
            .unwrap_or_default()
            .min(reward.remaining_reward.parse().unwrap_or_default());

        let (dep_rate, bor_rate) = self.get_exchange_rates();
        let reserve_amount = match reward.farm_type {
            FarmType::BorrowFarming => (reward.total_shares as f64 * bor_rate) as u64,
            FarmType::DepositFarming => (reward.total_shares as f64 * dep_rate) as u64,
        };

        let price_factor = if reserve_price == 0 {
            0.0
        } else {
            reward_price as f64 / reserve_price as f64
        };

        let amount_factor = if reserve_amount == 0 {
            0.0
        } else {
            daily_reward as f64 / reserve_amount as f64
        };

        price_factor * amount_factor * 365.0
    }
}

use std::fmt;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum FarmType {
    #[default]
    BorrowFarming,
    DepositFarming,
}

impl fmt::Display for FarmType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            FarmType::BorrowFarming => "BorrowFarming",
            FarmType::DepositFarming => "DepositFarming",
        };
        write!(f, "{}", s)
    }
}

impl FarmType {
    pub fn to_string(&self) -> &'static str {
        match self {
            FarmType::BorrowFarming => "BorrowFarming",
            FarmType::DepositFarming => "DepositFarming",
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct Reward {
    #[serde(skip_deserializing)]
    pub token_address: String,
    #[serde(skip_deserializing)]
    pub farm_type: FarmType,
    #[serde(skip_deserializing)]
    pub total_shares: u64,
    pub remaining_reward: String,
    pub reward_per_day: String,
    pub reward_per_share_decimal: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TableObject {
    pub handle: AccountAddress,
    pub length: u32,
    pub head: Option<TableKey>,
    pub tail: Option<TableKey>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TableKey {
    pub account_address: String,
    pub module_name: String,
    pub struct_name: String,
}

impl TableKey {
    pub fn to_string(&self) -> String {
        format!(
            "{}::{}::{}",
            self.account_address, self.module_name, self.struct_name
        )
    }

    pub fn decode(&self) -> String {
        let module_name = hex::decode(&self.module_name.strip_prefix("0x").unwrap_or_default())
            .unwrap_or(self.module_name.as_bytes().to_vec());
        let struct_name = hex::decode(&self.struct_name.strip_prefix("0x").unwrap_or_default())
            .unwrap_or(self.struct_name.as_bytes().to_vec());

        return format!(
            "{}::{}::{}",
            self.account_address,
            String::from_utf8(module_name).unwrap_or_default(),
            String::from_utf8(struct_name).unwrap_or_default(),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::ReserveDetail;

    #[test]
    fn test_reserve() {
        let reserve: ReserveDetail = serde_json::from_str(
            r#"{
                "initial_exchange_rate": {
                    "val": "1000000000000000000"
                },
                "interest_accrue_timestamp": "1750756394",
                "interest_rate_config": {
                    "max_borrow_rate": "250",
                    "min_borrow_rate": "0",
                    "optimal_borrow_rate": "10",
                    "optimal_utilization": "80"
                },
                "reserve_amount": {
                    "val": "4062293499709934463904043084"
                },
                "reserve_config": {
                    "allow_collateral": true,
                    "allow_redeem": true,
                    "borrow_factor": 100,
                    "borrow_fee_hundredth_bips": "1000",
                    "borrow_limit": "180000000000000",
                    "deposit_limit": "260000000000000",
                    "flash_loan_fee_hundredth_bips": "3000",
                    "liquidation_bonus_bips": "300",
                    "liquidation_fee_hundredth_bips": "15000",
                    "liquidation_threshold": 85,
                    "loan_to_value": 80,
                    "reserve_ratio": 20,
                    "withdraw_fee_hundredth_bips": "0"
                },
                "total_borrowed": {
                    "val": "72542787130084535030034564078557"
                },
                "total_borrowed_share": {
                    "val": "70049974561549522190954054254222"
                },
                "total_cash_available": "47548745480391",
                "total_lp_supply": "117734108748830"
            }"#,
        )
        .unwrap();

        let max = reserve.get_max_borrowable();
        assert_eq!(max, 47544683186891);

        assert_eq!(reserve.get_borrow_amount_without_fee(1000), 999); // fee 0.1%
    }
}

module moneyfi::strategy_tapp {
    use std::signer;
    use std::vector;
    use std::option;
    use std::string::String;
    use std::bcs::to_bytes;
    use aptos_std::from_bcs;
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::error;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::Metadata;

    use tapp::router;
    use tapp::integration;
    use tapp::hook_factory;
    use tapp::position;
    use stable::stable;
    use views::stable_views;

    use moneyfi::wallet_account::{Self, WalletAccount};
    use dex_contract::router_v3;
    friend moneyfi::strategy;

    // -- Constants
    const DEADLINE_BUFFER: u64 = 31556926; // 1 years
    const USDC_ADDRESS: address = @stablecoin;

    const STRATEGY_ID: u8 = 4;

    // -- Error
    /// Tapp Strategy data not exists
    const E_TAPP_STRATEGY_DATA_NOT_EXISTS: u64 = 1;
    /// Position not exists
    const E_TAPP_POSITION_NOT_EXISTS: u64 = 2;
    /// Invalid asset
    const E_TAPP_INVALID_ASSET: u64 = 3;

    // -- Structs
    struct StrategyStats has key {
        assets: OrderedMap<Object<Metadata>, AssetStats> // assets -> AssetStats
    }

    struct AssetStats has drop, store {
        total_value_locked: u128, // total value locked in this asset
        total_deposited: u128, // total deposited amount
        total_withdrawn: u128 // total withdrawn amount
    }

    struct TappStrategyData has copy, drop, store {
        strategy_id: u8,
        pools: OrderedMap<address, Position> // pool address -> Position
    }

    struct Position has copy, drop, store {
        position: address, // position address
        lp_amount: u128, // Liquidity pool amount
        asset: Object<Metadata>,
        pair: Object<Metadata>,
        amount: u64,
    }

    struct ExtraData has drop, copy, store {
        pool: address,
        withdraw_fee: u64
    }

    //--initialization
    fun init_module(sender: &signer) {
        move_to(
            sender,
            StrategyStats {
                assets: ordered_map::new<Object<Metadata>, AssetStats>()
            }
        );
    }
}
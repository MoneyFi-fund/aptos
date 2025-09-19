module moneyfi::strategy_echelon_tapp {
    use std::signer;
    use std::vector;
    use std::option::{Self, Option};
    use aptos_std::math128;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::error;
    use aptos_framework::timestamp;
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

    use moneyfi::strategy_echelon;

    const ZERO_ADDRESS: address =
        @0x0000000000000000000000000000000000000000000000000000000000000000;

    /// Position not exists
    const E_TAPP_POSITION_NOT_EXISTS: u64 = 2;
    /// Invalid asset
    const E_INVALID_ASSET: u64 = 3;
}

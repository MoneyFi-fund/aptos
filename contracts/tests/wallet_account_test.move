#[test_only]
module moneyfi::wallet_account_test {
    use std::signer;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use std::vector;
    use aptos_framework::timestamp::{Self};

    use moneyfi::test_helpers;
    use moneyfi::access_control;
    use moneyfi::wallet_account::{Self, WalletAccount, WalletAccountObject};

    // TODO

}

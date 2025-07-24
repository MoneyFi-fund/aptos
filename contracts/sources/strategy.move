module moneyfi::strategy {
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};

    use moneyfi::wallet_account::{Self, WalletAccount};
    use moneyfi::hyperion_strategy;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;

    /// return (deposited_amount)
    public(friend) fun deposit(
        strategy: u8,
        account: Object<WalletAccount>,
        pool: address,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<u8>
    ): (u64, u64) {
        // TODO
        let (actual_amount, gas_fee) =
            if (strategy == STRATEGY_HYPERION) {
                hyperion_strategy::deposit_fund_to_hyperion_single(
                    account, pool, asset, amount, extra_data
                )
            } else {
                // Handle other strategies
                (0, 0)
            };
        (actual_amount, gas_fee)
    }

    /// return (total_deposited_amount, total_withdrawn_amount, gas_fee)
    public(friend) fun withdraw(
        strategy: u8,
        account: Object<WalletAccount>,
        pool: address,
        asset: Object<Metadata>,
        min_amount: u64,
        extra_data: vector<u8>
    ): (u64, u64, u64) {
        let (total_deposited_amount, total_withdrawn_amount, gas_fee) =
            if (strategy == STRATEGY_HYPERION) {
                hyperion_strategy::withdraw_fund_from_hyperion_single(
                    account, pool, asset, amount, extra_data
                )
            } else {
                (0, 0, 0)
            };
        (total_deposited_amount, total_withdrawn_amount, gas_fee)
    }

    /// 1. Swap asset_0 to asset_1: amount_0_in => amount_1_out
    /// 2. Depsoit (amount_1_out + amount_1) asset_1 to strategy
    ///  return (amount_0_in, amount_1_out, deposited_amount_1)
    public(friend) fun swap_and_deposit(
        strategy: u8,
        account: Object<WalletAccount>,
        asset_0: Object<Metadata>,
        asset_1: Object<Metadata>,
        amount_0: u64,
        amount_1: u64,
        extra_data: vector<u8>
    ): (u64, u64, u64) {
        // TODO
        (0, 0, 0)
    }

    /// 1. Withdraw => (total_withdrawn_amount_0, total_withdrawn_amount_1)
    /// 2. Swap asset_0 to asset_1: amount_0_in => amount_1_out
    /// return (
    ///     total_deposited_amount_0,
    ///     total_deposited_amount_1,
    ///     total_withdrawn_amount_0,
    ///     total_withdrawn_amount_1,
    ///     amount_0_in,
    ///     amount_1_out,
    /// )
    public(friend) fun swap_and_withdraw(
        strategy: u8,
        account: Object<WalletAccount>,
        asset_0: Object<Metadata>,
        asset_1: Object<Metadata>,
        amount_0: u64,
        amount_1: u64,
        extra_data: vector<u8>
    ): (u64, u64, u64, u64, u64, u64) {
        // TODO
        (0, 0, 0, 0, 0, 0)
    }
}

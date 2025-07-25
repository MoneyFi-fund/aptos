module moneyfi::strategy {
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};

    use moneyfi::wallet_account::{Self, WalletAccount};
    // use moneyfi::hyperion_strategy;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;

    /// return (deposited_amount)
    public(friend) fun deposit(
        strategy: u8,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<u8>
    ): (u64, u64) {
        // TODO
        let (actual_amount, gas_fee) =
            if (strategy == STRATEGY_HYPERION) {
                // hyperion_strategy::deposit_fund_to_hyperion_single(
                //     account, pool, asset, amount, extra_data
                // )
                (0, 0)
            } else {
                // Handle other strategies
                (0, 0)
            };
        (actual_amount, gas_fee)
    }

    /// return (
    ///     total_deposited_amount,
    ///     total_withdrawn_amount,
    /// )
    public(friend) fun withdraw(
        strategy: u8,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        min_amount: u64,
        extra_data: vector<u8>
    ): (u64, u64) {
        let (total_deposited_amount, total_withdrawn_amount, gas_fee) =
            if (strategy == STRATEGY_HYPERION) {
                // hyperion_strategy::withdraw_fund_from_hyperion_single(
                //     account, asset, amount, extra_data
                // )
                (0, 0, 0)
            } else {
                (0, 0, 0)
            };
        (total_deposited_amount, total_withdrawn_amount)
    }

    /// return (
    ///     actual_amount_in,
    ///     actual_amount_out
    /// )
    public(friend) fun swap(
        strategy: u8,
        account: Object<WalletAccount>,
        from_asset: Object<Metadata>,
        to_asset: Object<Metadata>,
        amount_in: u64,
        min_amount_out: u64,
        extra_data: vector<u8>
    ): (u64, u64) {
        // TODO

        (0, 0)
    }
}

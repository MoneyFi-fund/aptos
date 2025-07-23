module moneyfi::strategy {
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};

    use moneyfi::wallet_account::{Self, WalletAccount};
    use moneyfi::hyperion_strategy;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;

    /// return (actual_amount, gas_fee)
    public(friend) fun deposit(
        strategy: u8,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<u8>
    ): u64 {
        // TODO
        let (actual_amount, gas_fee) = if (strategy == STRATEGY_HYPERION) {
            hyperion_strategy::deposit_fund_to_hyperion_single(
                account,
                pool,
                asset,
                amount
            )
        } else {
            // Handle other strategies
            (0, 0)
        };
        (actual_amount, gas_fee)
    }

    /// return (actual_amount, gas_fee ,interest_amount, loss_amount)
    public(friend) fun withdraw(
        strategy: u8,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<u8>
    ): (u64, u64, u64, u64) {
        // TODO

        (0, 0, 0, 0)
    }
}

module moneyfi::strategy {
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};

    use moneyfi::wallet_account::{Self, WalletAccount};
    use moneyfi::hyperion_strategy;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;

    /// return (actual_amount, lp_amount)
    public(friend) fun deposit(
        strategy: u8,
        pool: address,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64
    ): (u64, u64) {
        // TODO
        let account_signer = wallet_account::get_wallet_account_signer(account);
        let (actual_amount, lp_amount) = if (strategy == STRATEGY_HYPERION) {
            hyperion_strategy::deposit_fund_to_hyperion_from_operator_single(
                account_signer,
                pool,
                asset,
                amount
            )
        } else {
            // Handle other strategies
            (0, 0)
        };
        (0, 0)
    }

    /// return (actual_amount, lp_amount, interest_amount, rewards)
    public(friend) fun withdraw(
        strategy: u8,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64
    ): (u64, u64, u64, OrderedMap<address, u64>) {
        let rewards = ordered_map::new();

        // TODO

        (0, 0, 0, rewards)
    }
}

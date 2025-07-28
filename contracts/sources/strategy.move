module moneyfi::strategy {
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;

    use moneyfi::wallet_account::WalletAccount;
    use moneyfi::hyperion_strategy;
    use moneyfi::thala_strategy;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;
    const STRATEGY_ARIES: u8 = 2;

    // return (
    //     current_tvl,
    //     total_deposited,
    //     total_withdrawn,
    // )
    #[view]
    public fun get_strategy_stats(strategy: u8, asset: Object<Metadata>): (u128, u128, u128) {
        if (strategy == STRATEGY_HYPERION) {
            return hyperion_strategy::get_strategy_stats(asset);
        };

        (0, 0, 0)
    }

    /// return (deposited_amount)
    public(friend) fun deposit(
        strategy: u8,
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        extra_data: vector<u8>
    ): u64 {
        // TODO
        let actual_amount =
            if (strategy == STRATEGY_HYPERION) {
                hyperion_strategy::deposit_fund_to_hyperion_single(
                    account, asset, amount, extra_data
                )
            } else {
                // Handle other strategies
                0
            };
        actual_amount
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
        let (total_deposited_amount, total_withdrawn_amount) =
            if (strategy == STRATEGY_HYPERION) {
                hyperion_strategy::withdraw_fund_from_hyperion_single(
                    account, asset, min_amount, extra_data
                )
            } else { (0, 0) };
        (total_deposited_amount, total_withdrawn_amount)
    }

    public(friend) fun update_tick(
        strategy: u8, account: Object<WalletAccount>, extra_data: vector<u8>
    ) {
        if (strategy == STRATEGY_HYPERION) {
            hyperion_strategy::update_tick(account, extra_data);
        } else {
            // Handle other strategies
        };
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
        let (actual_amount_in, actual_amount_out) =
            if (strategy == STRATEGY_HYPERION) {
                hyperion_strategy::swap(
                    account,
                    from_asset,
                    to_asset,
                    amount_in,
                    min_amount_out,
                    extra_data
                )
            } else { (0, 0) };
        (actual_amount_in, actual_amount_out)
    }
}

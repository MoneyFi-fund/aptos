module moneyfi::strategy {
    use std::vector;
    use std::error;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;

    use moneyfi::wallet_account::WalletAccount;
    use moneyfi::hyperion_strategy;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;
    const STRATEGY_ARIES: u8 = 2;

    const E_UNKNOWN_STRATEGY: u64 = 1;
    const E_NOT_SUPPORTED_BY_STRATEGY: u64 = 2;

    // return [
    //     current_tvl,
    //     total_deposited,
    //     total_withdrawn,
    // ]
    #[view]
    public fun get_strategy_stats(strategy: u8, asset: Object<Metadata>): vector<u128> {
        let stats = vector[];

        if (strategy == STRATEGY_HYPERION) {
            let (v1, v2, v3) = hyperion_strategy::get_strategy_stats(asset);
            vector::append(&mut stats, vector[v1, v2, v3]);
        };

        stats
    }

    /// return deposited_amount
    public(friend) fun deposit(
        strategy: u8,
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount: u64,
        extra_data: vector<vector<u8>>
    ): u64 {
        if (strategy == STRATEGY_HYPERION) {
            return hyperion_strategy::deposit_fund_to_hyperion_single(
                account, asset, amount, extra_data
            );
        };

        abort(error::invalid_argument(E_UNKNOWN_STRATEGY));
        0
    }

    /// return (
    ///     total_deposited_amount,
    ///     total_withdrawn_amount,
    ///     withdraw_fee,
    /// )
    public(friend) fun withdraw(
        strategy: u8,
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        min_amount: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64, u64) {
        if (strategy == STRATEGY_HYPERION) {
            return hyperion_strategy::withdraw_fund_from_hyperion_single(
                account, asset, min_amount, extra_data
            );
        };

        abort(error::invalid_argument(E_UNKNOWN_STRATEGY));
        (0, 0, 0)
    }

    public(friend) fun update_tick(
        strategy: u8, account: &Object<WalletAccount>, extra_data: vector<vector<u8>>
    ) {
        if (strategy == STRATEGY_HYPERION) {
            hyperion_strategy::update_tick(account, extra_data);
        } else {
            // Handle other strategies
        };
    }

    /// return (
    ///     actual_amount_in,
    ///     actual_amount_out,
    /// )
    public(friend) fun swap(
        strategy: u8,
        account: &Object<WalletAccount>,
        from_asset: &Object<Metadata>,
        to_asset: &Object<Metadata>,
        amount_in: u64,
        min_amount_out: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64) {
        if (strategy == STRATEGY_HYPERION) {
            return hyperion_strategy::swap(
                account,
                from_asset,
                to_asset,
                amount_in,
                min_amount_out,
                extra_data
            );
        };

        abort(error::invalid_argument(E_UNKNOWN_STRATEGY));
        (0, 0)
    }
}

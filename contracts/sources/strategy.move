module moneyfi::strategy {
    use std::vector;
    use std::error;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;

    use moneyfi::wallet_account::WalletAccount;
    use moneyfi::strategy_hyperion;
    use moneyfi::strategy_aries;
    use moneyfi::strategy_thala;
    use moneyfi::strategy_tapp;

    friend moneyfi::vault;

    const STRATEGY_HYPERION: u8 = 1;
    const STRATEGY_ARIES: u8 = 2;
    const STRATEGY_THALA: u8 = 3;
    const STRATEGY_TAPP: u8 = 4;

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
            let (v1, v2, v3) = strategy_hyperion::get_strategy_stats(asset);
            vector::append(&mut stats, vector[v1, v2, v3]);
        } else if (strategy == STRATEGY_ARIES) {
            let (v1, v2, v3) = strategy_aries::get_stats(&asset);
            vector::append(&mut stats, vector[v1, v2, v3]);
        } else if (strategy == STRATEGY_THALA) {
            let (v1, v2, v3) = strategy_thala::get_strategy_stats(asset);
            vector::append(&mut stats, vector[v1, v2, v3]);
        } else if (strategy == STRATEGY_TAPP) {
            let (v1, v2, v3) = strategy_tapp::get_strategy_stats(asset);
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
            return strategy_hyperion::deposit_fund_to_hyperion_single(
                account, asset, amount, extra_data
            );
        };

        if (strategy == STRATEGY_ARIES) {
            return strategy_aries::deposit_to_vault(account, asset, amount, extra_data);
        };

        if (strategy == STRATEGY_THALA) {
            return strategy_thala::deposit_fund_to_thala_single(
                account, asset, amount, extra_data
            );
        };

        if (strategy == STRATEGY_TAPP) {
            return strategy_tapp::deposit_fund_to_tapp_single(
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
            return strategy_hyperion::withdraw_fund_from_hyperion_single(
                account, asset, min_amount, extra_data
            );
        };

        if (strategy == STRATEGY_ARIES) {
            return strategy_aries::withdraw_from_vault(
                account, asset, min_amount, extra_data
            );
        };

        if (strategy == STRATEGY_THALA) {
            return strategy_thala::withdraw_fund_from_thala_single(
                account, asset, min_amount, extra_data
            );
        };

        if (strategy == STRATEGY_TAPP) {
            return strategy_tapp::withdraw_fund_from_tapp_single(
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
            strategy_hyperion::update_tick(account, extra_data);
            return
        };

        abort(error::not_implemented(E_NOT_SUPPORTED_BY_STRATEGY));
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
            return strategy_hyperion::swap(
                account,
                from_asset,
                to_asset,
                amount_in,
                min_amount_out,
                extra_data
            );
        };

        if (strategy == STRATEGY_THALA) {
            return strategy_thala::swap(
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

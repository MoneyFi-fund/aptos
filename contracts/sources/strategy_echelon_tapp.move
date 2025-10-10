module moneyfi::strategy_echelon_tapp {
    use std::signer;
    use std::string::String;
    use aptos_std::math128;
    use aptos_std::math64;
    use aptos_std::ordered_map::OrderedMap;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;

    use moneyfi::strategy_echelon;
    use moneyfi::strategy_tapp;

    const U64_MAX: u64 = 18446744073709551615;

    // ========== ENTRY FUNCTIONS ==========

    /// Deposit to vault (proxy to strategy_echelon)
    public entry fun deposit(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64
    ) {
        strategy_echelon::deposit(sender, vault_name, wallet_id, amount);
    }

    /// Withdraw from vault with TAPP reward claiming
    public entry fun withdraw(
        sender: &signer,
        vault_name: String,
        wallet_id: vector<u8>,
        amount: u64,
        gas_fee: u64,
        hook_data: vector<u8>
    ) {
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = strategy_tapp::get_vault_tapp_data(vault_addr);
        let total_borrow_amount = strategy_echelon::vault_borrow_amount(vault_name);

        // Claim TAPP rewards if vault has TAPP positions and borrows
        if (!tapp_data.is_empty() && total_borrow_amount > 0) {
            let withdraw_amount =
                strategy_echelon::estimate_repay_amount_from_account_withdraw_amount(
                    vault_name, wallet_id, amount
                );

            // If we need to repay some borrowed amount, try to get funds from TAPP first
            if (withdraw_amount > 0) {
                // Claim rewards from all TAPP positions
                let claimed_total =
                    claim_all_rewards(&vault_signer, &vault_name, &tapp_data);

                // Compound claimed rewards
                if (claimed_total > 0) {
                    strategy_echelon::compound_rewards(vault_name, claimed_total);
                };

                // Handle TAPP withdrawal with proper sorting and logic
                handle_tapp_withdrawal(
                    &vault_signer,
                    &vault_name,
                    &tapp_data,
                    withdraw_amount,
                    total_borrow_amount
                );
            } else {
                // Even if no repayment needed, still claim rewards for compounding
                let claimed_total =
                    claim_all_rewards(&vault_signer, &vault_name, &tapp_data);
                if (claimed_total > 0) {
                    strategy_echelon::compound_rewards(vault_name, claimed_total);
                };
            };
        };

        // Proceed with the actual withdrawal from the main strategy
        strategy_echelon::withdraw(
            sender,
            vault_name,
            wallet_id,
            amount,
            gas_fee,
            hook_data
        );
    }

    /// Deposit to vault with reward claiming
    public entry fun vault_deposit_echelon(
        sender: &signer, vault_name: String, amount: u64
    ) {
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = strategy_tapp::get_vault_tapp_data(vault_addr);

        if (!tapp_data.is_empty()) {
            let claimed_total = claim_all_rewards(&vault_signer, &vault_name, &tapp_data);
            if (claimed_total > 0) {
                strategy_echelon::compound_rewards(vault_name, claimed_total);
            };
        };

        strategy_echelon::vault_deposit_echelon(sender, vault_name, amount);
    }

    /// Borrow from Echelon and deposit to TAPP
    public entry fun borrow_and_deposit_to_tapp(
        sender: &signer,
        vault_name: String,
        pool: address,
        amount: u64
    ) {
        let borrowable_amount = strategy_echelon::max_borrowable_amount(vault_name);
        if (borrowable_amount == 0) {
            return;
        };

        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = strategy_tapp::get_vault_tapp_data(vault_addr);

        // Claim rewards before borrowing
        if (!tapp_data.is_empty()) {
            let claimed_total = claim_all_rewards(&vault_signer, &vault_name, &tapp_data);
            if (claimed_total > 0) {
                strategy_echelon::compound_rewards(vault_name, claimed_total);
            };
        };

        // Borrow and deposit to TAPP
        let borrowed_amount = strategy_echelon::borrow(sender, vault_name, amount);
        if (borrowed_amount > 0) {
            let asset = strategy_echelon::vault_borrow_asset(vault_name);
            strategy_tapp::deposit_to_tapp_impl(
                &vault_signer, &asset, pool, borrowed_amount
            );
        };
    }

    /// Withdraw from TAPP and repay to Echelon
    public entry fun withdraw_from_tapp_and_repay(
        sender: &signer,
        vault_name: String,
        pool: address,
        min_amount: u64
    ) {
        let vault_signer = strategy_echelon::get_signer(vault_name);
        let vault_addr = signer::address_of(&vault_signer);
        let tapp_data = strategy_tapp::get_vault_tapp_data(vault_addr);

        // Claim rewards first
        if (!tapp_data.is_empty()) {
            let claimed_total = claim_all_rewards(&vault_signer, &vault_name, &tapp_data);
            if (claimed_total > 0) {
                strategy_echelon::compound_rewards(vault_name, claimed_total);
            };
        };

        let total_borrow_amount = strategy_echelon::vault_borrow_amount(vault_name);
        let (_, total_withdrawn_amount) =
            strategy_tapp::withdraw_from_tapp_impl(
                &vault_signer,
                &strategy_echelon::vault_borrow_asset(vault_name),
                pool,
                min_amount
            );

        // Repay borrowed amount
        let repay_amount =
            if (min_amount >= total_borrow_amount) {
                U64_MAX
            } else {
                total_withdrawn_amount
            };

        if (total_withdrawn_amount > 0) {
            let repaid_amount = strategy_echelon::repay(sender, vault_name, repay_amount);

            // If there's profit, swap to vault asset and compound
            if (repaid_amount < total_withdrawn_amount) {
                let profit = total_withdrawn_amount - repaid_amount;
                let (amount_out, _) =
                    strategy_tapp::swap_with_hyperion(
                        &vault_signer,
                        &strategy_echelon::vault_borrow_asset(vault_name),
                        &strategy_echelon::vault_asset(vault_name),
                        profit,
                        false
                    );
                strategy_echelon::compound_rewards(vault_name, amount_out);
            };
        };
    }

    // ========== VIEW FUNCTIONS ==========

    /// Get account state with TAPP positions included
    #[view]
    public fun get_account_state(
        vault_name: String, wallet_id: vector<u8>
    ): (u64, u64, u64) {
        let (
            pending_amount,
            deposited_amount,
            estimate_withdrawable_amount,
            user_shares,
            total_shares
        ) = strategy_echelon::get_account_state(vault_name, wallet_id);

        let vault_addr = strategy_echelon::vault_address(vault_name);
        if (strategy_tapp::vault_has_tapp_data(vault_addr)) {
            let asset = strategy_echelon::vault_asset(vault_name);
            let borrow_asset = strategy_echelon::vault_borrow_asset(vault_name);
            let borrow_amount = strategy_echelon::vault_borrow_amount(vault_name);
            let total_tapp_amount =
                strategy_tapp::get_estimate_withdrawable_amount_to_asset(
                    vault_addr, &borrow_asset
                );

            // Calculate profit or loss
            let (interest_amount, loss_amount) =
                if (total_tapp_amount > borrow_amount) {
                    let profit = total_tapp_amount - borrow_amount;
                    let amount_out =
                        strategy_tapp::get_amount_out(&borrow_asset, &asset, profit);
                    (amount_out, 0)
                } else {
                    let loss = borrow_amount - total_tapp_amount;
                    let amount_out =
                        strategy_tapp::get_amount_out(&borrow_asset, &asset, loss);
                    (0, amount_out)
                };

            // Calculate user's share of profit/loss
            let (user_interest, user_loss) =
                if (total_shares > 0 && user_shares > 0) {
                    (
                        math128::ceil_div(
                            (interest_amount as u128) * (user_shares as u128),
                            (total_shares as u128)
                        ) as u64,
                        math128::ceil_div(
                            (loss_amount as u128) * (user_shares as u128),
                            (total_shares as u128)
                        ) as u64
                    )
                } else { (0, 0) };

            estimate_withdrawable_amount =
                estimate_withdrawable_amount + user_interest - user_loss;
        };

        (pending_amount, deposited_amount, estimate_withdrawable_amount)
    }

    // ========== INTERNAL HELPER FUNCTIONS ==========

    /// Claim rewards from all TAPP positions
    fun claim_all_rewards(
        vault_signer: &signer,
        vault_name: &String,
        tapp_data: &OrderedMap<address, strategy_tapp::Position>
    ): u64 {
        let claimed_total = 0;
        let asset = strategy_echelon::vault_asset(*vault_name);

        tapp_data.for_each_ref(
            |pool, _| {
                let reward_amount =
                    strategy_tapp::claim_tapp_reward(vault_signer, asset, *pool);
                if (reward_amount > 0) {
                    claimed_total = claimed_total + reward_amount;
                };
            }
        );

        claimed_total
    }

    /// Handle TAPP withdrawal with proper sorting and logic
    fun handle_tapp_withdrawal(
        vault_signer: &signer,
        vault_name: &String,
        tapp_data: &OrderedMap<address, strategy_tapp::Position>,
        withdraw_amount: u64,
        total_borrow_amount: u64
    ): u64 {
        let should_withdraw_all = withdraw_amount >= total_borrow_amount;

        if (!should_withdraw_all && withdraw_amount == 0) {
            return 0; // No need to withdraw from TAPP
        };

        // Collect and sort pools by amount (smallest first)
        let pool_amounts = strategy_tapp::collect_pool_amounts(tapp_data);
        strategy_tapp::sort_pools_by_amount_asc(&mut pool_amounts);

        let target_amount =
            if (should_withdraw_all) {
                U64_MAX
            } else {
                withdraw_amount
            };

        // Withdraw from pools sequentially
        let withdrawn_amount =
            strategy_tapp::withdraw_from_pools_sequential(
                vault_signer,
                &strategy_echelon::vault_borrow_asset(*vault_name),
                &pool_amounts,
                target_amount,
                should_withdraw_all
            );

        withdrawn_amount
    }
}

module moneyfi::strategy_aries {
    use std::bcs;
    use std::option::{Self, Option};
    use std::error;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use aptos_std::math64;
    use aptos_std::from_bcs;
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use moneyfi::access_control;
    use moneyfi::storage;
    use moneyfi::wallet_account::{Self, WalletAccount};

    friend moneyfi::strategy;

    const STRATEGY_ACCOUNT_SEED: vector<u8> = b"strategy_aries::STRATEGY_ACCOUNT";
    const SHARE_DECIMALS: u64 = 18;
    const APT_FA_ADDRESS: address = @0xa;
    const U64_MAX: u64 = 18446744073709551615;

    const E_VAULT_EXISTS: u64 = 1;
    const E_EXCEED_CAPACITY: u64 = 2;
    const E_UNSUPPORTED_ASSET: u64 = 3;
    const E_POOL_NOT_EXIST: u64 = 4;

    struct Strategy has key {
        extend_ref: ExtendRef,
        vaults: OrderedMap<address, Vault>
    }

    struct Vault has store, copy {
        name: String,
        asset: Object<Metadata>,
        deposit_cap: u64,
        // accumulated deposited amount
        total_deposited_amount: u128,
        // accumulated withdrawn amount
        total_withdrawn_amount: u128,
        // unused amount
        available_amount: u64,
        reward_amount: u64,
        loans: vector<Loan>,
        paused: bool
    }

    struct Loan has store, copy {
        asset: Object<Metadata>,
        amount: u64
    }

    /// Track asset of an account in vault
    struct VaultAsset has copy, store, drop {
        // amount deposited to aries
        deposited_amount: u64,
        // unused amount
        available_amount: u64,
        shares: u64
    }

    // -- Events
    #[event]
    struct VaultCreatedEvent has drop, store {
        address: address,
        name: String,
        timestamp: u64
    }

    fun init_module(sender: &signer) {
        init_strategy_account();
    }

    // -- Entries

    public entry fun create_vault(
        sender: &signer, name: String, asset: Object<Metadata>
    ) acquires Strategy {
        access_control::must_be_service_account(sender);
        assert!(!name.is_empty());

        let strategy_addr = get_strategy_address();
        assert!(
            !aries::profile::profile_exists(strategy_addr, name),
            error::already_exists(E_VAULT_EXISTS)
        );

        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();

        if (!aries::profile::is_registered(strategy_addr)) {
            aries::profile::init_with_referrer(&strategy_signer, strategy_addr);
        };
        aries::profile::new(&strategy_signer, name);

        let addr = aries::profile::get_profile_address(strategy_addr, name);
        ordered_map::add(
            &mut strategy.vaults,
            addr,
            Vault {
                name,
                asset,
                deposit_cap: U64_MAX,
                available_amount: 0,
                total_deposited_amount: 0,
                total_withdrawn_amount: 0,
                reward_amount: 0,
                loans: vector[],
                paused: false
            }
        );

        event::emit(
            VaultCreatedEvent { address: addr, name, timestamp: timestamp::now_seconds() }
        );
    }

    public entry fun config_vault(
        sender: &signer,
        name: String,
        emode: Option<String>,
        deposit_cap: u64,
        paused: bool
    ) acquires Strategy {
        access_control::must_be_service_account(sender);

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();
        let vault = strategy.get_vault_mut(name);

        vault.deposit_cap = deposit_cap;
        vault.paused = paused;

        if (option::is_some(&emode)) {
            let emode = option::borrow(&emode);
            if (emode.is_empty()) {
                aries::controller::exit_emode(&strategy_signer, name);
            } else {
                aries::controller::enter_emode(&strategy_signer, name, *emode);
            }
        };
    }

    // public entry fun vault_deposit(
    //     sender: &signer, vault_name: String, amount: u64
    // ) acquires Strategy {
    //     access_control::must_be_service_account(sender);

    //     let strategy_addr = get_strategy_address();
    //     let strategy = borrow_global_mut<Strategy>(strategy_addr);

    //     strategy.deposit_to_aries(vault_name, amount);
    // }

    // public entry fun vault_withdraw(
    //     sender: &signer,
    //     vault_name: String,
    //     asset: Object<Metadata>,
    //     amount: u64
    // ) acquires Strategy {
    //     access_control::must_be_service_account(sender);

    //     let strategy_addr = get_strategy_address();
    //     let strategy = borrow_global_mut<Strategy>(strategy_addr);

    //     strategy.withdraw_from_aries(vault_name, amount);
    // }

    // -- Views

    #[view]
    public fun get_vault(name: String): (address, Vault) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let vault_addr = get_vault_address(name);
        assert!(
            ordered_map::contains(&strategy.vaults, &vault_addr),
            error::not_found(E_VAULT_EXISTS)
        );

        (vault_addr, *ordered_map::borrow(&strategy.vaults, &vault_addr))
    }

    // -- Public

    /// deposit fund from wallet account to strategy vault
    public(friend) fun deposit_to_vault(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount: u64,
        extra_data: vector<vector<u8>>
    ): u64 acquires Strategy {
        assert!(amount > 0);
        assert!(extra_data.length() > 0);
        let vault_name = from_bcs::to_string(*extra_data.borrow(0));

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let vault = strategy.get_vault_mut(vault_name);
        assert!(!vault.paused);
        assert!(&vault.asset == asset);

        let (_, asset_amount) = vault.get_deposited_amount();
        assert!(
            asset_amount + vault.available_amount + amount <= vault.deposit_cap,
            error::permission_denied(E_EXCEED_CAPACITY)
        );

        let account_signer = wallet_account::get_wallet_account_signer(account);
        primary_fungible_store::transfer(
            &account_signer,
            vault.asset,
            strategy_addr,
            amount
        );
        vault.total_deposited_amount = vault.total_deposited_amount + (amount as u128);
        vault.available_amount = vault.available_amount + amount;

        let vault_addr = get_vault_address(vault_name);
        let account_data = get_account_data_for_vault(account, vault_addr);
        let vault_asset = account_data.borrow_mut(&vault_addr);

        vault_asset.available_amount = vault_asset.available_amount + amount;

        let shares = strategy.deposit_to_aries(vault_name, amount);
        vault_asset.shares = vault_asset.shares + shares;
        vault_asset.deposited_amount = vault_asset.deposited_amount + amount;
        vault_asset.available_amount = vault_asset.available_amount - amount;

        wallet_account::set_strategy_data(account, account_data);

        amount
    }

    /// Withdraw fund from strategy vault to wallet account
    /// Pass amount = U64_MAX to withdraw all
    public(friend) fun withdraw_from_vault(
        account: &Object<WalletAccount>,
        asset: &Object<Metadata>,
        amount: u64,
        extra_data: vector<vector<u8>>
    ): (u64, u64, u64) acquires Strategy {
        assert!(amount > 0);
        assert!(extra_data.length() > 0);
        let vault_name = from_bcs::to_string(*extra_data.borrow(0));

        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);
        let strategy_signer = strategy.get_account_signer();

        let vault_addr = get_vault_address(vault_name);
        let account_data = get_account_data_for_vault(account, vault_addr);
        let vault_asset = account_data.borrow_mut(&vault_addr);

        // drop vault after check
        {
            let vault = strategy.get_vault_mut(vault_name);
            assert!(!vault.paused);
            assert!(&vault.asset == asset);
        };

        let deposited_amount = amount;
        if (amount > vault_asset.available_amount) {
            // TODO: claim reward
            // {
            //     let vault = strategy.get_vault_mut(vault_name);
            //     vault.claim_swap_reward(&strategy_signer);
            // };

            let reserve_type = get_reserve_type_info(asset);
            let withdraw_amount =
                if (amount == U64_MAX) {
                    aries::reserve::get_underlying_amount_from_lp_amount(
                        reserve_type, vault_asset.shares
                    )
                } else {
                    let withdraw_amount = amount - vault_asset.available_amount;
                    let shares =
                        aries::reserve::get_lp_amount_from_underlying_amount(
                            reserve_type, vault_asset.shares
                        );
                    assert!(shares <= vault_asset.shares);

                    withdraw_amount
                };
            let (amount, shares) =
                strategy.withdraw_from_aries(vault_name, withdraw_amount);
            vault_asset.available_amount = vault_asset.available_amount + amount;
            deposited_amount = math64::mul_div(
                vault_asset.deposited_amount, shares, vault_asset.shares
            );
            vault_asset.shares = vault_asset.shares - shares;
        };
        assert!(vault_asset.available_amount >= amount);

        let vault = strategy.get_vault_mut(vault_name);
        let account_addr = object::object_address(account);
        primary_fungible_store::transfer(
            &strategy_signer,
            vault.asset,
            account_addr,
            amount
        );
        vault_asset.available_amount = vault_asset.available_amount - amount;
        vault_asset.deposited_amount =
            if (vault_asset.deposited_amount > deposited_amount) {
                vault_asset.deposited_amount - deposited_amount
            } else { 0 };

        vault.available_amount = vault.available_amount - amount;
        vault.total_withdrawn_amount = vault.total_withdrawn_amount + (amount as u128);

        wallet_account::set_strategy_data(account, account_data);

        (deposited_amount, amount, 0)
    }

    public fun get_stats(asset: &Object<Metadata>): (u128, u128, u128) acquires Strategy {
        let strategy_addr = get_strategy_address();
        let strategy = borrow_global_mut<Strategy>(strategy_addr);

        let total_deposited = 0;
        let total_withdrawn = 0;
        let current_tvl = 0;
        strategy.vaults.for_each_ref(|k, v| {
            if (&v.asset == asset) {
                total_deposited = total_deposited + v.total_deposited_amount;
                total_withdrawn = total_withdrawn + v.total_withdrawn_amount;

                let (_, asset_amount) = get_deposited_amount(v);
                current_tvl = current_tvl + (asset_amount as u128);
            };
        });

        (current_tvl, total_deposited, total_withdrawn)
    }

    //  -- Private

    fun init_strategy_account() {
        let account_addr = storage::get_child_object_address(STRATEGY_ACCOUNT_SEED);
        assert!(!exists<Strategy>(account_addr));

        let extend_ref =
            storage::create_child_object_with_phantom_owner(STRATEGY_ACCOUNT_SEED);
        let account_signer = object::generate_signer_for_extending(&extend_ref);
        move_to(
            &account_signer,
            Strategy { extend_ref, vaults: ordered_map::new() }
        );
    }

    fun get_strategy_address(): address {
        storage::get_child_object_address(STRATEGY_ACCOUNT_SEED)
    }

    fun get_account_signer(self: &Strategy): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    fun get_vault_mut_by_address(self: &mut Strategy, addr: address): &mut Vault {
        assert!(ordered_map::contains(&self.vaults, &addr));

        ordered_map::borrow_mut(&mut self.vaults, &addr)
    }

    fun get_vault_address(name: String): address {
        let strategy_addr = get_strategy_address();

        aries::profile::get_profile_address(strategy_addr, name)
    }

    fun get_vault_mut(self: &mut Strategy, name: String): &mut Vault {
        self.get_vault_mut_by_address(get_vault_address(name))
    }

    fun get_account_data_for_vault(
        account: &Object<WalletAccount>, vault_addr: address
    ): OrderedMap<address, VaultAsset> {
        let account_data =
            if (wallet_account::strategy_data_exists<OrderedMap<address, VaultAsset>>(
                account
            )) {
                wallet_account::get_strategy_data<OrderedMap<address, VaultAsset>>(
                    account
                )
            } else {
                ordered_map::new()
            };

        if (!account_data.contains(&vault_addr)) {
            account_data.add(
                vault_addr,
                VaultAsset { deposited_amount: 0, available_amount: 0, shares: 0 }
            )
        };

        account_data
    }

    /// Deposit asset from vault to Aries
    /// Return shares
    fun deposit_to_aries(
        self: &mut Strategy, vault_name: String, amount: u64
    ): u64 {
        let strategy_signer = self.get_account_signer();
        let strategy_addr = get_strategy_address();
        let vault = self.get_vault_mut(vault_name);
        let asset_addr = object::object_address(&vault.asset);
        assert!(!vault.paused);
        assert!(
            asset_addr == @usdc || asset_addr == @usdt,
            error::permission_denied(E_UNSUPPORTED_ASSET)
        );
        assert!(amount > 0 && amount <= vault.available_amount);

        let profile = *vault_name.bytes();
        let (shares_before, _) = vault.get_deposited_amount();
        if (asset_addr == @usdc) {
            aries::controller::deposit_fa<aries::wrapped_coins::WrappedUSDC>(
                &strategy_signer, profile, amount
            );
        } else if (asset_addr == @usdt) {
            aries::controller::deposit_fa<aries::fa_to_coin_wrapper::WrappedUSDT>(
                &strategy_signer, profile, amount
            );
        };
        let (shares_after, _) = vault.get_deposited_amount();
        assert!(shares_after > shares_before);

        let shares = shares_after - shares_before;

        vault.available_amount = vault.available_amount - amount;

        shares
    }

    /// Withdraw asset from Aries back to vault
    /// Return received amount and burned shares
    fun withdraw_from_aries(
        self: &mut Strategy, vault_name: String, amount: u64
    ): (u64, u64) {
        let strategy_signer = self.get_account_signer();
        let vault = self.get_vault_mut(vault_name);
        let asset_addr = object::object_address(&vault.asset);
        assert!(amount > 0);
        assert!(!vault.paused);
        assert!(
            asset_addr == @usdc || asset_addr == @usdt,
            error::permission_denied(E_UNSUPPORTED_ASSET)
        );

        let strategy_addr = get_strategy_address();
        let balance_before = primary_fungible_store::balance(strategy_addr, vault.asset);
        let (shares_before, _) = vault.get_deposited_amount();

        let profile = *vault_name.bytes();
        if (asset_addr == @usdc) {
            aries::controller::withdraw_fa<aries::wrapped_coins::WrappedUSDC>(
                &strategy_signer, profile, amount, false
            );
        } else if (asset_addr == @usdt) {
            aries::controller::withdraw_fa<aries::fa_to_coin_wrapper::WrappedUSDT>(
                &strategy_signer, profile, amount, false
            );
        };

        let balance_after = primary_fungible_store::balance(strategy_addr, vault.asset);
        let (shares_after, _) = vault.get_deposited_amount();
        assert!(balance_after >= balance_before);
        assert!(shares_before >= shares_after);

        let amount = balance_after - balance_before;
        let shares = shares_before - shares_after;
        vault.available_amount = vault.available_amount + amount;

        (amount, shares)
    }

    fun claim_swap_reward(self: &mut Vault, strategy_signer: &signer) {
        // TODO: check claimable amount
        let reward_amount =
            claim_deposit_reward(strategy_signer, *self.name.bytes(), &self.asset);

        let asset_amount =
            if (reward_amount > 100_000_000) { // 1 APT
                swap_reward(strategy_signer, &self.asset, reward_amount)
            } else { 0 };

        // self.available_amount = self.available_amount + asset_amount;
        self.reward_amount = self.reward_amount + asset_amount;

    }

    /// Returns shares and current asset amount
    fun get_deposited_amount(self: &Vault): (u64, u64) {
        let strategy_addr = get_strategy_address();

        let reserve_type = get_reserve_type_info(&self.asset);
        let shares =
            aries::profile::get_deposited_amount(strategy_addr, &self.name, reserve_type);
        let asset_amount =
            aries::reserve::get_underlying_amount_from_lp_amount(reserve_type, shares);

        (shares, asset_amount)
    }

    fun claim_deposit_reward(
        strategy_signer: &signer, profile: vector<u8>, asset: &Object<Metadata>
    ): u64 {
        claim_reward(
            strategy_signer,
            profile,
            asset,
            type_info::type_of<aries::reserve_config::DepositFarming>()
        )
    }

    fun claim_borrow_reward(
        strategy_signer: &signer, profile: vector<u8>, asset: &Object<Metadata>
    ): u64 {
        claim_reward(
            strategy_signer,
            profile,
            asset,
            type_info::type_of<aries::reserve_config::BorrowFarming>()
        )
    }

    /// Claim APT reward
    fun claim_reward(
        strategy_signer: &signer,
        profile: vector<u8>,
        asset: &Object<Metadata>,
        farming: TypeInfo
    ): u64 {
        let strategy_addr = get_strategy_address();
        let reserve_type = get_reserve_type_info(asset);

        let balance_before = coin::balance<AptosCoin>(strategy_addr);
        aries::controller::claim_reward_ti<AptosCoin>(
            strategy_signer,
            profile,
            reserve_type,
            farming
        );
        let balance_after = coin::balance<AptosCoin>(strategy_addr);

        if (balance_after > balance_before) {
            balance_after - balance_before
        } else { 0 }
    }

    fun get_reserve_type_info(asset: &Object<Metadata>): TypeInfo {
        let asset_addr = object::object_address(asset);
        if (asset_addr == @usdc) {
            return type_info::type_of<aries::wrapped_coins::WrappedUSDC>();
        } else if (asset_addr == @usdt) {
            return type_info::type_of<aries::fa_to_coin_wrapper::WrappedUSDT>();
        };

        abort error::permission_denied(E_UNSUPPORTED_ASSET);
        type_info::type_of<TypeInfo>() // Fallback
    }

    /// Swap APT reward to USDT/USDC using Hyperion
    /// Returns the amount of USDT/USDC received
    fun swap_reward(
        strategy_signer: &signer, to: &Object<Metadata>, amount: u64
    ): u64 {
        let strategy_addr = get_strategy_address();

        let fee_tier = 1; // 0.05%
        let apt = object::address_to_object<Metadata>(APT_FA_ADDRESS);
        // let (exist, pool_addr) =
        //     hyperion::pool_v3::liquidity_pool_address_safe(apt, *to, fee_tier);
        // assert!(exist, error::permission_denied(E_POOL_NOT_EXIST));
        // let pool =
        //     object::address_to_object<hyperion::pool_v3::LiquidityPoolV3>(pool_addr);

        let pool = hyperion::pool_v3::liquidity_pool(apt, *to, fee_tier);
        let (amount_out, _) = hyperion::pool_v3::get_amount_out(pool, apt, amount);
        amount_out = amount_out - (amount_out * 1 / 1000); // 0.1% slippage

        // ignore price impact
        let sqrt_price_limit =
            if (hyperion::utils::is_sorted(apt, *to)) {
                79226673515401279992447579055 // max sqrt price
            } else {
                04295048016 // min sqrt price
            };

        let balance_before = primary_fungible_store::balance(strategy_addr, *to);
        hyperion::router_v3::exact_input_swap_entry(
            strategy_signer,
            fee_tier,
            amount,
            amount_out,
            sqrt_price_limit,
            apt,
            *to,
            strategy_addr,
            timestamp::now_seconds() + 60
        );
        let balance_after = primary_fungible_store::balance(strategy_addr, *to);

        balance_after - balance_before
    }
}

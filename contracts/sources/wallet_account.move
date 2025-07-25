module moneyfi::wallet_account {
    use std::bcs;
    use std::signer;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::timestamp;

    use moneyfi::access_control;
    use moneyfi::storage;

    friend moneyfi::vault;
    friend moneyfi::strategy;
    friend moneyfi::hyperion_strategy;

    // -- Constants
    const WALLET_ACCOUNT_SEED: vector<u8> = b"WALLET_ACCOUNT";
    const CHAIN_ID_APTOS: u8 = 0;

    // -- Errors
    const E_WALLET_ACCOUNT_EXISTS: u64 = 1;
    const E_WALLET_ACCOUNT_NOT_EXISTS: u64 = 2;
    const E_NOT_APTOS_WALLET_ACCOUNT: u64 = 3;
    const E_NOT_OWNER: u64 = 4;
    const E_WALLET_ACCOUNT_NOT_CONNECTED: u64 = 5;
    const E_WALLET_ACCOUNT_ALREADY_CONNECTED: u64 = 6;
    const E_INVALID_ARGUMENT: u64 = 7;

    // -- Structs
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct WalletAccount has key {
        // wallet_id is a byte array of length 32
        wallet_id: vector<u8>,
        // internal chain ID
        chain_id: u8,
        wallet_address: Option<address>,
        referrer_wallet_id: vector<u8>,
        assets: OrderedMap<address, AccountAsset>,
        extend_ref: ExtendRef
    }

    struct AccountAsset has drop, store, copy {
        current_amount: u64,
        deposited_amount: u64,
        lp_amount: u64,
        swap_out_amount: u64,
        swap_in_amount: u64,
        distributed_amount: u64,
        withdrawn_amount: u64,
        interest_amount: u64,
        interest_share_amount: u64,
        rewards: OrderedMap<address, u64>
    }

    struct WalletAccountObject has key {
        wallet_account: Object<WalletAccount>
    }

    struct StrategyData<T> has key {
        data: T
    }

    // -- Events
    #[event]
    struct WalletAccountCreatedEvent has drop, store {
        wallet_id: vector<u8>,
        chain_id: u8,
        wallet_account: Object<WalletAccount>,
        timestamp: u64
    }

    public entry fun register(
        sender: &signer,
        verifier: &signer,
        wallet_id: vector<u8>,
        referrer_wallet_id: vector<u8>
    ) {
        access_control::must_be_service_account(verifier);
        let wallet_address = signer::address_of(sender);
        assert!(
            !exists<WalletAccountObject>(wallet_address),
            error::already_exists(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account =
            create_wallet_account(
                wallet_id,
                CHAIN_ID_APTOS,
                option::some(wallet_address),
                referrer_wallet_id
            );
        move_to(sender, WalletAccountObject { wallet_account });

        event::emit(
            WalletAccountCreatedEvent {
                wallet_id,
                chain_id: CHAIN_ID_APTOS,
                wallet_account,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    fun create_wallet_account(
        wallet_id: vector<u8>,
        chain_id: u8,
        wallet_address: Option<address>,
        referrer_wallet_id: vector<u8>
    ): Object<WalletAccount> {
        let account_addr = get_wallet_account_object_address(wallet_id);
        assert!(
            !object::object_exists<WalletAccount>(account_addr),
            error::already_exists(E_WALLET_ACCOUNT_EXISTS)
        );

        let extend_ref =
            storage::create_child_object_with_phantom_owner(
                get_wallet_account_object_seed(wallet_id)
            );
        let account_signer = &object::generate_signer_for_extending(&extend_ref);

        move_to(
            account_signer,
            WalletAccount {
                wallet_id: wallet_id,
                chain_id,
                wallet_address,
                referrer_wallet_id,
                assets: ordered_map::new(),
                extend_ref: extend_ref
            }
        );

        let wallet_account = object::address_to_object(account_addr);

        wallet_account
    }

    public(friend) fun deposit(
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64
    ) acquires WalletAccount {
        let account_addr = object::object_address(&account);
        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);

        let asset_data = wallet_account.get_asset(asset);
        asset_data.deposited_amount = asset_data.deposited_amount + amount;
        asset_data.current_amount = asset_data.current_amount + amount;
        asset_data.lp_amount = asset_data.lp_amount + lp_amount;

        wallet_account.set_asset(asset, asset_data);
    }

    /// return amount of lp token
    public(friend) fun withdraw(
        account: Object<WalletAccount>, asset: Object<Metadata>, amount: u64
    ): u64 acquires WalletAccount {
        let account_addr = object::object_address(&account);
        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);

        let asset_data = wallet_account.get_asset(asset);
        assert!(amount > 0 && asset_data.current_amount >= amount);

        let lp_amount =
            ((amount as u128) * (asset_data.lp_amount as u128)
                / (asset_data.current_amount as u128)) as u64;

        asset_data.withdrawn_amount = asset_data.withdrawn_amount + amount;
        asset_data.current_amount = asset_data.current_amount - amount;
        asset_data.lp_amount = asset_data.lp_amount - lp_amount;

        wallet_account.set_asset(asset, asset_data);

        lp_amount
    }

    // return lp amount for src asset
    public(friend) fun swap(
        account: Object<WalletAccount>,
        from_asset: Object<Metadata>,
        to_asset: Object<Metadata>,
        from_amount: u64,
        to_amount: u64,
        to_lp_amount: u64
    ): u64 acquires WalletAccount {
        let account_addr = object::object_address(&account);
        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);

        let asset_data_0 = wallet_account.get_asset(from_asset);
        let asset_data_1 = wallet_account.get_asset(to_asset);
        assert!(
            from_amount > 0 && asset_data_0.current_amount >= from_amount
        );

        let lp_amount_0 =
            ((from_amount as u128) * (asset_data_0.lp_amount as u128)
                / (asset_data_0.current_amount as u128)) as u64;

        asset_data_0.swap_out_amount = asset_data_0.swap_out_amount + from_amount;
        asset_data_0.current_amount = asset_data_0.current_amount - from_amount;
        asset_data_0.lp_amount = asset_data_0.lp_amount - lp_amount_0;

        asset_data_1.lp_amount = asset_data_1.lp_amount + to_lp_amount;
        asset_data_1.current_amount = asset_data_1.current_amount + to_amount;
        asset_data_1.swap_in_amount = asset_data_1.swap_in_amount + to_amount;

        wallet_account.set_asset(from_asset, asset_data_0);
        wallet_account.set_asset(to_asset, asset_data_1);

        lp_amount_0
    }

    public(friend) fun distributed_fund(
        account: Object<WalletAccount>, asset: Object<Metadata>, amount: u64
    ) acquires WalletAccount {
        let account_addr = object::object_address(&account);
        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);

        let asset_data = wallet_account.get_asset(asset);
        assert!(asset_data.current_amount >= amount);

        asset_data.distributed_amount = asset_data.distributed_amount + amount;
        asset_data.current_amount = asset_data.current_amount - amount;
        wallet_account.set_asset(asset, asset_data);
    }

    public(friend) fun collected_fund(
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        distributed_amount: u64,
        collected_amount: u64,
        interest_amount: u64,
        interest_share_amount: u64

    ) acquires WalletAccount {
        let account_addr = object::object_address(&account);

        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);
        let asset_data = wallet_account.get_asset(asset);
        assert!(asset_data.distributed_amount >= distributed_amount);

        asset_data.distributed_amount = asset_data.distributed_amount
            - distributed_amount;
        asset_data.current_amount = asset_data.current_amount + collected_amount;
        asset_data.interest_amount = asset_data.interest_amount + interest_amount;
        asset_data.interest_share_amount =
            asset_data.interest_share_amount + interest_share_amount;

        wallet_account.set_asset(asset, asset_data);
    }

    public(friend) fun set_strategy_data<T: store + drop + copy>(
        account: Object<WalletAccount>, data: T
    ) acquires StrategyData, WalletAccount {
        let addr = object::object_address(&account);
        if (!exists<StrategyData<T>>(addr)) {
            let account_signer = get_wallet_account_signer(account);
            move_to(&account_signer, StrategyData { data });
        };

        let strategy_data = borrow_global_mut<StrategyData<T>>(addr);
        strategy_data.data = data;
    }

    public(friend) fun get_strategy_data<T: store + copy>(
        account: Object<WalletAccount>
    ): T acquires StrategyData {
        let addr = object::object_address(&account);
        assert!(exists<StrategyData<T>>(addr));

        let strategy_data = borrow_global<StrategyData<T>>(addr);

        strategy_data.data
    }

    public fun exists_strategy_data<T: store>(
        account: Object<WalletAccount>
    ): bool {
        let addr = object::object_address(&account);
        exists<StrategyData<T>>(addr)
    }

    // Check wallet_id is a valid wallet account
    #[view]
    public fun has_wallet_account(wallet_id: vector<u8>): bool {
        let addr = get_wallet_account_object_address(wallet_id);
        object::object_exists<WalletAccount>(addr)
    }

    // Get the WalletAccount object address for a given wallet_id
    // #[view]
    public fun get_wallet_account_object_address(wallet_id: vector<u8>): address {
        storage::get_child_object_address(get_wallet_account_object_seed(wallet_id))
    }

    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account(wallet_id: vector<u8>): Object<WalletAccount> {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        object::address_to_object<WalletAccount>(addr)
    }

    public fun get_wallet_account_by_address(
        addr: address
    ): Object<WalletAccount> acquires WalletAccountObject {
        let obj = borrow_global<WalletAccountObject>(addr);

        obj.wallet_account
    }

    public fun get_wallet_id_by_address(
        addr: address
    ): vector<u8> acquires WalletAccountObject, WalletAccount {
        let obj = borrow_global<WalletAccountObject>(addr);
        let wallet_account =
            borrow_global<WalletAccount>(object::object_address(&obj.wallet_account));
        wallet_account.wallet_id
    }

    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&vector[WALLET_ACCOUNT_SEED, wallet_id])
    }

    public(friend) fun get_wallet_account_signer(
        account: Object<WalletAccount>
    ): signer acquires WalletAccount {
        let addr = object::object_address(&account);

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    public(friend) fun get_referrer_addresses(
        account: Object<WalletAccount>, max: u8
    ): vector<address> acquires WalletAccount {
        let referrers = vector[];

        let i = 0;
        let addr = object::object_address(&account);
        while (i < max) {
            if (!exists<WalletAccount>(addr)) {
                break;
            };
            let account = borrow_global<WalletAccount>(addr);
            if (vector::is_empty(&account.referrer_wallet_id)) {
                break;
            };
            vector::push_back(
                &mut referrers,
                get_wallet_account_object_address(account.referrer_wallet_id)
            );

            i = i + 1;
        };

        referrers
    }

    fun get_asset(self: &WalletAccount, asset: Object<Metadata>): AccountAsset {
        let addr = object::object_address(&asset);
        if (ordered_map::contains(&self.assets, &addr)) {
            return *ordered_map::borrow(&self.assets, &addr);
        };

        AccountAsset {
            current_amount: 0,
            deposited_amount: 0,
            lp_amount: 0,
            swap_out_amount: 0,
            swap_in_amount: 0,
            distributed_amount: 0,
            withdrawn_amount: 0,
            interest_amount: 0,
            interest_share_amount: 0,
            rewards: ordered_map::new()
        }
    }

    fun set_asset(
        self: &mut WalletAccount, asset: Object<Metadata>, data: AccountAsset
    ) {
        let addr = object::object_address(&asset);
        ordered_map::upsert(&mut self.assets, addr, data);
    }

    #[test_only]
    friend moneyfi::wallet_account_test;

    #[test_only]
    public fun create_wallet_account_for_test(
        wallet: &signer,
        wallet_id: vector<u8>,
        chain_id: u8,
        referrer_wallet_id: vector<u8>
    ): Object<WalletAccount> {
        let wallet_address = signer::address_of(wallet);
        let account =
            create_wallet_account(
                wallet_id,
                chain_id,
                option::some(wallet_address),
                referrer_wallet_id
            );
        move_to(wallet, WalletAccountObject { wallet_account: account });

        account
    }

    #[test_only]
    public fun get_wallet_account_signer_for_test(
        addr: address
    ): signer acquires WalletAccount, WalletAccountObject {
        get_wallet_account_signer(get_wallet_account_by_address(addr))
    }
}

module moneyfi::wallet_account {
    use std::bcs;
    use std::signer;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::event;
    use aptos_framework::util;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use moneyfi::access_control;
    use moneyfi::storage;

    friend moneyfi::vault;
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
        assets: OrderedMap<address, AccountAsset>,
        extend_ref: ExtendRef
    }

    struct AccountAsset has drop, store {
        remaining_amount: u64,
        deposited_amount: u64,
        lp_amount: u64,
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
        sender: &signer, verifier: &signer, wallet_id: vector<u8>
    ) acquires WalletAccount {
        access_control::must_be_service_account(verifier);
        let wallet_address = signer::address_of(sender);
        assert!(
            !exists<WalletAccountObject>(wallet_address),
            error::already_exists(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account =
            create_wallet_account(
                wallet_id, CHAIN_ID_APTOS, option::some(wallet_address)
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
        wallet_id: vector<u8>, chain_id: u8, wallet_address: Option<address>
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
        asset_data.deposited_amount += amount;
        asset_data.lp_amount += lp_amount;

        wallet_account.set_asset(asset, asset_data);
    }

    public(friend) fun withdraw(
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64
    ) acquires WalletAccount {
        let account_addr = object::object_address(&account);
        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);

        let asset_data = wallet_account.get_asset(asset);
        assert!(asset_data.lp_amount >= lp_amount);
        assert!(asset_data.remaining_amount >= amount);

        asset_data.withdrawn_amount += amount;
        asset_data.lp_amount -= lp_amount;
        asset_data.remaining_amount -= amount;

        wallet_account.set_asset(asset, asset_data);
    }

    public(friend) fun distributed_fund(
        account: Object<WalletAccount>, asset: Object<Metadata>, amount: u64
    ) acquires WalletAccount {
        let account_addr = object::object_address(&account);
        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);

        let asset_data = wallet_account.get_asset(asset);
        assert!(asset_data.remaining_amount >= amount);

        asset_data.distributed_amount = asset_data.distributed_amount + amount;
        asset_data.remaining_amount = asset_data.remaining_amount - amount;
        wallet_account.set_asset(asset, asset_data);
    }

    public(friend) fun collected_fund(
        account: Object<WalletAccount>,
        asset: Object<Metadata>,
        amount: u64,
        interest_amount: u64,
        interest_share_amount: u64

    ) acquires WalletAccount {
        let account_addr = object::object_address(&account);

        let wallet_account = borrow_global_mut<WalletAccount>(account_addr);
        let asset_data = wallet_account.get_asset(asset);
        assert!(asset_data.distributed_amount >= amount);

        asset_data.remaining_amount = asset_data.remaining_amount + amount;
        asset_data.interest_amount = asset_data.interest_amount + interest_amount;
        asset_data.interest_share_amount =
            asset_data.interest_share_amount + interest_share_amount;

        if (asset_data.distributed_amount > amount) {
            asset_data.distributed_amount = asset_data.distributed_amount - amount;
        } else {
            asset_data.distributed_amount = 0;
        };
        wallet_account.set_asset(asset, asset_data);
    }

    public(friend) fun set_strategy_data<T: store>(
        account: Object<WalletAccount>, data: T
    ) acquires StrategyData {
        let addr = object::object_address(&account);
        if (!exists<StrategyData<T>>(addr)) {
            let account_signer = get_wallet_account_signer(account);
            move_to(&account_signer, StrategyData { data });
        };

        let strategy_data = borrow_global_mut<StrategyData<T>>(addr);
        strategy_data.data = data;
    }

    public(friend) fun get_strategy_data<T: store>(
        account: Object<WalletAccount>
    ): T acquires StrategyData {
        let addr = object::object_address(&account);
        assert!(exists<StrategyData<T>>(addr));

        let strategy_data = borrow_global<StrategyData<T>>(addr);

        strategy_data.data
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

    fun get_asset(self: &WalletAccount, asset: Object<Metadata>): AccountAsset {
        let addr = object::object_address(&asset);
        if (ordered_map::contains(&self.assets, &addr)) {
            return *ordered_map::borrow(&self.assets, &addr);
        };

        AccountAsset {
            remaining_amount: 0,
            deposited_amount: 0,
            lp_amount: 0,
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
    public(friend) fun create_wallet_account_for_test(
        wallet_id: vector<u8>, chain_id: u8, wallet_address: Option<address>
    ): Object<WalletAccount> {
        create_wallet_account(wallet_id, chain_id, wallet_address)
    }
}

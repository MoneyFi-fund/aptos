module moneyfi::wallet_account {
    use std::bcs;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::error;
    use aptos_std::table::{Self, Table};
    use aptos_std::string_utils;
    use aptos_framework::account;
    use aptos_framework::util;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};

    use moneyfi::access_control;

    // -- Constants
    const WALLET_ACCOUNT_SEED: vector<u8> = b"WALLET_ACCOUNT";
    const APT_SRC_DOMAIN: u32 = 9;

    // -- Errors
    const E_WALLET_ACCOUNT_EXISTS: u64 = 1;
    const E_WALLET_ACCOUNT_NOT_EXISTS: u64 = 2;
    const E_NOT_APTOS_WALLET_ACCOUNT: u64 = 3;
    const E_NOT_OWNER: u64 = 4;
    const E_WALLET_ACCOUNT_NOT_CONNECTED: u64 = 5;
    const E_WALLET_ACCOUNT_ALREADY_CONNECTED: u64 = 6;

    // -- Structs
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct WalletAccount has key {
        wallet_id: vector<u8>,
        source_domain: u32,
        assets: Table<address, u64>,
        distributed_assets: Table<address, u64>,
        position_opened: vector<address>,
        extend_ref: ExtendRef
    }

    struct WalletAccountObject has key {
        wallet_account: Object<WalletAccount>
    }

    // -- Events
    #[event]
    struct WalletAccountCreated has drop, store {
        wallet_id: vector<u8>,
        source_domain: u32,
        wallet_object: address,
    }

    #[event]
    struct WalletAccountConnected has drop, store {
        wallet_id: vector<u8>,
        wallet_object: address,
        wallet_address: address
    }   

    // -- Entries
    /// create a new WalletAccount for a given wallet_id<byte[32]>
    public entry fun create_wallet_account(
        sender: &signer, wallet_id: vector<u8>, source_domain: u32
    ) {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(!object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS));

        let data_object_signer = &access_control::get_object_data_signer();

        let constructor_ref =
            &object::create_named_object(
                data_object_signer, get_wallet_account_object_seed(wallet_id)
            );
        let wallet_signer = &object::generate_signer(constructor_ref);
        move_to(
            wallet_signer,
            WalletAccount {
                wallet_id: wallet_id,
                source_domain: source_domain,
                assets: table::new<address, u64>(),
                distributed_assets: table::new<address, u64>(),
                position_opened: vector::empty<address>(),
                extend_ref: object::generate_extend_ref(constructor_ref)
            }
        );

        event::emit(
            WalletAccountCreated {
                wallet_id: wallet_id,
                source_domain: source_domain,
                wallet_object: addr
            }
        );
    }

    /// Connect user wallet to a WalletAccount
    public entry fun connect_wallet(
        sender: &signer, wallet_id: vector<u8>, signature: vector<u8>
    ) acquires WalletAccount {

        // TODO: verify signature
        //connect_wallet_internal(sender, wallet_id);
    }

    /// Connect Aptos wallet to a WalletAccount
    /// This function has to be called before claim assets
    public entry fun connect_aptos_wallet(
        sender: &signer, wallet_id: vector<u8>
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        assert!(wallet_account.source_domain == APT_SRC_DOMAIN, error::invalid_state(E_NOT_APTOS_WALLET_ACCOUNT));
        assert!(signer::address_of(sender) == util::address_from_bytes(wallet_id), error::permission_denied(E_NOT_OWNER));
        connect_wallet_internal(sender, wallet_account);
    }

    // -- Views
    /// Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account_object_address(wallet_id: vector<u8>): address {
        let data_object_addr = access_control::get_data_object_address();
        object::create_object_address(
            &data_object_addr, get_wallet_account_object_seed(wallet_id)
        )
    }

    /// Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account(wallet_id: vector<u8>): Object<WalletAccount> {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        object::address_to_object<WalletAccount>(addr)
    }
    // -- Public
    /// Get the signer for a WalletAccount
    public fun get_wallet_account_signer(sender: &signer ,wallet_id: vector<u8>): signer acquires WalletAccount {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);

        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    /// Get the signer for a WalletAccount for the owner
    public fun get_wallet_account_signer_for_owner(
        sender: &signer, 
        wallet_id: vector<u8>
    ): signer acquires WalletAccount, WalletAccountObject {
        assert!(is_owner(signer::address_of(sender), wallet_id), error::permission_denied(E_NOT_OWNER));

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    public inline fun is_owner(
        owner: address, wallet_id: vector<u8>
    ): bool acquires WalletAccount, WalletAccountObject {
        assert!(exists<WalletAccountObject>(owner), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account_object = borrow_global<WalletAccountObject>(owner);
        addr == object::object_address(&wallet_account_object.wallet_account)
    }

    /// Add position opened object to the WalletAccount
    public fun add_position_opened(
        sender: &signer, wallet_id: vector<u8>, position: address
    ) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        access_control::must_be_operator(sender);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        vector::push_back(&mut wallet_account_mut.position_opened, position);
    }

    /// Remove position opened object from the WalletAccount
    /// Use this function when the position is closed
    public fun remove_position_opened(
        sender: &signer, wallet_id: vector<u8>, position: address
    ) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        access_control::must_be_operator(sender);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        let (b, index) = vector::index_of(&wallet_account_mut.position_opened, &position);
        assert!(b, error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        vector::remove(&mut wallet_account_mut.position_opened, index);
    }


    // -- Private

    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_{}", WALLET_ACCOUNT_SEED, wallet_id))
    }

    fun connect_wallet_internal(sender: &signer, wallet_account: &mut WalletAccount) acquires WalletAccount {
        let wallet_address = signer::address_of(sender);
        let wallet_account_addr = get_wallet_account_object_address(wallet_account.wallet_id);
        assert!(object::object_exists<WalletAccount>(wallet_account_addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        assert!(!exists<WalletAccountObject>(wallet_address), error::already_exists(E_WALLET_ACCOUNT_ALREADY_CONNECTED));

        if (option::is_none(&wallet_account.wallet_address)) {
            wallet_account.wallet_address = option::some(wallet_address);
        };

        move_to(
            sender,
            WalletAccountObject {
                wallet_account: get_wallet_account(wallet_account.wallet_id)
            }
        );
        event::emit(
            WalletAccountConnected {
                wallet_id: wallet_account.wallet_id,
                wallet_object: wallet_account_addr,
                wallet_address: wallet_address
            }
        );
    }
}
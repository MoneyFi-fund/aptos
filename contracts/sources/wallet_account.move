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
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};

    use moneyfi::access_control;

    // -- Constants
    const WALLET_ACCOUNT_SEED: vector<u8> = b"WALLET_ACCOUNT";

    // -- Errors
    const E_WALLET_ACCOUNT_EXISTS: u64 = 1;
    const E_WALLET_ACCOUNT_NOT_EXISTS: u64 = 2;

    // -- Structs
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct WalletAccount has key {
        wallet_id: vector<u8>,
        wallet_address: Option<address>,
        assets: Table<address, u64>,
        distributed_assets: Table<address, u64>,
        extend_ref: ExtendRef
    }

    struct WalletAccountObject has key {
        wallet_account: Object<WalletAccount>
    }

    // -- Events
    struct WalletAccountCreated has drop, store {
        wallet_id: vector<u8>,
        wallet_object: Object<WalletAccount>,
    }

    // -- Entries
    /// create a new WalletAccount for a given wallet_id<byte[32]>
    public entry fun create_wallet_account(
        sender: &signer, wallet_id: vector<u8>
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
                wallet_address: option::none<address>(),
                assets: table::new<address, u64>(),
                distributed_assets: table::new<address, u64>(),
                extend_ref: object::generate_extend_ref(constructor_ref)
            }
        );

        // TODO: dispatch event
    }

    /// Connect user wallet to a WalletAccount
    public entry fun connect_wallet(
        sender: &signer, wallet_id: vector<u8>, signature: vector<u8>
    ) acquires WalletAccount {
        let wallet_address = signer::address_of(sender);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(wallet_account_addr));
        assert!(!exists<WalletAccountObject>(wallet_address));

        // TODO: verify signature

        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        if (option::is_none(&wallet_account.wallet_address)) {
            wallet_account.wallet_address = option::some(wallet_address);
        };

        move_to(
            sender,
            WalletAccountObject {
                wallet_account: object::address_to_object(wallet_account_addr)
            }
        );
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
        assert!(exists<WalletAccountObject>(signer::address_of(sender)), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));

        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account_object = borrow_global<WalletAccountObject>(signer::address_of(sender));

        assert!(addr == object::object_address(&wallet_account_object.wallet_account), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    // -- Private
    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_{}", WALLET_ACCOUNT_SEED, wallet_id))
    }
}
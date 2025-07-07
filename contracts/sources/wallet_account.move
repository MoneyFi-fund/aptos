module moneyfi::wallet_account {
    use std::bcs;
    use std::signer;
    use std::vector;
    use std::error;
    use aptos_std::table::{Self, Table};
    use aptos_std::string_utils;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::event;
    use aptos_framework::util;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;

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
    const E_INVALID_ARGUMENT: u64 = 7;
    const E_POSITION_NOT_EXISTS: u64 = 8;
    const E_POSITION_ALREADY_EXISTS: u64 = 9;

    // -- Structs
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct WalletAccount has key {
        wallet_id: vector<u8>,
        source_domain: u32,
        assets: Table<address, u64>,
        distributed_assets: Table<address, u64>,
        position_opened: SimpleMap<address, PositionOpened>,
        extend_ref: ExtendRef
    }

    struct WalletAccountObject has key {
        wallet_account: Object<WalletAccount>
    }  

    struct PositionOpened has copy, drop, store {
        assets: SimpleMap<address, u64>,
        strategy_id: u8,
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

    #[event]
    struct DepositToWalletAccount has drop, store {
        sender: address,
        wallet_object: address,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>
    }

    #[event]
    struct WithdrawFromWalletAccount has drop, store {
        recipient: address,
        wallet_object: address,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>
    }

    #[event]
    struct OpenPosition has drop, store {
        wallet_id: vector<u8>,
        position: address,
        assets: SimpleMap<address, u64>,
        strategy_id: u8
    }

    #[event]
    struct ClosePosition has drop, store {
        wallet_id: vector<u8>,
        position: address,
    }

    #[event]
    struct UpgradePosition has drop, store {
        wallet_id: vector<u8>,
        position: address,
        total_assets: SimpleMap<address, u64>
    }

    // -- Entries
    // create a new WalletAccount for a given wallet_id<byte[32]>
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
                position_opened: simple_map::new<address, PositionOpened>(),
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

    // Connect user wallet to a WalletAccount
//   public entry fun connect_wallet(
//       sender: &signer, wallet_id: vector<u8>, signature: vector<u8>
//   ) acquires WalletAccount {
//
//       // TODO: verify signature
//       //connect_wallet_internal(sender, wallet_id);
//   }

    // Connect Aptos wallet to a WalletAccount
    // This function has to be called before claim assets
    public entry fun connect_aptos_wallet(
        sender: &signer, wallet_id: vector<u8>
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        assert!(wallet_account.source_domain == APT_SRC_DOMAIN, error::invalid_state(E_NOT_APTOS_WALLET_ACCOUNT));
        assert!(signer::address_of(sender) == util::address_from_bytes(wallet_id), error::permission_denied(E_NOT_OWNER));
        connect_wallet_internal(sender, wallet_account);
    }

    public entry fun deposit_to_wallet_account(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            primary_fungible_store::transfer(
                sender,
                asset,
                wallet_account_addr,
                amount,
            );
            if (table::contains(&wallet_account.assets, asset_addr)) {
                let current_amount = table::borrow(&wallet_account.assets, asset_addr);
                table::add(&mut wallet_account.assets, asset_addr, *current_amount + amount);
            } else {
                table::add(&mut wallet_account.assets, asset_addr, amount);
            };
            i = i + 1;
        };
        event::emit(
            DepositToWalletAccount {
                sender: signer::address_of(sender),
                wallet_object: wallet_account_addr,
                assets: assets,
                amounts: amounts
            }
        );
    }

    public entry fun withdraw_from_wallet_account_for_user(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>
    ) acquires WalletAccount , WalletAccountObject {
        if(!is_connected(signer::address_of(sender), wallet_id)) {
            connect_aptos_wallet(sender, wallet_id);
        };
        let object_signer = get_wallet_account_signer_for_owner(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            primary_fungible_store::transfer(
                &object_signer,
                asset,
                signer::address_of(sender),
                amount,
            );
            if (table::contains(&wallet_account.assets, asset_addr)) {
                let current_amount = table::borrow(&wallet_account.assets, asset_addr);
                assert!(*current_amount >= amount, error::invalid_argument(E_INVALID_ARGUMENT));
                if (*current_amount == amount) {
                    table::remove(&mut wallet_account.assets, asset_addr);
                } else {
                    table::add(&mut wallet_account.assets, asset_addr, *current_amount - amount);
                }
            };
            i = i + 1;
        };
        event::emit(
                WithdrawFromWalletAccount {
                    recipient: signer::address_of(sender),
                    wallet_object: wallet_account_addr,
                    assets: assets,
                    amounts: amounts
                }
            );
    }

    public entry fun withdraw_from_wallet_account_for_operator(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>,
        recipient: address,
    ) acquires WalletAccount {
        access_control::must_be_operator(sender);
        let object_signer = get_wallet_account_signer(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        assert!(recipient != signer::address_of(sender), error::invalid_argument(E_INVALID_ARGUMENT));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            primary_fungible_store::transfer(
                &object_signer,
                asset,
                recipient,
                amount,
            );
            if (table::contains(&wallet_account.assets, asset_addr)) {
                let current_amount = table::borrow(&wallet_account.assets, asset_addr);
                assert!(*current_amount >= amount, error::invalid_argument(E_INVALID_ARGUMENT));
                if (*current_amount == amount) {
                    table::remove(&mut wallet_account.assets, asset_addr);
                } else {
                    table::add(&mut wallet_account.assets, asset_addr, *current_amount - amount);
                }
            };
            i = i + 1;
        };
        event::emit(
            WithdrawFromWalletAccount {
                recipient: recipient,
                wallet_object: wallet_account_addr,
                assets: assets,
                amounts: amounts
            }
        );
    }

    // -- Views
    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account_object_address(wallet_id: vector<u8>): address {
        let data_object_addr = access_control::get_data_object_address();
        object::create_object_address(
            &data_object_addr, get_wallet_account_object_seed(wallet_id)
        )
    }

    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account(wallet_id: vector<u8>): Object<WalletAccount> {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        object::address_to_object<WalletAccount>(addr)
    }

    #[view]
    public fun get_position_opened(
        wallet_id: vector<u8>
    ): (vector<address>,vector<PositionOpened>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);

        simple_map::to_vec_pair<address, PositionOpened>(
            wallet_account.position_opened
        )
    }

    #[view]
    public fun is_connected(
        user: address, wallet_id: vector<u8>
    ): bool acquires WalletAccountObject {
        assert!(user == util::address_from_bytes(wallet_id), error::permission_denied(E_NOT_OWNER));
        let addr = get_wallet_account_object_address(wallet_id);
        if (exists<WalletAccountObject>(user)) {
            let wallet_account_object = borrow_global<WalletAccountObject>(user);
            addr == object::object_address(&wallet_account_object.wallet_account)
        } else {
            false
        }
    }

    // -- Public
    // Get the signer for a WalletAccount
    public fun get_wallet_account_signer(sender: &signer ,wallet_id: vector<u8>): signer acquires WalletAccount {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);

        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    //Get the signer for a WalletAccount for the owner
    public fun get_wallet_account_signer_for_owner(
        sender: &signer, 
        wallet_id: vector<u8>
    ): signer acquires WalletAccount, WalletAccountObject {
        let addr = get_wallet_account_object_address(wallet_id);
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

    // Add position opened object to the WalletAccount
    public fun add_position_opened(
        sender: &signer, 
        wallet_id: vector<u8>, 
        position: address, 
        assets: vector<address>, 
        amounts: vector<u64>, 
        strategy_id: u8,
    ) acquires WalletAccount {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        let assets_map = simple_map::new_from<address, u64>(assets, amounts);
        let position_opened = PositionOpened {
            assets: assets_map,
            strategy_id: strategy_id
        };
        assert!(
            !simple_map::contains_key(&wallet_account_mut.position_opened, &position), 
            error::already_exists(E_POSITION_ALREADY_EXISTS)
        );
        simple_map::add(&mut wallet_account_mut.position_opened, position, position_opened);
        event::emit(
            OpenPosition {
                wallet_id: wallet_account_mut.wallet_id,
                position: position,
                assets: assets_map,
                strategy_id: strategy_id
            }
        );
    }

    // Remove position opened object from the WalletAccount
    // Use this function when the position is closed
    public fun remove_position_opened(
        sender: &signer, wallet_id: vector<u8>, position: address
    ) acquires WalletAccount {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        assert!(
            simple_map::contains_key(&wallet_account_mut.position_opened, &position), 
            error::not_found(E_POSITION_NOT_EXISTS)
        );
        simple_map::remove(&mut wallet_account_mut.position_opened, &position);
        event::emit(
            ClosePosition {
                wallet_id: wallet_account_mut.wallet_id,
                position: position
            }
        );
    }

    // Upgrade position opened object in the WalletAccount
    // Use this function when the position is opened and you want to add more assets to it
    public fun upgrage_position_opened(
        sender: &signer, 
        wallet_id: vector<u8>, 
        position: address,
        assets_added: vector<address>,
        amounts_added: vector<u64>
    ) acquires WalletAccount {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        assert!(
            simple_map::contains_key(&wallet_account_mut.position_opened, &position), 
            error::not_found(E_POSITION_NOT_EXISTS)
        );
        assert!(vector::length(&assets_added) == vector::length(&amounts_added),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );
        let position_opened = simple_map::borrow_mut(&mut wallet_account_mut.position_opened, &position);
        let assets_map = &mut position_opened.assets;
        let index = 0;
        while (index < vector::length(&assets_added)) {
            let asset = vector::borrow(&assets_added, index);
            let amount = vector::borrow(&amounts_added, index);
            if (simple_map::contains_key(assets_map, asset)) {
                let current_amount = simple_map::borrow(assets_map, asset);
                simple_map::add(assets_map, *asset, *current_amount + *amount);
            } else {
                simple_map::add(assets_map, *asset, *amount);
            };
            index = index + 1;
        };
        event::emit(
            UpgradePosition {
                wallet_id: wallet_account_mut.wallet_id,
                position: position,
                total_assets: *assets_map
            }
        );
    }

    // -- Private

    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_{}", WALLET_ACCOUNT_SEED, wallet_id))
    }

    fun connect_wallet_internal(sender: &signer, wallet_account: &mut WalletAccount) {
        let wallet_address = signer::address_of(sender);
        let wallet_account_addr = get_wallet_account_object_address(wallet_account.wallet_id);
        assert!(object::object_exists<WalletAccount>(wallet_account_addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        assert!(!exists<WalletAccountObject>(wallet_address), error::already_exists(E_WALLET_ACCOUNT_ALREADY_CONNECTED));
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
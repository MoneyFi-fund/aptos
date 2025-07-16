module moneyfi::storage {
    use std::vector;
    use std::error;
    use aptos_framework::event;
    use aptos_framework::timestamp::now_seconds;
    use aptos_framework::object::{
        Self,
        Object,
        ObjectCore,
        TransferRef,
        ExtendRef
    };

    use moneyfi::access_control;

    friend moneyfi::wallet_account;
    friend moneyfi::fee_manager;

    //-- ERROR
    const E_INVALID_ARGUMENT: u64 = 1;
    const E_ASSET_NOT_SUPPORTED: u64 = 2;

    struct Storage has key {
        object: Object<ObjectCore>,
        extend_ref: ExtendRef,
        transfer_ref: TransferRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct SupportedAsset has key {
        asset_supported: vector<address>
    }
    //-- EVENTS
    #[event]
    struct AddAssetSupportedEvent has drop, store {
        asset_addr: address,
        timestamp: u64
    }

    #[event]
    struct RemoveAssetSupportedEvent has drop, store {
        asset_addr: address,
        timestamp: u64
    }

    fun init_module(sender: &signer) {
        let constructor_ref = &object::create_sticky_object(@moneyfi);

        let transfer_ref = object::generate_transfer_ref(constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        move_to(
            &object::generate_signer(constructor_ref),
            SupportedAsset {
                asset_supported: vector::empty<address>()
            }
        );
        move_to(
            sender,
            Storage {
                object: object::object_from_constructor_ref(constructor_ref),
                extend_ref: object::generate_extend_ref(constructor_ref),
                transfer_ref
            }
        );
    }

    // -- Entries

    public entry fun transfer(sender: &signer, new_owner: address) acquires Storage {
        access_control::must_be_admin(sender);

        let storage = borrow_global<Storage>(@moneyfi);
        let linear_transfer_ref =
            object::generate_linear_transfer_ref(&storage.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, new_owner);

        // TODO: distpatch event?
    }

    public entry fun add_asset_supported(
        sender: &signer, metadata_addr: address
    ) acquires SupportedAsset, Storage {
        access_control::must_be_admin(sender);
        let config = borrow_global_mut<SupportedAsset>(get_address());
        if (!vector::contains(&config.asset_supported, &metadata_addr)) {
            vector::push_back(&mut config.asset_supported, metadata_addr);

            // Emit event
            event::emit(
                AddAssetSupportedEvent {
                    asset_addr: metadata_addr,
                    timestamp: now_seconds()
                }
            );
        };
    }

    public entry fun remove_asset_supported(
        sender: &signer, metadata_addr: address
    ) acquires SupportedAsset, Storage {
        access_control::must_be_admin(sender);
        let config = borrow_global_mut<SupportedAsset>(get_address());
        let (found, index) = vector::index_of(&config.asset_supported, &metadata_addr);
        if (found) {
            vector::remove(&mut config.asset_supported, index);

            // Emit event
            event::emit(
                RemoveAssetSupportedEvent {
                    asset_addr: metadata_addr,
                    timestamp: now_seconds()
                }
            );
        };
    }

    //-- Views
    #[view]
    public fun get_asset_supported(): vector<address> acquires SupportedAsset {
        let config = borrow_global<SupportedAsset>(get_address());
        config.asset_supported
    }

    public fun get_address(): address acquires Storage {
        let storage = borrow_global<Storage>(@moneyfi);

        object::object_address(&storage.object)
    }

    // -- Private

    public(friend) fun get_signer(): signer acquires Storage {
        let storage = borrow_global<Storage>(@moneyfi);

        object::generate_signer_for_extending(&storage.extend_ref)
    }

    public(friend) fun create_child_object(seed: vector<u8>): ExtendRef acquires Storage {
        let signer = get_signer();

        let constructor_ref = &object::create_named_object(&signer, seed);
        let transfer_ref = object::generate_transfer_ref(constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        object::generate_extend_ref(constructor_ref)
    }

    public fun check_asset_supported(asset: address) acquires SupportedAsset, Storage{
        let config = borrow_global<SupportedAsset>(get_address());
        assert!(
            vector::contains(&config.asset_supported, &asset),
            error::invalid_argument(E_ASSET_NOT_SUPPORTED)
        );
    }

    // -- Test only
    #[test_only]
    public fun init_module_for_testing(sender: &signer) {
        init_module(sender)
    }
}

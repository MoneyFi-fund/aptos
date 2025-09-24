module moneyfi::storage {
    use std::signer;
    use aptos_framework::object::{Self, Object, ObjectCore, TransferRef, ExtendRef};

    use moneyfi::access_control;

    const PHANTOM_OBJECT_SEED: vector<u8> = b"storage::PHANTOM_OBJECT";

    struct Storage has key {
        object: Object<ObjectCore>,
        extend_ref: ExtendRef,
        transfer_ref: TransferRef
    }

    fun init_module(sender: &signer) {
        assert!(signer::address_of(sender) == @moneyfi);
        let constructor_ref = &object::create_sticky_object(@moneyfi);

        let transfer_ref = object::generate_transfer_ref(constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);
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
        transfer_ownership(&storage.transfer_ref, new_owner);

        // TODO: distpatch event?
    }

    // -- Public

    public fun get_address(): address acquires Storage {
        let storage = borrow_global<Storage>(@moneyfi);

        object::object_address(&storage.object)
    }

    public fun get_child_object_address(seed: vector<u8>): address acquires Storage {
        object::create_object_address(&get_address(), seed)
    }

    /// Creates a child object using the provided seed.
    /// Note: If the child object is intended to hold a fungible asset, use `create_child_object_with_phantom_owner` instead.
    public fun create_child_object(seed: vector<u8>): ExtendRef acquires Storage {
        let (extend_ref, _) = create_child_object_impl(seed);

        extend_ref
    }

    /// Creates a child object with a phantom owner, meaning the object does not have a real owner.
    /// This ensures that only the child object itself can transfer tokens from its fungible asset store.
    public fun create_child_object_with_phantom_owner(seed: vector<u8>): ExtendRef acquires Storage {
        let (extend_ref, transfer_ref) = create_child_object_impl(seed);

        // transfer ownership to phantom object
        let phantom_object_addr = get_child_object_address(PHANTOM_OBJECT_SEED);
        transfer_ownership(&transfer_ref, phantom_object_addr);

        extend_ref
    }

    // -- Private

    fun get_signer(): signer acquires Storage {
        let storage = borrow_global<Storage>(@moneyfi);

        object::generate_signer_for_extending(&storage.extend_ref)
    }

    fun create_child_object_impl(seed: vector<u8>): (ExtendRef, TransferRef) acquires Storage {
        assert!(seed != PHANTOM_OBJECT_SEED);

        let storage_signer = get_signer();
        let constructor_ref = &object::create_named_object(&storage_signer, seed);
        let transfer_ref = object::generate_transfer_ref(constructor_ref);
        object::disable_ungated_transfer(&transfer_ref);

        (object::generate_extend_ref(constructor_ref), transfer_ref)
    }

    fun transfer_ownership(transfer_ref: &TransferRef, to: address) {
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, to);
    }

    // -- Test only

    #[test_only]
    public fun init_module_for_testing(sender: &signer) {
        init_module(sender)
    }
}

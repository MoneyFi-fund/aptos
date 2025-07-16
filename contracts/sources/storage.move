module moneyfi::storage {
    use aptos_framework::object::{
        Self,
        Object,
        ObjectCore,
        ConstructorRef,
        TransferRef,
        ExtendRef
    };

    use moneyfi::access_control;

    friend moneyfi::wallet_account;

    struct Storage has key {
        object: Object<ObjectCore>,
        extend_ref: ExtendRef,
        transfer_ref: TransferRef
    }

    fun init_module(sender: &signer) {
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
        let linear_transfer_ref =
            object::generate_linear_transfer_ref(&storage.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, new_owner);

        // TODO: distpatch event?
    }

    public fun get_address(): address acquires Storage {
        let storage = borrow_global<Storage>(@moneyfi);

        object::object_address(&storage.object)
    }

    // -- Private

    fun get_signer(): signer acquires Storage {
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

    // -- Test only
    #[test_only]
    public fun init_module_for_testing(sender: &signer) {
        init_module(sender)
    }
}

module moneyfi::access_control {
    use std::signer;
    use std::vector;
    use std::error;
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_std::table::{Self, Table};

    friend moneyfi::wallet_account;
    friend moneyfi::vault;

    // -- Roles

    /// Only admin can manage roles
    const ROLE_ADMIN: u8 = 1;
    /// Operator is wallet that owned by backend service
    const ROLE_OPERATOR: u8 = 2;
    const ROLE_DELEGATOR_ADMIN: u8 = 3;

    // -- Error Codes
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_NOT_AUTHORIZED: u64 = 2;
    const E_INVALID_ROLE: u64 = 3;

    // -- Structs
    struct RoleRegistry has key {
        accounts: vector<address>,
        roles: Table<address, u8>
    }

    struct Item has drop {
        account: address,
        role: u8
    }

    struct Config has key {
        paused: bool,
        data_object: Object<ObjectCore>,
        data_object_extend_ref: ExtendRef
    }

    #[test_only]
    friend moneyfi::access_control_test;

    fun init_module(sender: &signer) {
        initialize(sender)
    }

    // -- Entries

    public entry fun set_role(sender: &signer, addr: address, role: u8) acquires RoleRegistry {
        assert!(
            role == ROLE_ADMIN
                || role == ROLE_OPERATOR
                || role == ROLE_DELEGATOR_ADMIN,
            E_INVALID_ROLE
        );
        must_be_admin(sender);

        let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
        if (!table::contains(&registry.roles, addr)) {
            vector::push_back(&mut registry.accounts, addr);
        };

        table::upsert(&mut registry.roles, addr, role);

        // TODO: dispatch event
    }

    public entry fun revoke(sender: &signer, addr: address) acquires RoleRegistry {
        must_be_admin(sender);

        let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
        if (table::contains(&registry.roles, addr)) {
            table::remove(&mut registry.roles, addr);

            // TODO: dispatch event
        }
    }

    // -- Views

    #[view]
    public fun get_accounts(): vector<Item> acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);
        let items = vector::empty<Item>();

        let len = vector::length(&registry.accounts);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&registry.accounts, i);
            if (table::contains(&registry.roles, addr)) {
                let role = *table::borrow(&registry.roles, addr);
                let item = Item { account: addr, role };
                vector::push_back(&mut items, item);
            };
            i = i + 1;
        };

        items
    }

    // -- Public

    public fun must_be_admin(sender: &signer) acquires RoleRegistry {
        let addr = signer::address_of(sender);

        assert!(has_role(addr, ROLE_ADMIN), error::permission_denied(E_NOT_AUTHORIZED))
    }

    public fun must_be_operator(sender: &signer) acquires RoleRegistry {
        let addr = signer::address_of(sender);

        assert!(has_role(addr, ROLE_OPERATOR), error::permission_denied(E_NOT_AUTHORIZED))
    }

    public fun must_be_delegator(sender: &signer) acquires RoleRegistry {
        let addr = signer::address_of(sender);

        assert!(has_role(addr, ROLE_DELEGATOR_ADMIN), error::permission_denied(E_NOT_AUTHORIZED))
    }

    public fun get_data_object_address(): address acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        object::object_address(&config.data_object)
    } 

    // -- Private

    public(friend) fun initialize(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(!exists<RoleRegistry>(addr) && !exists<Config>(addr), E_ALREADY_INITIALIZED);

        let admin_addr =
            if (object::is_object(addr)) {
                object::owner(object::address_to_object<ObjectCore>(addr))
            } else { addr };

        let roles = table::new<address, u8>();
        table::add(&mut roles, admin_addr, ROLE_ADMIN);
        table::add(&mut roles, admin_addr, ROLE_DELEGATOR_ADMIN);
        table::add(&mut roles, admin_addr, ROLE_OPERATOR);

        let accounts = vector::singleton<address>(admin_addr);

        // init default config
        let constructor_ref = &object::create_sticky_object(@moneyfi);

        move_to(
            sender,
            Config {
                paused: false,
                data_object: object::object_from_constructor_ref(constructor_ref),
                data_object_extend_ref: object::generate_extend_ref(constructor_ref)
            }
        );

        move_to(sender, RoleRegistry { roles, accounts });
    }
    public(friend) fun get_object_data_signer(): signer acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        object::generate_signer_for_extending(&config.data_object_extend_ref)
    }

    fun has_role(addr: address, role: u8): bool acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);

        if (table::contains(&registry.roles, addr)) {
            table::borrow(&registry.roles, addr) == &role
        } else { false }
    }
}

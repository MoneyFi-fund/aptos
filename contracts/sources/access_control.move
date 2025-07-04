module moneyfi::access_control {
    use std::signer;
    use std::vector;
    use std::object::{Self, ObjectCore};
    use aptos_std::table::{Self, Table};

    // -- Roles

    /// Only admin can manage roles
    const ROLE_ADMIN: u8 = 1;
    /// Operator is wallet that owned by backend service
    const ROLE_OPERATOR: u8 = 2;
    const ROLE_DELEGATOR: u8 = 3;

    // -- Error Codes
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_NOT_AUTHORIZED: u64 = 2;
    const E_INVALID_ROLE: u64 = 3;

    struct RoleRegistry has key {
        accounts: vector<address>,
        roles: Table<address, u8>
    }

    struct Item has drop {
        account: address,
        role: u8
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
                || role == ROLE_DELEGATOR,
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

        assert!(has_role(addr, ROLE_ADMIN), E_NOT_AUTHORIZED)
    }

    public fun must_be_operator(sender: &signer) acquires RoleRegistry {
        let addr = signer::address_of(sender);

        assert!(has_role(addr, ROLE_OPERATOR), E_NOT_AUTHORIZED)
    }

    public fun must_be_delegator(sender: &signer) acquires RoleRegistry {
        let addr = signer::address_of(sender);

        assert!(has_role(addr, ROLE_DELEGATOR), E_NOT_AUTHORIZED)
    }

    // -- Private

    public(friend) fun initialize(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(!exists<RoleRegistry>(addr), E_ALREADY_INITIALIZED);

        let admin_addr =
            if (object::is_object(addr)) {
                object::owner(object::address_to_object<ObjectCore>(addr))
            } else { addr };

        let roles = table::new<address, u8>();
        table::add(&mut roles, admin_addr, ROLE_ADMIN);
        let accounts = vector::singleton<address>(admin_addr);

        move_to(sender, RoleRegistry { roles, accounts });
    }

    fun has_role(addr: address, role: u8): bool acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);

        if (table::contains(&registry.roles, addr)) {
            table::borrow(&registry.roles, addr) == &role
        } else { false }
    }
}

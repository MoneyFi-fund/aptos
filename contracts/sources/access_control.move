module moneyfi::access_control {
    use std::signer;
    use std::vector;
    use std::error;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_std::table::{Self, Table};

    friend moneyfi::wallet_account;
    friend moneyfi::hyperion;

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

    struct SystemFee has key {
        distribute_fee: SimpleMap<address, u64>,
        withdraw_fee: SimpleMap<address, u64>,
        rebalance_fee: SimpleMap<address, u64>,
        referral_fee: SimpleMap<address, u64>,
        protocol_fee: SimpleMap<address, u64>
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

        assert!(
            has_role(addr, ROLE_OPERATOR), error::permission_denied(E_NOT_AUTHORIZED)
        )
    }

    public fun must_be_delegator(sender: &signer) acquires RoleRegistry {
        let addr = signer::address_of(sender);

        assert!(
            has_role(addr, ROLE_DELEGATOR_ADMIN),
            error::permission_denied(E_NOT_AUTHORIZED)
        )
    }

    public fun get_data_object_address(): address acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        object::object_address(&config.data_object)
    }

    public fun is_operator(addr: address): bool acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);

        if (table::contains(&registry.roles, addr)) {
            table::borrow(&registry.roles, addr) == &ROLE_OPERATOR
        } else { false }
    }

    public fun is_sever(addr: address): bool acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        object::is_object(addr)
            && object::address_to_object<ObjectCore>(addr) == config.data_object
    }

    public fun add_distribute_fee(
        sender: &signer, addr: address, amount: u64
    ) acquires SystemFee, Config {
        is_sever(signer::address_of(sender));
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.distribute_fee, &addr)) {
            simple_map::add(&mut system_fee.distribute_fee, addr, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.distribute_fee, &addr);
            simple_map::upsert(
                &mut system_fee.distribute_fee, addr, current_amount + amount
            );
        };
    }

    public fun add_withdraw_fee(
        sender: &signer, addr: address, amount: u64
    ) acquires SystemFee, Config {
        is_sever(signer::address_of(sender));
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.withdraw_fee, &addr)) {
            simple_map::add(&mut system_fee.withdraw_fee, addr, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.withdraw_fee, &addr);
            simple_map::upsert(
                &mut system_fee.withdraw_fee, addr, current_amount + amount
            );
        };
    }

    public fun add_rebalance_fee(
        sender: &signer, addr: address, amount: u64
    ) acquires SystemFee, Config {
        is_sever(signer::address_of(sender));
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.rebalance_fee, &addr)) {
            simple_map::add(&mut system_fee.rebalance_fee, addr, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.rebalance_fee, &addr);
            simple_map::upsert(
                &mut system_fee.rebalance_fee, addr, current_amount + amount
            );
        };
    }

    public fun add_referral_fee(
        sender: &signer, addr: address, amount: u64
    ) acquires SystemFee, Config {
        is_sever(signer::address_of(sender));
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.referral_fee, &addr)) {
            simple_map::add(&mut system_fee.referral_fee, addr, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.referral_fee, &addr);
            simple_map::upsert(
                &mut system_fee.referral_fee, addr, current_amount + amount
            );
        };
    }

    public fun add_protocol_fee(
        sender: &signer, addr: address, amount: u64
    ) acquires SystemFee, Config {
        is_sever(signer::address_of(sender));
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.protocol_fee, &addr)) {
            simple_map::add(&mut system_fee.protocol_fee, addr, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.protocol_fee, &addr);
            simple_map::upsert(
                &mut system_fee.protocol_fee, addr, current_amount + amount
            );
        };
    }

    // -- Private

    public(friend) fun initialize(sender: &signer) {
        let addr = signer::address_of(sender);
        assert!(
            !exists<RoleRegistry>(addr) && !exists<Config>(addr),
            E_ALREADY_INITIALIZED
        );

        let admin_addr =
            if (object::is_object(addr)) {
                object::owner(object::address_to_object<ObjectCore>(addr))
            } else { addr };

        let roles = table::new<address, u8>();
        table::add(&mut roles, admin_addr, ROLE_ADMIN);

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

        move_to(
            &object::generate_signer(constructor_ref),
            SystemFee {
                distribute_fee: simple_map::new<address, u64>(),
                withdraw_fee: simple_map::new<address, u64>(),
                rebalance_fee: simple_map::new<address, u64>(),
                referral_fee: simple_map::new<address, u64>(),
                protocol_fee: simple_map::new<address, u64>()
            }
        );

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

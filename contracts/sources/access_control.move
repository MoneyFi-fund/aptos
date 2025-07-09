module moneyfi::access_control {
    use std::signer;
    use std::vector;
    use std::error;
    use std::option;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;

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
        roles: SimpleMap<address, vector<u8>>
    }

    struct Item has drop {
        account: address,
        role: u8
    }

    struct Config has key {
        paused: bool,
        data_object: Object<ObjectCore>,
        data_object_extend_ref: ExtendRef,
        stablecoin_metadata: Object<Metadata>
    }

    struct SystemFee has key {
        distribute_fee: SimpleMap<address, u64>,
        withdraw_fee: SimpleMap<address, u64>,
        rebalance_fee: SimpleMap<address, u64>,
        referral_fee: SimpleMap<address, u64>,
        protocol_fee: SimpleMap<address, u64>,
        fee_to: address,
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
        if (!simple_map::contains_key(&registry.roles, &addr)) {
            vector::push_back(&mut registry.accounts, addr);
            simple_map::add(&mut registry.roles, addr, vector::empty<u8>());
        };

        let roles = simple_map::borrow_mut(&mut registry.roles, &addr);
        if (!vector::contains(roles, &role)) {
            vector::push_back(roles, role);
        };

        // TODO: dispatch event
    }

    public entry fun claim_fees(
        sender: &signer,
        asset: Object<Metadata>,
        amount: u64
    ) acquires SystemFee, Config, RoleRegistry {
        must_be_delegator(sender);
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        let object_signer = get_object_data_signer();
        primary_fungible_store::transfer(
            &object_signer,
            asset,
            system_fee.fee_to,
            amount
        );
        //Event

    }

    public entry fun set_fee_to(sender: &signer, addr: address) acquires SystemFee, RoleRegistry {
        must_be_admin(sender);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        system_fee.fee_to = addr;
    }

    public entry fun revoke_role(sender: &signer, addr: address, role: u8) acquires RoleRegistry {
        must_be_admin(sender);

        let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
        if (simple_map::contains_key(&registry.roles, &addr)) {
            let roles = simple_map::borrow_mut(&mut registry.roles, &addr);
            let (found, index) = vector::index_of(roles, &role);
            if (found) {
                vector::remove(roles, index);
            };

            // If no roles left, remove the address completely
            if (vector::is_empty(roles)) {
                simple_map::remove(&mut registry.roles, &addr);
                let (found, index) = vector::index_of(&registry.accounts, &addr);
                if (found) {
                    vector::remove(&mut registry.accounts, index);
                };
            };

            // TODO: dispatch event
        }
    }

    public entry fun revoke_all_roles(sender: &signer, addr: address) acquires RoleRegistry {
        must_be_admin(sender);

        let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
        if (simple_map::contains_key(&registry.roles, &addr)) {
            simple_map::remove(&mut registry.roles, &addr);
            let (found, index) = vector::index_of(&registry.accounts, &addr);
            if (found) {
                vector::remove(&mut registry.accounts, index);
            };

            // TODO: dispatch event
        }
    }

    public entry fun set_stablecoin_metadata(
        sender: &signer, metadata: Object<Metadata>
    ) acquires Config, RoleRegistry {
        must_be_delegator(sender);
        let config = borrow_global_mut<Config>(@moneyfi);
        config.stablecoin_metadata = metadata;
    }

    // -- Views
    #[view]
    public fun get_stablecoin_metadata(): Object<Metadata> acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        config.stablecoin_metadata
    }

    #[view]
    public fun get_accounts(): vector<Item> acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);
        let items = vector::empty<Item>();

        let len = vector::length(&registry.accounts);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(&registry.accounts, i);
            if (simple_map::contains_key(&registry.roles, &addr)) {
                let roles = simple_map::borrow(&registry.roles, &addr);
                let role_len = vector::length(roles);
                let j = 0;
                while (j < role_len) {
                    let role = *vector::borrow(roles, j);
                    let item = Item { account: addr, role };
                    vector::push_back(&mut items, item);
                    j = j + 1;
                };
            };
            i = i + 1;
        };

        items
    }

    #[view]
    public fun get_user_roles(addr: address): vector<u8> acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);
        if (simple_map::contains_key(&registry.roles, &addr)) {
            *simple_map::borrow(&registry.roles, &addr)
        } else {
            vector::empty<u8>()
        }
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
        has_role(addr, ROLE_OPERATOR)
    }

    public fun is_sever(addr: address): bool acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        object::is_object(addr)
            && object::address_to_object<ObjectCore>(addr) == config.data_object
    }

    public fun add_distribute_fee(
        sender: &signer, addr: address, amount: u64
    ) acquires SystemFee, Config {
        assert!(is_sever(signer::address_of(sender)), error::permission_denied(E_NOT_AUTHORIZED));
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
        sender: &signer,
        addr: address,
        amount: u64
    ) acquires SystemFee, Config { 
        assert!(is_sever(signer::address_of(sender)), error::permission_denied(E_NOT_AUTHORIZED));
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
        assert!(is_sever(signer::address_of(sender)), error::permission_denied(E_NOT_AUTHORIZED));
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
        assert!(is_sever(signer::address_of(sender)), error::permission_denied(E_NOT_AUTHORIZED));
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
        assert!(is_sever(signer::address_of(sender)), error::permission_denied(E_NOT_AUTHORIZED));
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

        let roles = simple_map::new<address, vector<u8>>();
        let admin_roles = vector::empty<u8>();
        vector::push_back(&mut admin_roles, ROLE_ADMIN);
        vector::push_back(&mut admin_roles, ROLE_DELEGATOR_ADMIN);
        vector::push_back(&mut admin_roles, ROLE_OPERATOR);
        simple_map::add(&mut roles, admin_addr, admin_roles);

        let accounts = vector::singleton<address>(admin_addr);

        // init default config
        let constructor_ref = &object::create_sticky_object(@moneyfi);
        let aptos_coin_metadata = coin::paired_metadata<AptosCoin>();
        move_to(
            sender,
            Config {
                paused: false,
                data_object: object::object_from_constructor_ref(constructor_ref),
                data_object_extend_ref: object::generate_extend_ref(constructor_ref),
                stablecoin_metadata: option::destroy_some<Object<Metadata>>(aptos_coin_metadata),
            }
        );

        move_to(sender, RoleRegistry { roles, accounts });

        move_to(sender, SystemFee {
            distribute_fee: simple_map::new<address, u64>(),
            withdraw_fee: simple_map::new<address, u64>(),
            rebalance_fee: simple_map::new<address, u64>(),
            referral_fee: simple_map::new<address, u64>(),
            protocol_fee: simple_map::new<address, u64>(),
            fee_to: admin_addr,
        });
    }


    public(friend) fun get_object_data_signer(): signer acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        object::generate_signer_for_extending(&config.data_object_extend_ref)
    }

    fun has_role(addr: address, role: u8): bool acquires RoleRegistry {
        let registry = borrow_global<RoleRegistry>(@moneyfi);

        if (simple_map::contains_key(&registry.roles, &addr)) {
            let roles = simple_map::borrow(&registry.roles, &addr);
            vector::contains(roles, &role)
        } else { false }
    }
}
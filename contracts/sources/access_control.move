module moneyfi::access_control {
    use std::signer;
    use std::vector;
    use std::error;
    use std::option;
    use aptos_std::math64;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::object::{Self, Object, ObjectCore, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::event;
    use aptos_framework::timestamp::now_seconds;

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
    const E_INVALID_ARGUMENT: u64 = 4;
    const E_ASSET_NOT_SUPPORTED: u64 = 5;

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
        asset_supported: vector<address>
    }

    struct Fee has key {
        protocol_fee_rate: u64,
        referral_fee_rate: u64,
        denominator: u64
    }

    struct SystemFee has key {
        distribute_fee: SimpleMap<address, u64>,
        withdraw_fee: SimpleMap<address, u64>,
        rebalance_fee: SimpleMap<address, u64>,
        referral_fee: SimpleMap<address, u64>,
        pending_referral_fee: SimpleMap<address, u64>,
        protocol_fee: SimpleMap<address, u64>,
        pending_protocol_fee: SimpleMap<address, u64>,
        fee_to: address
    }

    //-- Event
    #[event]
    struct SetRoleEvent has drop, store {
        addr: address,
        role: u8,
        timestamp: u64
    }

    #[event]
    struct SetFeeToEvent has drop, store {
        addr: address,
        timestamp: u64
    }

    #[event]
    struct SetProtocolFeeEvent has drop, store {
        delegator_admin: address,
        protocol_fee_rate: u64,
        timestamp: u64
    }

    #[event]
    struct SetReferralFeeEvent has drop, store {
        delegator_admin: address,
        referral_fee_rate: u64,
        timestamp: u64
    }

    #[event]
    struct RevokeRoleEvent has drop, store {
        addr: address,
        role: u8,
        timestamp: u64
    }

    #[event]
    struct ClaimFeeEvent has drop, store {
        asset: address,
        amount: u64,
        timestamp: u64
    }

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

    // -- Entries
    fun init_module(sender: &signer) {
        initialize(sender)
    }

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

        // Emit event
        event::emit(SetRoleEvent { addr, role, timestamp: now_seconds() });
    }

    public entry fun claim_fees(
        sender: &signer, asset: Object<Metadata>, amount: u64
    ) acquires SystemFee, Config, RoleRegistry {
        must_be_delegator(sender);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        let object_signer = get_object_data_signer();
        let asset_addr = object::object_address(&asset);

        // Reset pending referral fee to 0
        if (simple_map::contains_key(&system_fee.pending_referral_fee, &asset_addr)) {
            simple_map::upsert(&mut system_fee.pending_referral_fee, asset_addr, 0);
        };
        // Reset pending protocol fee to 0
        if (simple_map::contains_key(&system_fee.pending_protocol_fee, &asset_addr)) {
            simple_map::upsert(&mut system_fee.pending_protocol_fee, asset_addr, 0);
        };

        primary_fungible_store::transfer(
            &object_signer,
            asset,
            system_fee.fee_to,
            amount
        );

        // Emit event
        event::emit(ClaimFeeEvent { asset: asset_addr, amount, timestamp: now_seconds() });
    }

    public entry fun set_fee_to(sender: &signer, addr: address) acquires SystemFee, RoleRegistry {
        must_be_admin(sender);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        system_fee.fee_to = addr;

        // Emit event
        event::emit(SetFeeToEvent { addr, timestamp: now_seconds() });
    }

    public entry fun revoke_role(sender: &signer, addr: address, role: u8) acquires RoleRegistry {
        must_be_admin(sender);

        let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
        if (simple_map::contains_key(&registry.roles, &addr)) {
            let roles = simple_map::borrow_mut(&mut registry.roles, &addr);
            let (found, index) = vector::index_of(roles, &role);
            if (found) {
                vector::remove(roles, index);

                // Emit event only if role was actually removed
                event::emit(RevokeRoleEvent { addr, role, timestamp: now_seconds() });
            };

            // If no roles left, remove the address completely
            if (vector::is_empty(roles)) {
                simple_map::remove(&mut registry.roles, &addr);
                let (found, index) = vector::index_of(&registry.accounts, &addr);
                if (found) {
                    vector::remove(&mut registry.accounts, index);
                };
            };
        }
    }

    public entry fun revoke_all_roles(sender: &signer, addr: address) acquires RoleRegistry {
        must_be_admin(sender);

        let registry = borrow_global_mut<RoleRegistry>(@moneyfi);
        if (simple_map::contains_key(&registry.roles, &addr)) {
            // Get all roles before removing to emit events
            let roles = *simple_map::borrow(&registry.roles, &addr);

            simple_map::remove(&mut registry.roles, &addr);
            let (found, index) = vector::index_of(&registry.accounts, &addr);
            if (found) {
                vector::remove(&mut registry.accounts, index);
            };

            // Emit revoke event for each role
            let i = 0;
            let len = vector::length(&roles);
            while (i < len) {
                let role = *vector::borrow(&roles, i);
                event::emit(RevokeRoleEvent { addr, role, timestamp: now_seconds() });
                i = i + 1;
            };
        }
    }

    public entry fun add_asset_supported(
        sender: &signer, metadata_addr: address
    ) acquires Config, RoleRegistry {
        must_be_delegator(sender);
        let config = borrow_global_mut<Config>(@moneyfi);
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
    ) acquires Config, RoleRegistry {
        must_be_delegator(sender);
        let config = borrow_global_mut<Config>(@moneyfi);
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

    public entry fun set_protocol_fee_rate(sender: &signer, rate: u64) acquires Fee, RoleRegistry {
        must_be_delegator(sender);
        let fee = borrow_global_mut<Fee>(@moneyfi);
        assert!(rate <= 10000, error::invalid_argument(E_INVALID_ARGUMENT));
        fee.protocol_fee_rate = rate;

        // Emit event
        event::emit(
            SetProtocolFeeEvent {
                delegator_admin: signer::address_of(sender),
                protocol_fee_rate: rate,
                timestamp: now_seconds()
            }
        );
    }

    public entry fun set_referral_fee_rate(sender: &signer, rate: u64) acquires Fee, RoleRegistry {
        must_be_delegator(sender);
        let fee = borrow_global_mut<Fee>(@moneyfi);
        assert!(rate <= 10000, error::invalid_argument(E_INVALID_ARGUMENT));
        fee.referral_fee_rate = rate;

        // Emit event
        event::emit(
            SetReferralFeeEvent {
                delegator_admin: signer::address_of(sender),
                referral_fee_rate: rate,
                timestamp: now_seconds()
            }
        );
    }

    // -- Views
    #[view]
    public fun get_asset_supported(): vector<address> acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        config.asset_supported
    }

    #[view]
    public fun get_pending_referral_fee(): (vector<address>, vector<u64>) acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        simple_map::to_vec_pair(system_fee.pending_referral_fee)
    }

    #[view]
    public fun get_pending_protocol_fee(): (vector<address>, vector<u64>) acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        simple_map::to_vec_pair(system_fee.pending_protocol_fee)
    }

    #[view]
    public fun get_fee_to(): address acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        system_fee.fee_to
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

    public fun calculate_protocol_fee(amount: u64): u64 acquires Fee {
        let fee = borrow_global<Fee>(@moneyfi);
        math64::mul_div(amount, fee.protocol_fee_rate, fee.denominator)
    }

    public fun calculate_referral_fee(protocol_fee: u64): u64 acquires Fee {
        let fee = borrow_global<Fee>(@moneyfi);
        math64::mul_div(protocol_fee, fee.referral_fee_rate, fee.denominator)
    }

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
        sender: &signer, asset: address, amount: u64
    ) acquires SystemFee, Config {
        assert!(
            is_sever(signer::address_of(sender)),
            error::permission_denied(E_NOT_AUTHORIZED)
        );
        check_asset_supported(asset);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.distribute_fee, &asset)) {
            simple_map::add(&mut system_fee.distribute_fee, asset, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.distribute_fee, &asset);
            simple_map::upsert(
                &mut system_fee.distribute_fee, asset, current_amount + amount
            );
        };
    }

    public fun add_withdraw_fee(
        sender: &signer, asset: address, amount: u64
    ) acquires SystemFee, Config {
        assert!(
            is_sever(signer::address_of(sender)),
            error::permission_denied(E_NOT_AUTHORIZED)
        );
        check_asset_supported(asset);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.withdraw_fee, &asset)) {
            simple_map::add(&mut system_fee.withdraw_fee, asset, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.withdraw_fee, &asset);
            simple_map::upsert(
                &mut system_fee.withdraw_fee, asset, current_amount + amount
            );
        };
    }

    public fun add_rebalance_fee(
        sender: &signer, asset: address, amount: u64
    ) acquires SystemFee, Config {
        assert!(
            is_sever(signer::address_of(sender)),
            error::permission_denied(E_NOT_AUTHORIZED)
        );
        check_asset_supported(asset);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!simple_map::contains_key(&system_fee.rebalance_fee, &asset)) {
            simple_map::add(&mut system_fee.rebalance_fee, asset, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.rebalance_fee, &asset);
            simple_map::upsert(
                &mut system_fee.rebalance_fee, asset, current_amount + amount
            );
        };
    }

    public fun add_referral_fee(
        sender: &signer, asset: address, amount: u64
    ) acquires SystemFee, Config {
        assert!(
            is_sever(signer::address_of(sender)),
            error::permission_denied(E_NOT_AUTHORIZED)
        );
        check_asset_supported(asset);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);

        // Add to referral_fee
        if (!simple_map::contains_key(&system_fee.referral_fee, &asset)) {
            simple_map::add(&mut system_fee.referral_fee, asset, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.referral_fee, &asset);
            simple_map::upsert(
                &mut system_fee.referral_fee, asset, current_amount + amount
            );
        };

        // Add to pending_referral_fee
        if (!simple_map::contains_key(&system_fee.pending_referral_fee, &asset)) {
            simple_map::add(&mut system_fee.pending_referral_fee, asset, amount);
        } else {
            let current_pending =
                *simple_map::borrow(&system_fee.pending_referral_fee, &asset);
            simple_map::upsert(
                &mut system_fee.pending_referral_fee, asset, current_pending + amount
            );
        };
    }

    public fun add_protocol_fee(
        sender: &signer, asset: address, amount: u64
    ) acquires SystemFee, Config {
        assert!(
            is_sever(signer::address_of(sender)),
            error::permission_denied(E_NOT_AUTHORIZED)
        );
        check_asset_supported(asset);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);

        // Add to protocol_fee
        if (!simple_map::contains_key(&system_fee.protocol_fee, &asset)) {
            simple_map::add(&mut system_fee.protocol_fee, asset, amount);
        } else {
            let current_amount = *simple_map::borrow(&system_fee.protocol_fee, &asset);
            simple_map::upsert(
                &mut system_fee.protocol_fee, asset, current_amount + amount
            );
        };

        // Add to pending_protocol_fee
        if (!simple_map::contains_key(&system_fee.pending_protocol_fee, &asset)) {
            simple_map::add(&mut system_fee.pending_protocol_fee, asset, amount);
        } else {
            let current_pending =
                *simple_map::borrow(&system_fee.pending_protocol_fee, &asset);
            simple_map::upsert(
                &mut system_fee.pending_protocol_fee, asset, current_pending + amount
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
        let asset_supported = vector::empty<address>();

        move_to(
            sender,
            Config {
                paused: false,
                data_object: object::object_from_constructor_ref(constructor_ref),
                data_object_extend_ref: object::generate_extend_ref(constructor_ref),
                asset_supported
            }
        );

        move_to(sender, RoleRegistry { roles, accounts });

        move_to(
            sender,
            SystemFee {
                distribute_fee: simple_map::new<address, u64>(),
                withdraw_fee: simple_map::new<address, u64>(),
                rebalance_fee: simple_map::new<address, u64>(),
                referral_fee: simple_map::new<address, u64>(),
                pending_referral_fee: simple_map::new<address, u64>(),
                protocol_fee: simple_map::new<address, u64>(),
                pending_protocol_fee: simple_map::new<address, u64>(),
                fee_to: admin_addr
            }
        );

        move_to(
            sender,
            Fee {
                protocol_fee_rate: 2000, // 20% = 2000
                referral_fee_rate: 2500, // 25% protocol fee
                denominator: 10000 // 100% = 10000
            }
        );
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

    public fun check_asset_supported(asset: address) acquires Config {
        let config = borrow_global<Config>(@moneyfi);
        assert!(
            vector::contains(&config.asset_supported, &asset),
            error::invalid_argument(E_ASSET_NOT_SUPPORTED)
        );
    }

    #[test_only]
    friend moneyfi::access_control_test;
    #[test_only]
    friend moneyfi::wallet_account_test;
    use std::string;

    #[test_only]
    public fun get_system_fee(asset: address): (u64, u64, u64, u64, u64, u64, u64) acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);

        let distribute_fee = *simple_map::borrow(&system_fee.distribute_fee, &asset);
        let withdraw_fee = *simple_map::borrow(&system_fee.withdraw_fee, &asset);
        let rebalance_fee = *simple_map::borrow(&system_fee.rebalance_fee, &asset);
        let referral_fee = *simple_map::borrow(&system_fee.referral_fee, &asset);
        let pending_referral_fee =
            *simple_map::borrow(&system_fee.pending_referral_fee, &asset);
        let protocol_fee = *simple_map::borrow(&system_fee.protocol_fee, &asset);
        let pending_protocol_fee =
            *simple_map::borrow(&system_fee.pending_protocol_fee, &asset);

        (
            distribute_fee,
            withdraw_fee,
            rebalance_fee,
            referral_fee,
            pending_referral_fee,
            protocol_fee,
            pending_protocol_fee
        )
    }
}

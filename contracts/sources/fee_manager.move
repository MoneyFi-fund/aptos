module moneyfi::fee_manager {
    use std::signer;
    use std::error;
    use aptos_std::math64;
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, ObjectCore,Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::event;
    use aptos_framework::timestamp::now_seconds;

    use moneyfi::access_control;
    use moneyfi::storage;
    friend moneyfi::wallet_account;

    //-- ERROR
    const E_INVALID_ARGUMENT: u64 = 1;
    const E_ASSET_NOT_SUPPORTED: u64 = 2;

    struct Fee has key {
        protocol_fee_rate: u64,
        referral_fee_rate: u64,
        denominator: u64
    }

    struct SystemFee has key {
        distribute_fee: OrderedMap<address, u64>,
        withdraw_fee: OrderedMap<address, u64>,
        rebalance_fee: OrderedMap<address, u64>,
        referral_fee: OrderedMap<address, u64>,
        protocol_fee: OrderedMap<address, u64>,
        fee_to: address
    }

    //-- EVENT
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
    struct ClaimFeeEvent has drop, store {
        asset: address,
        amount: u64,
        timestamp: u64
    }

    //-- Init
    fun init_module(sender: &signer) {
        let addr = signer::address_of(sender);
        let admin_addr =
            if (object::is_object(addr)) {
                object::root_owner(object::address_to_object<ObjectCore>(addr))
            } else { addr };

        move_to(
            sender,
            SystemFee {
                distribute_fee: ordered_map::new<address, u64>(),
                withdraw_fee: ordered_map::new<address, u64>(),
                rebalance_fee: ordered_map::new<address, u64>(),
                referral_fee: ordered_map::new<address, u64>(),
                protocol_fee: ordered_map::new<address, u64>(),
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

    //--Entries

    public entry fun claim_fees(
        sender: &signer, asset: Object<Metadata>, amount: u64
    ) acquires SystemFee {
        access_control::must_be_role_manager(sender);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        let object_signer = storage::get_signer();
        let asset_addr = object::object_address(&asset);

        primary_fungible_store::transfer(
            &object_signer,
            asset,
            system_fee.fee_to,
            amount
        );

        // Emit event
        event::emit(ClaimFeeEvent { asset: asset_addr, amount, timestamp: now_seconds() });
    }

    public entry fun set_fee_to(sender: &signer, addr: address) acquires SystemFee {
        access_control::must_be_admin(sender);
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        system_fee.fee_to = addr;

        // Emit event
        event::emit(SetFeeToEvent { addr, timestamp: now_seconds() });
    }

    public entry fun set_protocol_fee_rate(sender: &signer, rate: u64) acquires Fee {
        access_control::must_be_role_manager(sender);
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

    public entry fun set_referral_fee_rate(sender: &signer, rate: u64) acquires Fee{
        access_control::must_be_role_manager(sender);
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

    //-- Views

    #[view]
    public fun get_pending_fee(): (vector<address>, vector<u64>) acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        let fee_store = storage::get_address();
        let assets = ordered_map::keys(&system_fee.protocol_fee);
        let amounts = vector::map<address, u64>(assets, |asset| {
            primary_fungible_store::balance<Metadata>(fee_store, object::address_to_object<Metadata>(asset))
        });
        (assets, amounts)
    }

    #[view]
    public fun get_fee_to(): address acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        system_fee.fee_to
    }
    

    //-- Public
    public fun calculate_protocol_fee(amount: u64): u64 acquires Fee {
        let fee = borrow_global<Fee>(@moneyfi);
        math64::mul_div(amount, fee.protocol_fee_rate, fee.denominator)
    }

    public fun calculate_referral_fee(protocol_fee: u64): u64 acquires Fee {
        let fee = borrow_global<Fee>(@moneyfi);
        math64::mul_div(protocol_fee, fee.referral_fee_rate, fee.denominator)
    }

    //-- Private
    public(friend) fun add_distribute_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!ordered_map::contains(&system_fee.distribute_fee, &asset)) {
            ordered_map::add(&mut system_fee.distribute_fee, asset, amount);
        } else {
            let current_amount = *ordered_map::borrow(
                &system_fee.distribute_fee, &asset
            );
            ordered_map::upsert(
                &mut system_fee.distribute_fee, asset, current_amount + amount
            );
        };
    }

    public(friend) fun add_withdraw_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!ordered_map::contains(&system_fee.withdraw_fee, &asset)) {
            ordered_map::add(&mut system_fee.withdraw_fee, asset, amount);
        } else {
            let current_amount = *ordered_map::borrow(&system_fee.withdraw_fee, &asset);
            ordered_map::upsert(
                &mut system_fee.withdraw_fee, asset, current_amount + amount
            );
        };
    }

    public(friend) fun add_rebalance_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        if (!ordered_map::contains(&system_fee.rebalance_fee, &asset)) {
            ordered_map::add(&mut system_fee.rebalance_fee, asset, amount);
        } else {
            let current_amount = *ordered_map::borrow(&system_fee.rebalance_fee, &asset);
            ordered_map::upsert(
                &mut system_fee.rebalance_fee, asset, current_amount + amount
            );
        };
    }

    public(friend) fun add_referral_fee(
        asset: address, amount: u64
    ) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);

        // Add to referral_fee
        if (!ordered_map::contains(&system_fee.referral_fee, &asset)) {
            ordered_map::add(&mut system_fee.referral_fee, asset, amount);
        } else {
            let current_amount = *ordered_map::borrow(&system_fee.referral_fee, &asset);
            ordered_map::upsert(
                &mut system_fee.referral_fee, asset, current_amount + amount
            );
        };
    }

    public(friend) fun add_protocol_fee(
        asset: address, amount: u64
    ) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);

        // Add to protocol_fee
        if (!ordered_map::contains(&system_fee.protocol_fee, &asset)) {
            ordered_map::add(&mut system_fee.protocol_fee, asset, amount);
        } else {
            let current_amount = *ordered_map::borrow(&system_fee.protocol_fee, &asset);
            ordered_map::upsert(
                &mut system_fee.protocol_fee, asset, current_amount + amount
            );
        };
    }
}

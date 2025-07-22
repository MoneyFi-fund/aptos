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
    friend moneyfi::wallet_account;
    friend moneyfi::vault;

    //-- ERROR
    const E_INVALID_ARGUMENT: u64 = 1;
    const E_ASSET_NOT_SUPPORTED: u64 = 2;

    struct Fee has key {
        protocol_fee_rate: u64,
        referral_fee_rate: u64,
        denominator: u64
    }

    struct SystemFee has key {
        fee: OrderedMap<address, FeeData>,
        fee_to: address
    }

    struct FeeData has drop, store {
        distribute_fee: u64,
        withdraw_fee: u64,
        rebalance_fee: u64,
        referral_fee: u64,
        protocol_fee: u64,
    }

    //-- EVENT
    #[event]
    struct SetFeeToEvent has drop, store {
        addr: address,
        timestamp: u64
    }

    #[event]
    struct SetProtocolFeeEvent has drop, store {
        admin: address,
        protocol_fee_rate: u64,
        timestamp: u64
    }

    #[event]
    struct SetReferralFeeEvent has drop, store {
        admin: address,
        referral_fee_rate: u64,
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
                fee: ordered_map::new<address, FeeData>(),
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
                admin: signer::address_of(sender),
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
                admin: signer::address_of(sender),
                referral_fee_rate: rate,
                timestamp: now_seconds()
            }
        );
    }

    //-- Views
    #[view]
    public fun get_fee_to(): address acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        system_fee.fee_to
    }

    #[view]
    public fun get_all_fees(): (vector<address>, vector<FeeData>) acquires SystemFee {
        let system_fee = borrow_global<SystemFee>(@moneyfi);
        ordered_map::to_vec_pairs(&system_fee.fee)
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
    // Helper function to ensure FeeData exists for an asset
    fun ensure_fee_data_exists(system_fee: &mut SystemFee, asset: address) {
        if (!ordered_map::contains(&system_fee.fee, &asset)) {
            ordered_map::add(&mut system_fee.fee, asset, FeeData {
                distribute_fee: 0,
                withdraw_fee: 0,
                rebalance_fee: 0,
                referral_fee: 0,
                protocol_fee: 0,
            });
        };
    }

    public(friend) fun add_distribute_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        ensure_fee_data_exists(system_fee, asset);
        let fee_data = ordered_map::borrow_mut(&mut system_fee.fee, &asset);
        fee_data.distribute_fee = fee_data.distribute_fee + amount;
    }

    public(friend) fun add_withdraw_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        ensure_fee_data_exists(system_fee, asset);
        let fee_data = ordered_map::borrow_mut(&mut system_fee.fee, &asset);
        fee_data.withdraw_fee = fee_data.withdraw_fee + amount;
    }

    public(friend) fun add_rebalance_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        ensure_fee_data_exists(system_fee, asset);
        let fee_data = ordered_map::borrow_mut(&mut system_fee.fee, &asset);
        fee_data.rebalance_fee = fee_data.rebalance_fee + amount;
    }

    public(friend) fun add_referral_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        ensure_fee_data_exists(system_fee, asset);
        let fee_data = ordered_map::borrow_mut(&mut system_fee.fee, &asset);
        fee_data.referral_fee = fee_data.referral_fee + amount;
    }

    public(friend) fun add_protocol_fee(asset: address, amount: u64) acquires SystemFee {
        let system_fee = borrow_global_mut<SystemFee>(@moneyfi);
        ensure_fee_data_exists(system_fee, asset);
        let fee_data = ordered_map::borrow_mut(&mut system_fee.fee, &asset);
        fee_data.protocol_fee = fee_data.protocol_fee + amount;
    }
}

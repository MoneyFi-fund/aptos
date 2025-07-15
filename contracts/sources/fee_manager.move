module moneyfi::fee_manager {
    use std::signer;
    use aptos_std::math64;
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::object::{Self, ObjectCore};

    friend moneyfi::wallet_account;

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
        pending_referral_fee: OrderedMap<address, u64>,
        protocol_fee: OrderedMap<address, u64>,
        pending_protocol_fee: OrderedMap<address, u64>,
        fee_to: address
    }

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
                pending_referral_fee: ordered_map::new<address, u64>(),
                protocol_fee: ordered_map::new<address, u64>(),
                pending_protocol_fee: ordered_map::new<address, u64>(),
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

    public fun calculate_protocol_fee(amount: u64): u64 acquires Fee {
        let fee = borrow_global<Fee>(@moneyfi);
        math64::mul_div(amount, fee.protocol_fee_rate, fee.denominator)
    }

    public fun calculate_referral_fee(protocol_fee: u64): u64 acquires Fee {
        let fee = borrow_global<Fee>(@moneyfi);
        math64::mul_div(protocol_fee, fee.referral_fee_rate, fee.denominator)
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

    public(friend) fun add_rebalance_fee(
        sender: &signer, asset: address, amount: u64
    ) acquires SystemFee {
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
        sender: &signer, asset: address, amount: u64
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

        // Add to pending_referral_fee
        if (!ordered_map::contains(&system_fee.pending_referral_fee, &asset)) {
            ordered_map::add(&mut system_fee.pending_referral_fee, asset, amount);
        } else {
            let current_pending =
                *ordered_map::borrow(&system_fee.pending_referral_fee, &asset);
            ordered_map::upsert(
                &mut system_fee.pending_referral_fee, asset, current_pending + amount
            );
        };
    }

    public(friend) fun add_protocol_fee(
        sender: &signer, asset: address, amount: u64
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

        // Add to pending_protocol_fee
        if (!ordered_map::contains(&system_fee.pending_protocol_fee, &asset)) {
            ordered_map::add(&mut system_fee.pending_protocol_fee, asset, amount);
        } else {
            let current_pending =
                *ordered_map::borrow(&system_fee.pending_protocol_fee, &asset);
            ordered_map::upsert(
                &mut system_fee.pending_protocol_fee, asset, current_pending + amount
            );
        };
    }
}

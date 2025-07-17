module moneyfi::wallet_account {
    use std::bcs;
    use std::signer;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    use aptos_std::string_utils;
    use aptos_std::ordered_map::{Self, OrderedMap};
    use aptos_framework::event;
    use aptos_framework::util;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use moneyfi::access_control;
    use moneyfi::storage;
    use moneyfi::fee_manager;

    friend moneyfi::hyperion;

    // -- Constants
    const WALLET_ACCOUNT_SEED: vector<u8> = b"WALLET_ACCOUNT";
    const APT_SRC_DOMAIN: u32 = 9;

    // -- Errors
    const E_WALLET_ACCOUNT_EXISTS: u64 = 1;
    const E_WALLET_ACCOUNT_NOT_EXISTS: u64 = 2;
    const E_NOT_APTOS_WALLET_ACCOUNT: u64 = 3;
    const E_NOT_OWNER: u64 = 4;
    const E_WALLET_ACCOUNT_NOT_CONNECTED: u64 = 5;
    const E_WALLET_ACCOUNT_ALREADY_CONNECTED: u64 = 6;
    const E_INVALID_ARGUMENT: u64 = 7;
    const E_POSITION_NOT_EXISTS: u64 = 8;
    const E_POSITION_ALREADY_EXISTS: u64 = 9;

    // -- Structs
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct WalletAccount has key {
        // wallet_id is a byte array of length 32
        wallet_id: vector<u8>,
        // source_domain is the domain where the wallet is created
        // e.g. 9 for Aptos, 1 for Ethereum, etc.
        // This is used to identify the wallet account in cross-chain operations
        source_domain: u32,
        // referral is the address of the referrer, if any
        // This can be used for referral programs or rewards
        referral: bool,
        // assets user deposited to the wallet account
        assets: OrderedMap<address, u64>,
        // assets distributed pool
        distributed_assets: OrderedMap<address, u64>,
        // position opened by wallet account
        position_opened: OrderedMap<address, PositionOpened>,
        // total profit claimed by user
        total_profit_claimed: OrderedMap<address, u64>,
        //profit pending on wallet account
        profit_unclaimed: OrderedMap<address, u64>,
        extend_ref: ExtendRef
    }

    struct WalletAccountObject has key {
        wallet_account: Object<WalletAccount>
    }

    struct PositionOpened has copy, drop, store {
        assets: OrderedMap<address, u64>,
        strategy_id: u8
    }

    // -- Events
    #[event]
    struct WalletAccountCreatedEvent has drop, store {
        wallet_id: vector<u8>,
        source_domain: u32,
        wallet_object: address,
        timestamp: u64
    }

    #[event]
    struct DepositToWalletAccountEvent has drop, store {
        sender: address,
        wallet_id: vector<u8>,
        wallet_object: address,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct WithdrawFromWalletAccountEvent has drop, store {
        recipient: address,
        wallet_object: address,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct OpenPositionEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        assets: OrderedMap<address, u64>,
        strategy_id: u8,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct ClosePositionEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct AddLiquidityEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        total_assets: OrderedMap<address, u64>,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct RemoveLiquidityEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        total_assets: OrderedMap<address, u64>,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct DistributeAssetEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        assets: OrderedMap<address, u64>,
        fee_amount: u64,
        timestamp: u64
    }

    #[event]
    struct RewardClaimed has drop, store {
        wallet_id: vector<u8>,
        wallet_object: address,
        user: address,
        assets: vector<address>,
        amounts: vector<u64>,
        timestamp: u64
    }

    #[event]
    struct ClaimPositionRewards has drop, store {
        wallet_id: vector<u8>,
        position: address,
        asset: address,
        user_reward: u64,
        protocol_fee: u64,
        referral_fee: u64,
        referral: bool,
        fee_amount: u64,
        timestamp: u64
    }
    
    // -- Entries

    public entry fun register (
        sender: &signer,
        verifier: &signer,
        wallet_id: vector<u8>,
        referral: bool
    ) acquires WalletAccount {
        create_wallet_account(verifier, wallet_id, APT_SRC_DOMAIN, referral);
        connect_aptos_wallet(sender, wallet_id);
    }

    // create a new WalletAccount for a given wallet_id<byte[32]>
    public entry fun create_wallet_account(
        sender: &signer,
        wallet_id: vector<u8>,
        source_domain: u32,
        referral: bool
    ) {
        access_control::must_be_service_account(sender);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            !object::object_exists<WalletAccount>(addr),
            error::already_exists(E_WALLET_ACCOUNT_EXISTS)
        );

        let extend_ref = storage::create_child_object(get_wallet_account_object_seed(wallet_id));

        let wallet_signer = &object::generate_signer_for_extending(&extend_ref);
        // initialize the WalletAccount object
        move_to(
            wallet_signer,
            WalletAccount {
                wallet_id: wallet_id,
                source_domain: source_domain,
                referral: referral,
                assets: ordered_map::new<address, u64>(),
                distributed_assets: ordered_map::new<address, u64>(),
                position_opened: ordered_map::new<address, PositionOpened>(),
                total_profit_claimed: ordered_map::new<address, u64>(),
                profit_unclaimed: ordered_map::new<address, u64>(),
                extend_ref: extend_ref
            }
        );

        event::emit(
            WalletAccountCreatedEvent {
                wallet_id: wallet_id,
                source_domain: source_domain,
                wallet_object: addr,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    // Connect Aptos wallet to a WalletAccount
    // This function has to be called before claim assets
    public entry fun connect_aptos_wallet(
        sender: &signer, wallet_id: vector<u8>
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(wallet_account_addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        assert!(
            wallet_account.source_domain == APT_SRC_DOMAIN,
            error::invalid_state(E_NOT_APTOS_WALLET_ACCOUNT)
        );
        assert!(
            signer::address_of(sender) == util::address_from_bytes(wallet_id),
            error::permission_denied(E_NOT_OWNER)
        );
        connect_wallet_internal(sender, wallet_account);
    }

    public fun deposit_to_wallet_account(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>,
        fee_amount: u64
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(wallet_account_addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        assert!(
            vector::length(&assets) == vector::length(&amounts),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);

        let fee_deducted = false;
        let fee_asset_addr = @0x0;

        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);

            if (!fee_deducted && amount >= fee_amount) {
                assert!(
                    amount >= fee_amount, error::invalid_argument(E_INVALID_ARGUMENT)
                );
                primary_fungible_store::transfer(
                    sender,
                    asset,
                    storage::get_address(),
                    fee_amount
                );
                primary_fungible_store::transfer(
                    sender,
                    asset,
                    wallet_account_addr,
                    amount - fee_amount
                );
                if (ordered_map::contains(&wallet_account.assets, &asset_addr)) {
                    let current_amount =
                        ordered_map::borrow(&wallet_account.assets, &asset_addr);
                    ordered_map::upsert(
                        &mut wallet_account.assets,
                        asset_addr,
                        *current_amount + amount - fee_amount
                    );
                } else {
                    ordered_map::upsert(
                        &mut wallet_account.assets, asset_addr, amount - fee_amount
                    );
                };
                fee_deducted = true;
                fee_asset_addr = asset_addr;
            } else {
                // Normal transfer without fee
                primary_fungible_store::transfer(
                    sender, asset, wallet_account_addr, amount
                );
                if (ordered_map::contains(&wallet_account.assets, &asset_addr)) {
                    let current_amount =
                        ordered_map::borrow(&wallet_account.assets, &asset_addr);
                    ordered_map::upsert(
                        &mut wallet_account.assets,
                        asset_addr,
                        *current_amount + amount
                    );
                } else {
                    ordered_map::upsert(&mut wallet_account.assets, asset_addr, amount);
                };
            };
            i = i + 1;
        };
        // Add fee to system if fee was deducted
        if (fee_deducted) {
            fee_manager::add_rebalance_fee(fee_asset_addr, fee_amount);
        };

        event::emit(
            DepositToWalletAccountEvent {
                sender: signer::address_of(sender),
                wallet_id: wallet_id,
                wallet_object: wallet_account_addr,
                assets: assets,
                amounts: amounts,
                fee_amount: fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    public fun withdraw_from_wallet_account_by_user(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>
    ) acquires WalletAccount, WalletAccountObject {
        if (!is_connected(signer::address_of(sender), wallet_id)) {
            connect_aptos_wallet(sender, wallet_id);
        };
        claim_rewards(sender, wallet_id);
        let object_signer = get_wallet_account_signer_for_owner(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(
            vector::length(&assets) == vector::length(&amounts),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            let actual_amount = primary_fungible_store::balance(wallet_account_addr, asset);
            let transfer_amount = if(actual_amount < amount) {
                    actual_amount
                }else{
                    amount
                };
            primary_fungible_store::transfer(
                &object_signer,
                asset,
                signer::address_of(sender),
                transfer_amount
            );
            if (ordered_map::contains(&wallet_account.assets, &asset_addr)) {
                let current_amount =
                    ordered_map::borrow(&wallet_account.assets, &asset_addr);
                assert!(
                    *current_amount >= amount,
                    error::invalid_argument(E_INVALID_ARGUMENT)
                );
                if (*current_amount == amount) {
                    ordered_map::remove(&mut wallet_account.assets, &asset_addr);
                } else {
                    ordered_map::upsert(
                        &mut wallet_account.assets,
                        asset_addr,
                        *current_amount - amount
                    );
                }
            };
            i = i + 1;
        };
        event::emit(
            WithdrawFromWalletAccountEvent {
                recipient: signer::address_of(sender),
                wallet_object: wallet_account_addr,
                assets: assets,
                amounts: amounts,
                fee_amount: 0, // No fee for user withdrawal
                timestamp: timestamp::now_seconds()
            }
        );
    }

    public fun claim_rewards(
        sender: &signer, wallet_id: vector<u8>
    ) acquires WalletAccount, WalletAccountObject {
        if (!is_connected(signer::address_of(sender), wallet_id)) {
            connect_aptos_wallet(sender, wallet_id);
        };

        let object_signer = get_wallet_account_signer_for_owner(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);

        let (assets, amounts) =
            ordered_map::to_vec_pair<address, u64>(wallet_account.profit_unclaimed);
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset_addr = *vector::borrow(&assets, i);
            let amount = *vector::borrow(&amounts, i);
            if (amount == 0) {
                i = i + 1;
                continue;
            };
            // Convert asset address to Object<Metadata>
            let asset_obj = object::address_to_object<Metadata>(asset_addr);

            // Transfer rewards to user
            primary_fungible_store::transfer(
                &object_signer,
                asset_obj,
                signer::address_of(sender),
                amount
            );

            // Update total profit claimed
            if (ordered_map::contains(
                &wallet_account.total_profit_claimed, &asset_addr
            )) {
                let current_total =
                    ordered_map::borrow(
                        &wallet_account.total_profit_claimed, &asset_addr
                    );
                ordered_map::upsert(
                    &mut wallet_account.total_profit_claimed,
                    asset_addr,
                    *current_total + amount
                );
            } else {
                ordered_map::upsert(
                    &mut wallet_account.total_profit_claimed, asset_addr, amount
                );
            };
            if (ordered_map::contains(&wallet_account.assets, &asset_addr)) {
                let current_total =
                    ordered_map::borrow(&wallet_account.assets, &asset_addr);
                ordered_map::upsert(
                    &mut wallet_account.assets, asset_addr, *current_total - amount
                );
            };

            i = i + 1;
        };
        // Emit event
        event::emit(
            RewardClaimed {
                wallet_id: wallet_id,
                wallet_object: wallet_account_addr,
                user: signer::address_of(sender),
                assets: assets,
                amounts: amounts,
                timestamp: timestamp::now_seconds()
            }
        );
        // Clear profit_unclaimed after claiming
        wallet_account.profit_unclaimed = ordered_map::new<address, u64>();
    }

    // -- Views
    // Check wallet_id is a valid wallet account
    #[view]
    public fun has_wallet_account(wallet_id: vector<u8>): bool {
        let addr = get_wallet_account_object_address(wallet_id);
        object::object_exists<WalletAccount>(addr)
    }

    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account_object_address(wallet_id: vector<u8>): address {
        storage::get_child_address(get_wallet_account_object_seed(wallet_id))
    }

    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account(wallet_id: vector<u8>): Object<WalletAccount> {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        object::address_to_object<WalletAccount>(addr)
    }

    #[view]
    public fun get_position_opened(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u8>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);

        let (position_addr, infos) =
            ordered_map::to_vec_pair<address, PositionOpened>(
                wallet_account.position_opened
            );
        (position_addr, vector::map<PositionOpened, u8>(infos, |pos| pos.strategy_id))
    }

    #[view]
    public fun get_total_profit_claimed(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        ordered_map::to_vec_pair<address, u64>(wallet_account.total_profit_claimed)
    }

    #[view]
    public fun get_profit_unclaimed(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );
        let wallet_account = borrow_global<WalletAccount>(addr);
        ordered_map::to_vec_pair<address, u64>(wallet_account.profit_unclaimed)
    }

    #[view]
    public fun get_assets(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global<WalletAccount>(addr);
        ordered_map::to_vec_pair<address, u64>(wallet_account.assets)
    }

    #[view]
    public fun get_distributed_assets(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global<WalletAccount>(addr);
        ordered_map::to_vec_pair<address, u64>(wallet_account.distributed_assets)
    }

    #[view]
    public fun is_connected(user: address, wallet_id: vector<u8>): bool acquires WalletAccountObject {
        assert!(
            user == util::address_from_bytes(wallet_id),
            error::permission_denied(E_NOT_OWNER)
        );
        let addr = get_wallet_account_object_address(wallet_id);
        if (exists<WalletAccountObject>(user)) {
            let wallet_account_object = borrow_global<WalletAccountObject>(user);
            addr == object::object_address(&wallet_account_object.wallet_account)
        } else { false }
    }

    #[view]
    public fun get_amount_by_position(
        wallet_id: vector<u8>, position: address
    ): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global<WalletAccount>(addr);
        let position_data =
            ordered_map::borrow(&wallet_account.position_opened, &position);
        let (position_assets, position_amounts) =
            ordered_map::to_vec_pair<address, u64>(position_data.assets);
        (position_assets, position_amounts)
    }

    // -- Public
    // Get the signer for a WalletAccount
    public fun get_wallet_account_signer(
        sender: &signer, wallet_id: vector<u8>
    ): signer acquires WalletAccount {
        access_control::must_be_service_account(sender);
        let addr = get_wallet_account_object_address(wallet_id);

        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    public fun get_wallet_account_by_address(
        addr: address
    ): Object<WalletAccount> acquires WalletAccountObject {
        let obj = borrow_global<WalletAccountObject>(addr);

        obj.wallet_account
    }

    public fun get_wallet_id_by_address (
        addr: address
    ): vector<u8> acquires WalletAccountObject, WalletAccount {
        let obj = borrow_global<WalletAccountObject>(addr);
        let wallet_account = borrow_global<WalletAccount>(object::object_address(&obj.wallet_account));
        wallet_account.wallet_id
    }

    //Get the signer for a WalletAccount for the owner
    public fun get_wallet_account_signer_for_owner(
        sender: &signer, wallet_id: vector<u8>
    ): signer acquires WalletAccount, WalletAccountObject {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            is_owner(signer::address_of(sender), wallet_id),
            error::permission_denied(E_NOT_OWNER)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    public inline fun is_owner(
        owner: address, wallet_id: vector<u8>
    ): bool acquires WalletAccount, WalletAccountObject {
        assert!(
            exists<WalletAccountObject>(owner),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account_object = borrow_global<WalletAccountObject>(owner);
        addr == object::object_address(&wallet_account_object.wallet_account)
    }

    // Add position opened object to the WalletAccount
    public(friend) fun add_position_opened(
        wallet_id: vector<u8>,
        position: address,
        assets: vector<address>,
        amounts: vector<u64>,
        strategy_id: u8,
        fee_amount: u64
    ) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        assert!(
            vector::length(&assets) == vector::length(&amounts),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(
            !ordered_map::contains(&wallet.position_opened, &position),
            error::already_exists(E_POSITION_ALREADY_EXISTS)
        );

        let assets_map = ordered_map::new_from<address, u64>(assets, amounts);
        let pos = PositionOpened { assets: assets_map, strategy_id };

        ordered_map::add(&mut wallet.position_opened, position, pos);
        let fee_asset = *vector::borrow(&assets, 0);
        let current_asset_deposited = ordered_map::borrow(&wallet.assets, &fee_asset);
        ordered_map::upsert(
            &mut wallet.assets, fee_asset, *current_asset_deposited - fee_amount
        );

        // Update distributed_assets when opening position
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let amount = *vector::borrow(&amounts, i);

            if (ordered_map::contains(&wallet.distributed_assets, &asset)) {
                let current_distributed =
                    ordered_map::borrow(&wallet.distributed_assets, &asset);
                ordered_map::upsert(
                    &mut wallet.distributed_assets,
                    asset,
                    *current_distributed + amount
                );
            } else {
                ordered_map::upsert(&mut wallet.distributed_assets, asset, amount);
            };
            if (ordered_map::contains(&wallet.assets, &asset)) {
                let current_wallet_asset = ordered_map::borrow(&wallet.assets, &asset);
                ordered_map::upsert(
                    &mut wallet.assets, asset, *current_wallet_asset - amount
                );
            };
            i = i + 1;
        };

        // Transfer fee asset to the data object
        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet),
            object::address_to_object<Metadata>(fee_asset),
            storage::get_address(),
            fee_amount
        );
        fee_manager::add_distribute_fee(fee_asset, fee_amount);

        event::emit(
            OpenPositionEvent {
                wallet_id: wallet_id,
                position,
                assets: assets_map,
                strategy_id,
                fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );

        event::emit(
            DistributeAssetEvent {
                wallet_id: wallet_id,
                position,
                assets: assets_map,
                fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    // Remove position opened object from the WalletAccount
    // Use this function when the position is closed
    public(friend) fun remove_position_opened(
        wallet_id: vector<u8>,
        position: address,
        asset_out: Object<Metadata>,
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(
            ordered_map::contains(&wallet.position_opened, &position),
            error::not_found(E_POSITION_NOT_EXISTS)
        );

        // Get position assets before removing to update distributed_assets
        let position_data = ordered_map::borrow(&wallet.position_opened, &position);
        let (position_assets, position_amounts) =
            ordered_map::to_vec_pair<address, u64>(position_data.assets);
        // Update distributed_assets when closing position
        let i = 0;
        while (i < vector::length(&position_assets)) {
            let asset = *vector::borrow(&position_assets, i);
            let amount = *vector::borrow(&position_amounts, i);
            if (asset == object::object_address(&asset_out)) {
                // Transfer fee asset to the data object
                primary_fungible_store::transfer(
                    &get_wallet_account_signer_internal(wallet),
                    asset_out,
                    storage::get_address(),
                    fee_amount
                );
                if (ordered_map::contains(&wallet.distributed_assets, &asset)) {
                    let current_distributed =
                        ordered_map::borrow(&wallet.distributed_assets, &asset);
                    if (*current_distributed >= amount) {
                        if (*current_distributed == amount) {
                            ordered_map::remove(&mut wallet.distributed_assets, &asset);
                        } else {
                            ordered_map::upsert(
                                &mut wallet.distributed_assets,
                                asset,
                                *current_distributed - amount
                            );
                        }
                    };

                    fee_manager::add_withdraw_fee(
                        object::object_address(&asset_out),
                        fee_amount
                    );

                    let current_wallet_amount =
                        primary_fungible_store::balance(
                            addr, object::address_to_object<Metadata>(asset)
                        );
                    ordered_map::upsert(&mut wallet.assets, asset, current_wallet_amount);
                } else {
                    if (ordered_map::contains(&wallet.distributed_assets, &asset)) {
                        let current_distributed =
                            ordered_map::borrow(&wallet.distributed_assets, &asset);
                        if (*current_distributed >= amount) {
                            if (*current_distributed == amount) {
                                ordered_map::remove(
                                    &mut wallet.distributed_assets, &asset
                                );
                            } else {
                                ordered_map::upsert(
                                    &mut wallet.distributed_assets,
                                    asset,
                                    *current_distributed - amount
                                );
                            }
                        };
                        let current_wallet_amount =
                            primary_fungible_store::balance(
                                addr, object::address_to_object<Metadata>(asset)
                            );
                        ordered_map::upsert(
                            &mut wallet.assets, asset, current_wallet_amount
                        );
                    };
                };

                i = i + 1;
            };

            ordered_map::remove(&mut wallet.position_opened, &position);

            event::emit(
                ClosePositionEvent {
                    wallet_id: wallet_id,
                    position,
                    fee_amount,
                    timestamp: timestamp::now_seconds()
                }
            );
        }
    }

    //INTERNAL: ONLY CALLED BY DATA OBJECT SIGNER
    // Upgrade position opened object in the WalletAccount
    // Use this function when the position is opened and you want to add more assets to it
    public fun upgrade_position_opened(
        wallet_id: vector<u8>,
        position: address,
        assets_added: vector<address>,
        amounts_added: vector<u64>,
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        assert!(
            vector::length(&assets_added) == vector::length(&amounts_added),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(
            ordered_map::contains(&wallet.position_opened, &position),
            error::not_found(E_POSITION_NOT_EXISTS)
        );

        // Transfer fee asset to the data object
        let fee_asset = *vector::borrow(&assets_added, 0);
        let current_asset_deposited = ordered_map::borrow(&wallet.assets, &fee_asset);
        ordered_map::upsert(
            &mut wallet.assets, fee_asset, *current_asset_deposited - fee_amount
        );
        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet),
            object::address_to_object<Metadata>(fee_asset),
            storage::get_address(),
            fee_amount
        );
        fee_manager::add_distribute_fee(fee_asset, fee_amount);
        let pos = ordered_map::borrow_mut(&mut wallet.position_opened, &position);
        let assets_map = &mut pos.assets;
        let i = 0;
        while (i < vector::length(&assets_added)) {
            let asset = *vector::borrow(&assets_added, i);
            let amount = *vector::borrow(&amounts_added, i);

            let updated =
                if (ordered_map::contains(assets_map, &asset)) {
                    let current = ordered_map::borrow(assets_map, &asset);
                    *current + amount
                } else { amount };

            ordered_map::upsert(assets_map, asset, updated);

            // Update distributed_assets when upgrading position
            if (ordered_map::contains(&wallet.distributed_assets, &asset)) {
                let current_distributed =
                    ordered_map::borrow(&wallet.distributed_assets, &asset);
                ordered_map::upsert(
                    &mut wallet.distributed_assets,
                    asset,
                    *current_distributed + amount
                );
            } else {
                ordered_map::upsert(&mut wallet.distributed_assets, asset, amount);
            };

            if (ordered_map::contains(&wallet.assets, &asset)) {
                let current_wallet_asset = ordered_map::borrow(&wallet.assets, &asset);
                ordered_map::upsert(
                    &mut wallet.assets, asset, *current_wallet_asset - amount
                );
            };

            i = i + 1;
        };

        event::emit(
            AddLiquidityEvent {
                wallet_id: wallet_id,
                position,
                total_assets: *assets_map,
                fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );

        event::emit(
            DistributeAssetEvent {
                wallet_id: wallet_id,
                position,
                assets: *assets_map,
                fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    public fun update_position_after_partial_removal(
        wallet_id: vector<u8>,
        position: address,
        withdrawn_assets: vector<address>,
        withdrawn_amounts: vector<u64>,
        amounts_after: vector<u64>,
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        assert!(
            vector::length(&withdrawn_assets) == vector::length(&withdrawn_amounts),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );
        assert!(
            vector::length(&withdrawn_assets) == vector::length(&amounts_after),
            error::invalid_argument(E_INVALID_ARGUMENT)
        );

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(
            ordered_map::contains(&wallet.position_opened, &position),
            error::not_found(E_POSITION_NOT_EXISTS)
        );

        // Transfer fee asset to the data object
        let fee_asset = *vector::borrow(&withdrawn_assets, 0);

        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet),
            object::address_to_object<Metadata>(fee_asset),
            storage::get_address(),
            fee_amount
        );
        fee_manager::add_withdraw_fee(fee_asset, fee_amount);

        let pos = ordered_map::borrow_mut(&mut wallet.position_opened, &position);
        let assets_map = &mut pos.assets;
        let i = 0;
        while (i < vector::length(&withdrawn_assets)) {
            let asset = *vector::borrow(&withdrawn_assets, i);
            let withdrawn_amount = *vector::borrow(&withdrawn_amounts, i);
            let amount_after = *vector::borrow(&amounts_after, i);

            // Update position assets with amounts after removal
            if (amount_after == 0) {
                // Remove asset from position if amount is 0
                if (ordered_map::contains(assets_map, &asset)) {
                    ordered_map::remove(assets_map, &asset);
                };
            } else {
                // Update position with remaining amount
                ordered_map::upsert(assets_map, asset, amount_after);
            };

            // Subtract withdrawn amount from distributed_assets
            if (ordered_map::contains(&wallet.distributed_assets, &asset)) {
                let current_distributed =
                    ordered_map::borrow(&wallet.distributed_assets, &asset);
                assert!(
                    *current_distributed >= withdrawn_amount,
                    error::invalid_argument(E_INVALID_ARGUMENT)
                );
                if (*current_distributed == withdrawn_amount) {
                    ordered_map::remove(&mut wallet.distributed_assets, &asset);
                } else {
                    ordered_map::upsert(
                        &mut wallet.distributed_assets,
                        asset,
                        *current_distributed - withdrawn_amount
                    );
                }
            };

            // Add withdrawn amount to wallet assets (minus fee for fee asset)
            let actual_amount =
                if (asset == fee_asset) {
                    withdrawn_amount - fee_amount
                } else {
                    withdrawn_amount
                };

            if (actual_amount > 0) {
                if (ordered_map::contains(&wallet.assets, &asset)) {
                    let current_wallet_asset = ordered_map::borrow(
                        &wallet.assets, &asset
                    );
                    ordered_map::upsert(
                        &mut wallet.assets,
                        asset,
                        *current_wallet_asset + actual_amount
                    );
                } else {
                    ordered_map::upsert(&mut wallet.assets, asset, actual_amount);
                };
            };

            i = i + 1;
        };
        event::emit(
            RemoveLiquidityEvent {
                wallet_id: wallet_id,
                position,
                total_assets: ordered_map::new_from<address, u64>(
                    withdrawn_assets, withdrawn_amounts
                ),
                fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    //INTERNAL: ONLY CALLED BY DATA OBJECT SIGNER
    // use when close position and claim rewards to the wallet account
    public fun add_profit_unclaimed(
        wallet_id: vector<u8>,
        position: address,
        asset: address,
        amount: u64,
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        // Transfer fee asset to the data object
        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet_account_mut),
            object::address_to_object<Metadata>(asset),
            storage::get_address(),
            fee_amount
        );

        fee_manager::add_withdraw_fee(asset, fee_amount);

        let protocol_amount = fee_manager::calculate_protocol_fee(amount);

        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet_account_mut),
            object::address_to_object<Metadata>(asset),
            storage::get_address(),
            protocol_amount
        );

        let referral_fee =
            if (wallet_account_mut.referral) {
                fee_manager::calculate_referral_fee(protocol_amount) // 25% of protocol amount
            } else { 0 };

        fee_manager::add_referral_fee(asset, referral_fee);

        fee_manager::add_protocol_fee(
            asset,
            protocol_amount - referral_fee // 75% of protocol amount
        );
        let user_amount = amount - protocol_amount;
        if (ordered_map::contains(&wallet_account_mut.profit_unclaimed, &asset)) {
            let current_amount =
                ordered_map::borrow(&wallet_account_mut.profit_unclaimed, &asset);
            ordered_map::upsert(
                &mut wallet_account_mut.profit_unclaimed,
                asset,
                *current_amount + user_amount - fee_amount
            );
        } else {
            ordered_map::upsert(
                &mut wallet_account_mut.profit_unclaimed,
                asset,
                user_amount - fee_amount
            );
        };
        if (ordered_map::contains(&wallet_account_mut.assets, &asset)) {
            let current_amount = ordered_map::borrow(&wallet_account_mut.assets, &asset);
            ordered_map::upsert(
                &mut wallet_account_mut.assets,
                asset,
                *current_amount + user_amount - fee_amount
            );
        } else {
            ordered_map::upsert(
                &mut wallet_account_mut.assets, asset, user_amount - fee_amount
            );
        };

        event::emit(
            ClaimPositionRewards {
                wallet_id: wallet_id,
                position: position,
                asset: asset,
                user_reward: user_amount,
                protocol_fee: protocol_amount - referral_fee,
                referral_fee: referral_fee,
                referral: wallet_account_mut.referral,
                fee_amount: fee_amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    // -- Private

    public(friend) fun deposit(
        sender: &signer,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64
    ) acquires WalletAccount, WalletAccountObject {
        let addr = signer::address_of(sender);
        let account_obj = get_wallet_account_by_address(addr);
        let account_addr = object::object_address(&account_obj);
        let account = borrow_global_mut<WalletAccount>(account_addr);
        let asset_addr = object::object_address(&asset);

        primary_fungible_store::transfer(sender, asset, account_addr, amount);
        let balance =
            if (ordered_map::contains(&account.assets, &asset_addr)) {
                *ordered_map::borrow(&account.assets, &asset_addr)
            } else { 0 };
        ordered_map::upsert(&mut account.assets, asset_addr, amount + balance);

        let lp_balance = account.get_lp_balance(&asset);
        ordered_map::upsert(&mut account.lp_amount, asset_addr, lp_balance + lp_amount);
    }

    public(friend) fun withdraw(
        sender: &signer,
        asset: Object<Metadata>,
        amount: u64,
        lp_amount: u64
    ) acquires WalletAccount, WalletAccountObject {
        let addr = signer::address_of(sender);
        let account_obj = get_wallet_account_by_address(addr);
        let account_addr = object::object_address(&account_obj);
        let account = borrow_global_mut<WalletAccount>(account_addr);
        let asset_addr = object::object_address(&asset);

        let balance = get_balance(account_obj, asset);
        assert!(balance >= amount);
        let lp_balance = account.get_lp_balance(&asset);
        assert!(lp_balance >= lp_amount);

        let account_signer = account.generate_signer();
        primary_fungible_store::transfer(&account_signer, asset, addr, amount);

        let balance =
            if (ordered_map::contains(&account.assets, &asset_addr)) {
                *ordered_map::borrow(&account.assets, &asset_addr)
            } else { 0 };
        ordered_map::upsert(&mut account.assets, asset_addr, balance - amount);
        ordered_map::upsert(&mut account.lp_amount, asset_addr, lp_balance - lp_amount);
    }

    fun get_lp_balance(self: &WalletAccount, asset: &Object<Metadata>): u64 {
        let asset_addr = object::object_address(asset);
        if (ordered_map::contains(&self.lp_amount, &asset_addr)) {
            *ordered_map::borrow(&self.lp_amount, &asset_addr)
        } else { 0 }
    }

    fun generate_signer(self: &WalletAccount): signer {
        object::generate_signer_for_extending(&self.extend_ref)
    }

    fun verify_wallet_position(wallet_id: vector<u8>, position: address) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        let wallet_account = borrow_global<WalletAccount>(addr);
        assert!(
            ordered_map::contains(&wallet_account.position_opened, &position),
            error::not_found(E_POSITION_NOT_EXISTS)
        );
    }

    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_{}", WALLET_ACCOUNT_SEED, wallet_id))
    }

    fun connect_wallet_internal(
        sender: &signer, wallet_account: &mut WalletAccount
    ) {
        let wallet_address = signer::address_of(sender);
        let wallet_account_addr =
            get_wallet_account_object_address(wallet_account.wallet_id);
        assert!(
            object::object_exists<WalletAccount>(wallet_account_addr),
            error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS)
        );
        assert!(
            !exists<WalletAccountObject>(wallet_address),
            error::already_exists(E_WALLET_ACCOUNT_ALREADY_CONNECTED)
        );
        move_to(
            sender,
            WalletAccountObject {
                wallet_account: get_wallet_account(wallet_account.wallet_id)
            }
        );
        event::emit(
            WalletAccountConnectedEvent {
                wallet_id: wallet_account.wallet_id,
                wallet_object: wallet_account_addr,
                wallet_address: wallet_address,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    fun get_wallet_account_signer_internal(
        wallet_account: &WalletAccount
    ): signer {
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    #[test_only]
    friend moneyfi::wallet_account_test;

    #[test_only]
    public(friend) fun create_wallet_account_for_test(
        user_addr: address, referral: bool
    ): vector<u8> {
        let wallet_id = bcs::to_bytes<address>(&user_addr);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            !object::object_exists<WalletAccount>(addr),
            error::already_exists(E_WALLET_ACCOUNT_EXISTS)
        );

        let extend_ref = storage::create_child_object(get_wallet_account_object_seed(wallet_id));

        let wallet_signer = &object::generate_signer_for_extending(&extend_ref);
        // initialize the WalletAccount object
        move_to(
            wallet_signer,
            WalletAccount {
                wallet_id: wallet_id,
                source_domain: 9,
                referral: referral,
                assets: ordered_map::new<address, u64>(),
                distributed_assets: ordered_map::new<address, u64>(),
                position_opened: ordered_map::new<address, PositionOpened>(),
                total_profit_claimed: ordered_map::new<address, u64>(),
                profit_unclaimed: ordered_map::new<address, u64>(),
                extend_ref: object::generate_extend_ref(constructor_ref)
            }
        );
        wallet_id
    }
}

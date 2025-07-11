module moneyfi::wallet_account {
    use std::bcs;
    use std::signer;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    use aptos_std::string_utils;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::event;
    use aptos_framework::util;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use moneyfi::access_control;

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
        assets: SimpleMap<address, u64>,
        // assets distributed pool
        distributed_assets: SimpleMap<address, u64>,
        // position opened by wallet account
        position_opened: SimpleMap<address, PositionOpened>,
        // total profit claimed by user
        total_profit_claimed: SimpleMap<address, u64>,
        //profit pending on wallet account 
        profit_unclaimed: SimpleMap<address, u64>,
        extend_ref: ExtendRef
    }

    struct WalletAccountObject has key {
        wallet_account: Object<WalletAccount>
    }  

    struct PositionOpened has copy, drop, store {
        assets: SimpleMap<address, u64>,
        strategy_id: u8,
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
    struct WalletAccountConnectedEvent has drop, store {
        wallet_id: vector<u8>,
        wallet_object: address,
        wallet_address: address,
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
        assets: SimpleMap<address, u64>,
        strategy_id: u8,
        timestamp: u64
    }

    #[event]
    struct ClosePositionEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        timestamp: u64
    }

    #[event]
    struct AddLiquidityEvent has drop, store {
        wallet_id: vector<u8>,
        position: address,
        total_assets: SimpleMap<address, u64>,
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
        timestamp: u64
    }

    // -- Entries
    // create a new WalletAccount for a given wallet_id<byte[32]>
    public entry fun create_wallet_account(
        sender: &signer, wallet_id: vector<u8>, source_domain: u32, referral: bool
    ) {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(!object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS));

        let data_object_signer = &access_control::get_object_data_signer();

        let constructor_ref =
            &object::create_named_object(
                data_object_signer, get_wallet_account_object_seed(wallet_id)
            );
        let wallet_signer = &object::generate_signer(constructor_ref);
        // initialize the WalletAccount object
        move_to(
            wallet_signer,
            WalletAccount {
                wallet_id: wallet_id,
                source_domain: source_domain,
                referral: referral,
                assets: simple_map::new<address, u64>(),
                distributed_assets: simple_map::new<address, u64>(),
                position_opened: simple_map::new<address, PositionOpened>(),
                total_profit_claimed: simple_map::new<address, u64>(),
                profit_unclaimed: simple_map::new<address, u64>(),
                extend_ref: object::generate_extend_ref(constructor_ref)
            }
        );

        event::emit(
            WalletAccountCreatedEvent {
                wallet_id: wallet_id,
                source_domain: source_domain,
                wallet_object: addr,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    // Connect user wallet to a WalletAccount
//   public entry fun connect_wallet(
//       sender: &signer, wallet_id: vector<u8>, signature: vector<u8>
//   ) acquires WalletAccount {
//
//       // TODO: verify signature
//       //connect_wallet_internal(sender, wallet_id);
//   }

    // Connect Aptos wallet to a WalletAccount
    // This function has to be called before claim assets
    public entry fun connect_aptos_wallet(
        sender: &signer, wallet_id: vector<u8>
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(wallet_account_addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        assert!(wallet_account.source_domain == APT_SRC_DOMAIN, error::invalid_state(E_NOT_APTOS_WALLET_ACCOUNT));
        assert!(signer::address_of(sender) == util::address_from_bytes(wallet_id), error::permission_denied(E_NOT_OWNER));
        connect_wallet_internal(sender, wallet_account);
    }

    public entry fun deposit_to_wallet_account(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>,
        fee_amount: u64
    ) acquires WalletAccount {
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        
        // Get stablecoin metadata list
        let stablecoin_metadata = access_control::get_asset_supported();
        let fee_deducted = false;
        let fee_asset_addr = @0x0;
        
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            access_control::check_asset_supported(asset_addr);
            // Check if this asset is a stablecoin and we haven't deducted fee yet
            let is_stablecoin = vector::contains(&stablecoin_metadata, &asset_addr);
            
            if (is_stablecoin && !fee_deducted && amount >= fee_amount) {
                // Deduct fee from this stablecoin
                assert!(amount >= fee_amount, error::invalid_argument(E_INVALID_ARGUMENT));
                primary_fungible_store::transfer(
                    sender,
                    asset,
                    access_control::get_data_object_address(),
                    fee_amount,
                );
                primary_fungible_store::transfer(
                    sender,
                    asset,
                    wallet_account_addr,
                    amount - fee_amount,
                );
                if (simple_map::contains_key(&wallet_account.assets, &asset_addr)) {
                    let current_amount = simple_map::borrow(&wallet_account.assets, &asset_addr);
                    simple_map::upsert(&mut wallet_account.assets, asset_addr, *current_amount + amount - fee_amount);
                } else {
                    simple_map::upsert(&mut wallet_account.assets, asset_addr, amount - fee_amount);
                };
                fee_deducted = true;
                fee_asset_addr = asset_addr;
            } else {
                // Normal transfer without fee
                primary_fungible_store::transfer(
                    sender,
                    asset,
                    wallet_account_addr,
                    amount,
                );
                if (simple_map::contains_key(&wallet_account.assets, &asset_addr)) {
                    let current_amount = simple_map::borrow(&wallet_account.assets, &asset_addr);
                    simple_map::upsert(&mut wallet_account.assets, asset_addr, *current_amount + amount);
                } else {
                    simple_map::upsert(&mut wallet_account.assets, asset_addr, amount);
                };
            };
            i = i + 1;
        };
        
        // Add fee to system if fee was deducted
        if (fee_deducted) {
            let server_signer = access_control::get_object_data_signer();
            access_control::add_rebalance_fee(
                &server_signer,
                fee_asset_addr,
                fee_amount
            );
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

    public entry fun withdraw_from_wallet_account_by_user(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>
    ) acquires WalletAccount , WalletAccountObject {
        if(!is_connected(signer::address_of(sender), wallet_id)) {
            connect_aptos_wallet(sender, wallet_id);
        };
        claim_rewards(sender, wallet_id);
        let object_signer = get_wallet_account_signer_for_owner(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            primary_fungible_store::transfer(
                &object_signer,
                asset,
                signer::address_of(sender),
                amount,
            );
            if (simple_map::contains_key(&wallet_account.assets, &asset_addr)) {
                let current_amount = simple_map::borrow(&wallet_account.assets, &asset_addr);
                assert!(*current_amount >= amount, error::invalid_argument(E_INVALID_ARGUMENT));
                if (*current_amount == amount) {
                    simple_map::remove(&mut wallet_account.assets, &asset_addr);
                } else {
                    simple_map::upsert(&mut wallet_account.assets, asset_addr, *current_amount - amount);
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
                    timestamp: timestamp::now_seconds(),
                }
            );
    }

    public entry fun withdraw_from_wallet_account_by_operator(
        sender: &signer,
        wallet_id: vector<u8>,
        assets: vector<Object<Metadata>>,
        amounts: vector<u64>,
        recipient: address,
        fee_amount: u64,
    ) acquires WalletAccount {
        access_control::must_be_operator(sender);
        let object_signer = get_wallet_account_signer(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));
        assert!(recipient != signer::address_of(sender), error::invalid_argument(E_INVALID_ARGUMENT));
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);
        
        // Get stablecoin metadata list
        let stablecoin_metadata = access_control::get_asset_supported();
        let fee_deducted = false;
        let fee_asset_addr = @0x0;
        
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let asset_addr = object::object_address(&asset);
            let amount = *vector::borrow(&amounts, i);
            
            // Check if this asset is a stablecoin and we haven't deducted fee yet
            let is_stablecoin = vector::contains(&stablecoin_metadata, &asset_addr);
            
            if (is_stablecoin && !fee_deducted && amount >= fee_amount) {
                // Deduct fee from this stablecoin
                assert!(amount >= fee_amount, error::invalid_argument(E_INVALID_ARGUMENT));
                primary_fungible_store::transfer(
                    &object_signer,
                    asset,
                    access_control::get_data_object_address(),
                    fee_amount,
                );
                primary_fungible_store::transfer(
                    &object_signer,
                    asset,
                    recipient,
                    amount - fee_amount,
                );
                fee_deducted = true;
                fee_asset_addr = asset_addr;
            } else {
                // Normal transfer without fee
                primary_fungible_store::transfer(
                    &object_signer,
                    asset,
                    recipient,
                    amount,
                );
            };
            
            // Update wallet account balance
            if (simple_map::contains_key(&wallet_account.assets, &asset_addr)) {
                let current_amount = simple_map::borrow(&wallet_account.assets, &asset_addr);
                assert!(*current_amount >= amount, error::invalid_argument(E_INVALID_ARGUMENT));
                if (*current_amount == amount) {
                    simple_map::remove(&mut wallet_account.assets, &asset_addr);
                } else {
                    simple_map::upsert(&mut wallet_account.assets, asset_addr, *current_amount - amount);
                };
            };
            i = i + 1;
        };
        
        // Add fee to system if fee was deducted
        if (fee_deducted) {
            let server_signer = access_control::get_object_data_signer();
            access_control::add_withdraw_fee(
                &server_signer,
                fee_asset_addr,
                fee_amount
            );
        };
        
        event::emit(
            WithdrawFromWalletAccountEvent {
                recipient: recipient,
                wallet_object: wallet_account_addr,
                assets: assets,
                amounts: amounts,
                fee_amount: fee_amount,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    public entry fun claim_rewards(
        sender: &signer,
        wallet_id: vector<u8>
    ) acquires WalletAccount, WalletAccountObject {
        if (!is_connected(signer::address_of(sender), wallet_id)) {
            connect_aptos_wallet(sender, wallet_id);
        };

        let object_signer = get_wallet_account_signer_for_owner(sender, wallet_id);
        let wallet_account_addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global_mut<WalletAccount>(wallet_account_addr);

        let (assets, amounts) = simple_map::to_vec_pair<address, u64>(wallet_account.profit_unclaimed);
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
                amount,
            );

            // Update total profit claimed
            if (simple_map::contains_key(&wallet_account.total_profit_claimed, &asset_addr)) {
                let current_total = simple_map::borrow(&wallet_account.total_profit_claimed, &asset_addr);
                simple_map::upsert(&mut wallet_account.total_profit_claimed, asset_addr, *current_total + amount);
            } else {
                simple_map::upsert(&mut wallet_account.total_profit_claimed, asset_addr, amount);
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
                timestamp: timestamp::now_seconds(),
            }
        );
        // Clear profit_unclaimed after claiming
        wallet_account.profit_unclaimed = simple_map::new<address, u64>();
    }

    // -- Views
    // Check wallet_id is a valid wallet account
    #[view]
    public fun has_wallet_account(
        wallet_id: vector<u8>
    ): bool {
        let addr = get_wallet_account_object_address(wallet_id);
        object::object_exists<WalletAccount>(addr)
    }

    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account_object_address(wallet_id: vector<u8>): address {
        let data_object_addr = access_control::get_data_object_address();
        object::create_object_address(
            &data_object_addr, get_wallet_account_object_seed(wallet_id)
        )
    }

    // Get the WalletAccount object address for a given wallet_id
    #[view]
    public fun get_wallet_account(wallet_id: vector<u8>): Object<WalletAccount> {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        object::address_to_object<WalletAccount>(addr)
    }

    #[view]
    public fun get_position_opened(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u8>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);

        let (position_addr, infos) = simple_map::to_vec_pair<address, PositionOpened>(
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
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        simple_map::to_vec_pair<address, u64>(wallet_account.total_profit_claimed)
    }

    #[view]
    public fun get_profit_unclaimed(
        wallet_id: vector<u8>
    ): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        ); 
        let wallet_account = borrow_global<WalletAccount>(addr);
        simple_map::to_vec_pair<address, u64>(wallet_account.profit_unclaimed)
    }

    #[view]
    public fun get_assets(wallet_id: vector<u8>): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global<WalletAccount>(addr);
        simple_map::to_vec_pair<address, u64>(wallet_account.assets)
    }

    #[view]
    public fun get_distributed_assets(wallet_id: vector<u8>): (vector<address>, vector<u64>) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account = borrow_global<WalletAccount>(addr);
        simple_map::to_vec_pair<address, u64>(wallet_account.distributed_assets)
    }

    #[view]
    public fun is_connected(
        user: address, wallet_id: vector<u8>
    ): bool acquires WalletAccountObject {
        assert!(user == util::address_from_bytes(wallet_id), error::permission_denied(E_NOT_OWNER));
        let addr = get_wallet_account_object_address(wallet_id);
        if (exists<WalletAccountObject>(user)) {
            let wallet_account_object = borrow_global<WalletAccountObject>(user);
            addr == object::object_address(&wallet_account_object.wallet_account)
        } else {
            false
        }
    }

    // -- Public
    // Get the signer for a WalletAccount
    public fun get_wallet_account_signer(sender: &signer ,wallet_id: vector<u8>): signer acquires WalletAccount {
        access_control::must_be_operator(sender);
        let addr = get_wallet_account_object_address(wallet_id);

        assert!(
            object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_EXISTS)
        );

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    //Get the signer for a WalletAccount for the owner
    public fun get_wallet_account_signer_for_owner(
        sender: &signer, 
        wallet_id: vector<u8>
    ): signer acquires WalletAccount, WalletAccountObject {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(is_owner(signer::address_of(sender), wallet_id), error::permission_denied(E_NOT_OWNER));

        let wallet_account = borrow_global<WalletAccount>(addr);
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }

    public inline fun is_owner(
        owner: address, wallet_id: vector<u8>
    ): bool acquires WalletAccount, WalletAccountObject {
        assert!(exists<WalletAccountObject>(owner), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let addr = get_wallet_account_object_address(wallet_id);
        let wallet_account_object = borrow_global<WalletAccountObject>(owner);
        addr == object::object_address(&wallet_account_object.wallet_account)
    }

    //INTERNAL: ONLY CALLED BY DATA OBJECT SIGNER
    // Add position opened object to the WalletAccount
    public fun add_position_opened(
        data_signer: &signer, 
        wallet_id: vector<u8>, 
        position: address, 
        assets: vector<address>, 
        amounts: vector<u64>, 
        strategy_id: u8,
        fee_amount: u64
    ) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(signer::address_of(data_signer) == access_control::get_data_object_address(), error::permission_denied(E_NOT_OWNER));
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        assert!(vector::length(&assets) == vector::length(&amounts), error::invalid_argument(E_INVALID_ARGUMENT));

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(!simple_map::contains_key(&wallet.position_opened, &position), error::already_exists(E_POSITION_ALREADY_EXISTS));

        let assets_map = simple_map::new_from<address, u64>(assets, amounts);
        let pos = PositionOpened { assets: assets_map, strategy_id };

        simple_map::add(&mut wallet.position_opened, position, pos);
        let fee_asset = *vector::borrow(&assets, 0);
        let current_asset_deposited = simple_map::borrow(&wallet.assets, &fee_asset);
        simple_map::upsert(&mut wallet.assets, fee_asset, *current_asset_deposited - fee_amount);
        
        // Update distributed_assets when opening position
        let i = 0;
        while (i < vector::length(&assets)) {
            let asset = *vector::borrow(&assets, i);
            let amount = *vector::borrow(&amounts, i);
            
            if (simple_map::contains_key(&wallet.distributed_assets, &asset)) {
                let current_distributed = simple_map::borrow(&wallet.distributed_assets, &asset);
                simple_map::upsert(&mut wallet.distributed_assets, asset, *current_distributed + amount);
            } else {
                simple_map::upsert(&mut wallet.distributed_assets, asset, amount);
            };
            i = i + 1;
        };

        // Transfer fee asset to the data object
        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet),
            object::address_to_object<Metadata>(fee_asset),
            access_control::get_data_object_address(),
            fee_amount
        );
        access_control::add_distribute_fee(
            data_signer,
            fee_asset,
            fee_amount
        );

        event::emit(OpenPositionEvent {
            wallet_id: wallet_id,
            position,
            assets: assets_map,
            strategy_id,
            timestamp: timestamp::now_seconds(),
        });
    }

    //INTERNAL: ONLY CALLED BY DATA OBJECT SIGNER
    // Remove position opened object from the WalletAccount
    // Use this function when the position is closed
    public fun remove_position_opened(
        data_signer: &signer, 
        wallet_id: vector<u8>, 
        position: address,
        asset_out: Object<Metadata>,
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(signer::address_of(data_signer) == access_control::get_data_object_address(), error::permission_denied(E_NOT_OWNER));
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(simple_map::contains_key(&wallet.position_opened, &position), error::not_found(E_POSITION_NOT_EXISTS));

        // Get position assets before removing to update distributed_assets
        let position_data = simple_map::borrow(&wallet.position_opened, &position);
        let (position_assets, position_amounts) = simple_map::to_vec_pair<address, u64>(position_data.assets);
        
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
                    access_control::get_data_object_address(),
                    fee_amount
                );
                if (simple_map::contains_key(&wallet.distributed_assets, &asset)) {
                    let current_distributed = simple_map::borrow(&wallet.distributed_assets, &asset);
                    if (*current_distributed >= amount) {
                        if (*current_distributed == amount) {
                            simple_map::remove(&mut wallet.distributed_assets, &asset);
                        } else {
                            simple_map::upsert(&mut wallet.distributed_assets, asset, *current_distributed - amount);
                        }
                    };
                    let current_wallet_amount = simple_map::borrow(&wallet.assets, &asset);
                    simple_map::upsert(&mut wallet.assets, asset, *current_wallet_amount - fee_amount); 
                    access_control::add_withdraw_fee(
                        data_signer,
                        object::object_address(&asset_out),
                        fee_amount
                    );
            } else {
                if (simple_map::contains_key(&wallet.distributed_assets, &asset)) {
                let current_distributed = simple_map::borrow(&wallet.distributed_assets, &asset);
                if (*current_distributed >= amount) {
                    if (*current_distributed == amount) {
                        simple_map::remove(&mut wallet.distributed_assets, &asset);
                    } else {
                        simple_map::upsert(&mut wallet.distributed_assets, asset, *current_distributed - amount);
                    }
                }
            };
            };
            
            i = i + 1;
        };

        simple_map::remove(&mut wallet.position_opened, &position);

        event::emit(ClosePositionEvent {
            wallet_id: wallet_id,
            position,
            timestamp: timestamp::now_seconds(),
        });
    }
    
    }

    //INTERNAL: ONLY CALLED BY DATA OBJECT SIGNER
    // Upgrade position opened object in the WalletAccount
    // Use this function when the position is opened and you want to add more assets to it
    public fun upgrade_position_opened(
        data_signer: &signer, 
        wallet_id: vector<u8>, 
        position: address,
        assets_added: vector<address>,
        amounts_added: vector<u64>,
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(signer::address_of(data_signer) == access_control::get_data_object_address(), error::permission_denied(E_NOT_OWNER));
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        assert!(vector::length(&assets_added) == vector::length(&amounts_added), error::invalid_argument(E_INVALID_ARGUMENT));

        let wallet = borrow_global_mut<WalletAccount>(addr);
        assert!(simple_map::contains_key(&wallet.position_opened, &position), error::not_found(E_POSITION_NOT_EXISTS));

        // Transfer fee asset to the data object
        let fee_asset = *vector::borrow(&assets_added, 0);
        let current_asset_deposited = simple_map::borrow(&wallet.assets, &fee_asset);
        simple_map::upsert(&mut wallet.assets, fee_asset, *current_asset_deposited - fee_amount);
        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet),
            object::address_to_object<Metadata>(fee_asset),
            access_control::get_data_object_address(),
            fee_amount
        );
        access_control::add_distribute_fee(
            data_signer,
            fee_asset,
            fee_amount
        );
        let pos = simple_map::borrow_mut(&mut wallet.position_opened, &position);
        let assets_map = &mut pos.assets;
        let i = 0;
        while (i < vector::length(&assets_added)) {
            let asset = *vector::borrow(&assets_added, i);
            let amount = *vector::borrow(&amounts_added, i);

            let updated = if (simple_map::contains_key(assets_map, &asset)) {
                let current = simple_map::borrow(assets_map, &asset);
                *current + amount
            } else {
                amount
            };
            
            simple_map::upsert(assets_map, asset, updated);
            
            // Update distributed_assets when upgrading position
            if (simple_map::contains_key(&wallet.distributed_assets, &asset)) {
                let current_distributed = simple_map::borrow(&wallet.distributed_assets, &asset);
                simple_map::upsert(&mut wallet.distributed_assets, asset, *current_distributed + amount);
            } else {
                simple_map::upsert(&mut wallet.distributed_assets, asset, amount);
            };
            
            i = i + 1;
        };

        event::emit(AddLiquidityEvent {
            wallet_id: wallet_id,
            position,
            total_assets: *assets_map,
            timestamp: timestamp::now_seconds(),
        });

    }


    //INTERNAL: ONLY CALLED BY DATA OBJECT SIGNER
    // use when close position and claim rewards to the wallet account
    public fun add_profit_unclaimed(
        data_signer: &signer,
        wallet_id: vector<u8>,
        position: address,
        asset: address,
        amount: u64, 
        fee_amount: u64
    ) acquires WalletAccount {
        verify_wallet_position(wallet_id, position);
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account_mut = borrow_global_mut<WalletAccount>(addr);
        assert!(signer::address_of(data_signer) == access_control::get_data_object_address(), error::permission_denied(E_NOT_OWNER));
        // Transfer fee asset to the data object
        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet_account_mut),
            object::address_to_object<Metadata>(asset),
            access_control::get_data_object_address(),
            fee_amount
        );

        access_control::add_withdraw_fee(
            data_signer,
            asset,
            fee_amount
        );

        let protocol_amount = access_control::calculate_protocol_fee(amount);

        primary_fungible_store::transfer(
            &get_wallet_account_signer_internal(wallet_account_mut),
            object::address_to_object<Metadata>(asset),
            access_control::get_data_object_address(),
            protocol_amount
        );

        let referral_fee = if (wallet_account_mut.referral){
            access_control::calculate_referral_fee(protocol_amount) // 25% of protocol amount
        } else {
            0
        };

        access_control::add_referral_fee(
            data_signer,
            asset,
            referral_fee
        );

        access_control::add_protocol_fee(
            data_signer,
            asset,
            protocol_amount - referral_fee // 75% of protocol amount
        );
        let user_amount = amount - protocol_amount;
        if (simple_map::contains_key(&wallet_account_mut.profit_unclaimed, &asset)) {
            let current_amount = simple_map::borrow(&wallet_account_mut.profit_unclaimed, &asset);
            simple_map::upsert(&mut wallet_account_mut.profit_unclaimed, asset, *current_amount + user_amount - fee_amount);
        } else {
            simple_map::upsert(&mut wallet_account_mut.profit_unclaimed, asset, user_amount - fee_amount);
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
                timestamp: timestamp::now_seconds(),
            }
        );
    }
    // -- Private
    fun verify_wallet_position(
        wallet_id: vector<u8>,
        position: address
    ) acquires WalletAccount {
        let addr = get_wallet_account_object_address(wallet_id);
        assert!(object::object_exists<WalletAccount>(addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        let wallet_account = borrow_global<WalletAccount>(addr);
        assert!(simple_map::contains_key(&wallet_account.position_opened, &position), error::not_found(E_POSITION_NOT_EXISTS));
    }

    fun get_wallet_account_object_seed(wallet_id: vector<u8>): vector<u8> {
        bcs::to_bytes(&string_utils::format2(&b"{}_{}", WALLET_ACCOUNT_SEED, wallet_id))
    }

    fun connect_wallet_internal(sender: &signer, wallet_account: &mut WalletAccount) {
        let wallet_address = signer::address_of(sender);
        let wallet_account_addr = get_wallet_account_object_address(wallet_account.wallet_id);
        assert!(object::object_exists<WalletAccount>(wallet_account_addr), error::not_found(E_WALLET_ACCOUNT_NOT_EXISTS));
        assert!(!exists<WalletAccountObject>(wallet_address), error::already_exists(E_WALLET_ACCOUNT_ALREADY_CONNECTED));
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
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    fun get_wallet_account_signer_internal(
        wallet_account: &WalletAccount,
    ): signer {
        object::generate_signer_for_extending(&wallet_account.extend_ref)
    }
}
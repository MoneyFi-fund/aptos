module thalaswap_v2::pool {
    // import necessary modules for me
    use std::string;
    use std::vector;
    use std::option;
    use std::signer;

    use aptos_framework::object;
    use aptos_framework::fungible_asset;
    use aptos_framework::smart_table;
    use aptos_framework::smart_vector;

    use rate_limiter::rate_limiter::RateLimiter;

    struct Pool has key {
        extend_ref: object::ExtendRef,
        assets_metadata: vector<object::Object<fungible_asset::Metadata>>,
        pool_type: u8,
        swap_fee_bps: u64,
        locked: bool,
        lp_token_mint_ref: fungible_asset::MintRef,
        lp_token_transfer_ref: fungible_asset::TransferRef,
        lp_token_burn_ref: fungible_asset::BurnRef
    }

    struct RateLimit has key {
        asset_rate_limiters: smart_table::SmartTable<object::Object<fungible_asset::Metadata>, rate_limiter::rate_limiter::RateLimiter>,
        whitelisted_users: vector<address>
    }

    struct AddLiquidityEvent has drop, store {
        pool_obj: object::Object<Pool>,
        metadata: vector<object::Object<fungible_asset::Metadata>>,
        amounts: vector<u64>,
        minted_lp_token_amount: u64,
        pool_balances: vector<u64>
    }

    struct Flashloan {
        pool_obj: object::Object<Pool>,
        amounts: vector<u64>
    }

    struct FlashloanEvent has drop, store {
        pool_obj: object::Object<Pool>,
        pool_balances: vector<u64>,
        metadata: vector<object::Object<fungible_asset::Metadata>>,
        amounts: vector<u64>
    }

    struct PauseFlag has key {
        swap_paused: bool,
        liquidity_paused: bool,
        flashloan_paused: bool
    }

    struct RemoveLiquidityEvent has drop, store {
        pool_obj: object::Object<Pool>,
        metadata: vector<object::Object<fungible_asset::Metadata>>,
        amounts: vector<u64>,
        burned_lp_token_amount: u64,
        pool_balances: vector<u64>
    }

    struct StablePool has key {
        amp_factor: u64,
        precision_multipliers: vector<u64>
    }

    struct SwapEvent has drop, store {
        pool_obj: object::Object<Pool>,
        metadata: vector<object::Object<fungible_asset::Metadata>>,
        idx_in: u64,
        idx_out: u64,
        amount_in: u64,
        amount_out: u64,
        total_fee_amount: u64,
        protocol_fee_amount: u64,
        pool_balances: vector<u64>
    }

    struct TwapOracle has drop, store, key {
        pool_obj: object::Object<Pool>,
        metadata_x: object::Object<fungible_asset::Metadata>,
        metadata_y: object::Object<fungible_asset::Metadata>,
        cumulative_price_x: u128,
        cumulative_price_y: u128,
        spot_price_x: u128,
        spot_price_y: u128,
        timestamp: u64
    }

    struct AddLiquidityPreview has drop {
        minted_lp_token_amount: u64,
        refund_amounts: vector<u64>
    }

    struct CreateTwapOracleEvent has drop, store {
        oracle_obj: object::Object<TwapOracle>,
        pool_obj: object::Object<Pool>,
        metadata_x: object::Object<fungible_asset::Metadata>,
        metadata_y: object::Object<fungible_asset::Metadata>
    }

    struct MetaStablePool has key {
        oracle_names: vector<string::String>,
        rates: vector<u128>,
        last_updated: u64
    }

    struct PoolCreationEvent has drop, store {
        pool_obj: object::Object<Pool>,
        metadata: vector<object::Object<fungible_asset::Metadata>>,
        amounts: vector<u64>,
        minted_lp_token_amount: u64,
        swap_fee_bps: u64
    }

    struct PoolParamChangeEvent has drop, store {
        pool_obj: object::Object<Pool>,
        name: string::String,
        prev_value: u64,
        new_value: u64
    }

    struct RateLimitUpdateEvent has drop, store {
        asset_metadata: object::Object<fungible_asset::Metadata>,
        window_max_qty: u128,
        window_duration_seconds: u64
    }

    struct RemoveLiquidityPreview has drop {
        withdrawn_amounts: vector<u64>
    }

    struct RemoveTwapOracleEvent has drop, store {
        pool_obj: object::Object<Pool>,
        metadata_x: object::Object<fungible_asset::Metadata>,
        metadata_y: object::Object<fungible_asset::Metadata>
    }

    struct SwapFeeMultipliers has key {
        traders: smart_table::SmartTable<address, u64>
    }

    struct SwapPreview has drop {
        amount_in: u64,
        amount_in_post_fee: u64,
        amount_out: u64,
        amount_normalized_in: u128,
        amount_normalized_out: u128,
        total_fee_amount: u64,
        protocol_fee_amount: u64,
        idx_in: u64,
        idx_out: u64,
        swap_fee_bps: u64
    }

    struct SyncRatesEvent has drop, store {
        pool_obj: object::Object<Pool>,
        oracle_names: vector<string::String>,
        rates: vector<u128>,
        last_updated: u64
    }

    struct ThalaSwap has key {
        fees_metadata: vector<object::Object<fungible_asset::Metadata>>,
        pools: smart_vector::SmartVector<object::Object<Pool>>,
        swap_fee_protocol_allocation_bps: u64,
        flashloan_fee_bps: u64
    }

    struct ThalaSwapParamChangeEvent has drop, store {
        name: string::String,
        prev_value: u64,
        new_value: u64
    }

    struct UpdateTwapOracleEvent has drop, store {
        oracle_obj: object::Object<TwapOracle>,
        pool_obj: object::Object<Pool>,
        metadata_x: object::Object<fungible_asset::Metadata>,
        metadata_y: object::Object<fungible_asset::Metadata>,
        cumulative_price_x: u128,
        cumulative_price_y: u128,
        spot_price_x: u128,
        spot_price_y: u128,
        timestamp: u64
    }

    struct WeightedPool has key {
        weights: vector<u64>
    }

    public entry fun remove_liquidity_entry(
        arg0: &signer,
        arg1: object::Object<Pool>,
        arg2: object::Object<fungible_asset::Metadata>,
        arg3: u64,
        arg4: vector<u64>
    ) {
        abort(0)
    }

    public fun pool_assets_metadata(
        arg0: object::Object<Pool>
    ): vector<object::Object<fungible_asset::Metadata>> acquires Pool {
        let v0 = arg0;
        borrow_global<Pool>(object::object_address<Pool>(&v0)).assets_metadata
    }

    public fun preview_add_liquidity_stable(arg0: object::Object<Pool>, arg1: vector<object::Object<fungible_asset::Metadata>>, arg2: vector<u64>) : AddLiquidityPreview  {
        
        AddLiquidityPreview{
            minted_lp_token_amount : 0, 
            refund_amounts         : vector::empty<u64>(),
        }
    }

    public fun add_liquidity_preview_info(arg0: AddLiquidityPreview) : (u64, vector<u64>) {
        (arg0.minted_lp_token_amount, arg0.refund_amounts)
    }

    public fun pool_lp_token_metadata(arg0: object::Object<Pool>) : object::Object<fungible_asset::Metadata>  acquires Pool {
        let v0 = arg0;
        let assets_metadata_vector = borrow_global<Pool>(object::object_address<Pool>(&v0)).assets_metadata; 
        *vector::borrow(&assets_metadata_vector, 0)
    }

    public fun preview_swap_exact_in_stable(arg0: object::Object<Pool>, arg1: object::Object<fungible_asset::Metadata>, arg2: object::Object<fungible_asset::Metadata>, arg3: u64, arg4: option::Option<address>) : SwapPreview{
        SwapPreview{
            amount_in             : 0, 
            amount_in_post_fee    : 0, 
            amount_out            : 0, 
            amount_normalized_in  : 0, 
            amount_normalized_out : 0, 
            total_fee_amount      : 0, 
            protocol_fee_amount   : 0, 
            idx_in                : 0, 
            idx_out               : 0, 
            swap_fee_bps          : 0,
        }
    }

    public fun swap_preview_info(arg0: SwapPreview) : (u64, u64, u64, u128, u128, u64, u64, u64, u64, u64) {
        (arg0.amount_in, arg0.amount_in_post_fee, arg0.amount_out, arg0.amount_normalized_in, arg0.amount_normalized_out, arg0.total_fee_amount, arg0.protocol_fee_amount, arg0.idx_in, arg0.idx_out, arg0.swap_fee_bps)
    }

    public fun preview_remove_liquidity(arg0: object::Object<Pool>, arg1: object::Object<fungible_asset::Metadata>, arg2: u64) : RemoveLiquidityPreview {
        RemoveLiquidityPreview{withdrawn_amounts: vector::empty<u64>()}
    }

    public fun remove_liquidity_preview_info(arg0: RemoveLiquidityPreview) : vector<u64> {
        arg0.withdrawn_amounts
    }
}   



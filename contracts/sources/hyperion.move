module moneyfi::hyperion {
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::error;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{
        Self,
        FungibleAsset,
        Metadata
    };
    use aptos_framework::primary_fungible_store;

    use dex_contract::i32::{Self, I32};
    use dex_contract::router_v3;
    use dex_contract::pool_v3;
    use dex_contract::position_v3::{Self, Info};


    //const FEE_RATE_VEC: vector<u64> = vector[100, 500, 3000, 10000]; fee_tier is [0, 1, 2, 3] for [0.01%, 0.05%, 0.3%, 1%] ??
    //-- Entries

    //-- Views
    #[view]
    public fun get_tick(
        _position: Object<Info>
    ): (I32, I32) {
        position_v3::get_tick(_position)
    }

    #[view]
     public fun get_liquidity(
        _position: Object<Info>
    ): u128 {
        position_v3::get_liquidity(_position)
    }

     #[view]
    public fun get_amount_by_liquidity(_position: Object<Info>): (u64, u64) {
        router_v3::get_amount_by_liquidity(_position)
    }

    #[view]
    public fun optimal_liquidity_amounts(
        _tick_lower_u32: u32,
        _tick_upper_u32: u32,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _amount_a_desired: u64,
        _amount_b_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64,
    ): (u128, u64, u64) {
        router_v3::optimal_liquidity_amounts(
            _tick_lower_u32,
            _tick_upper_u32,
            _token_a,
            _token_b,
            _fee_tier,
            _amount_a_desired,
            _amount_b_desired,
            _amount_a_min,
            _amount_b_min
        )
    }

    #[view]
    public fun optimal_liquidity_amounts_from_a(
        _tick_lower_u32: u32,
        _tick_upper_u32: u32,
        _tick_current_u32: u32,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _amount_a_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64,
    ): (u128, u64) {
        router_v3::optimal_liquidity_amounts_from_a(
            _tick_lower_u32,
            _tick_upper_u32,
            _tick_current_u32,
            _token_a,
            _token_b,
            _fee_tier,
            _amount_a_desired,
            _amount_a_min,
            _amount_b_min
        )
    }

    //-- Public
    public fun open_position(
        _user: &signer,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _tick_lower: u32,
        _tick_upper: u32,
    ): Object<Info> {
        pool_v3::open_position(
            _user,
            _token_a,
            _token_b,
            _fee_tier,
            _tick_lower,
            _tick_upper
        )
    }

   public fun add_liquidity_single(
       _user: &signer,
       _position: Object<Info>,
       _token_input: Object<Metadata>,
       _token_pair: Object<Metadata>,
       _amount_in: u64,
       _amount_out_min: u256,
       _amount_out_max: u256,
       _slippage_numerator: u256,
       _slippage_denominator: u256,
   )   {
        router_v3::add_liquidity_single(
            _user,
            _position,
            _token_input,
            _token_pair,
            _amount_in,
            _amount_out_min,
            _amount_out_max,
            _slippage_numerator,
            _slippage_denominator
        );
   }

   

    public fun claim_rewards(
        _user: &signer,
        _position: Object<position_v3::Info>,
        _receiver: address
    ) {
        router_v3::claim_rewards(
            _user,
            _position,
            _receiver
        );
    }

    public fun exact_input_swap_entry(
        _user: &signer,
        _fee_tier: u8,
        _amount_in: u64,
        _amount_out_min: u64,
        _sqrt_price_limit: u128,
        _from_token: Object<Metadata>,
        _to_token: Object<Metadata>,
        _recipient: address,
        _deadline: u64
    ) {
        router_v3::exact_input_swap_entry(
            _user,
            _fee_tier,
            _amount_in,
            _amount_out_min,
            _sqrt_price_limit,
            _from_token,
            _to_token,
            _recipient,
            _deadline
        );
    }

    public fun add_liquidity(
        _lp: &signer,
        _lp_object: Object<position_v3::Info>,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _amount_a_desired: u64,
        _amount_b_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64,
        _deadline: u64
    ) {
        router_v3::add_liquidity(
            _lp,
            _lp_object,
            _token_a,
            _token_b,
            _fee_tier,
            _amount_a_desired,
            _amount_b_desired,
            _amount_a_min,
            _amount_b_min,
            _deadline
        );
    }

    public entry fun create_liquidity(
        _lp: &signer,
        _token_a: Object<Metadata>,
        _token_b: Object<Metadata>,
        _fee_tier: u8,
        _tick_lower: u32,
        _tick_upper: u32,
        _tick_current: u32,
        _amount_a_desired: u64,
        _amount_b_desired: u64,
        _amount_a_min: u64,
        _amount_b_min: u64,
        _deadline: u64
    ) {
        router_v3::create_liquidity(
            _lp,
            _token_a,
            _token_b,
            _fee_tier,
            _tick_lower,
            _tick_upper,
            _tick_current,
            _amount_a_desired,
            _amount_b_desired,
            _amount_a_min,
            _amount_b_min,
            _deadline
        );
    }
    //-- Private

}

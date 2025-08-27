module thalaswap_v2::coin_wrapper {
    use aptos_framework::object;
    use aptos_framework::fungible_asset;

    use thalaswap_v2::pool;

    struct Notacoin {
        dummy_field: bool
    }

    public entry fun add_liquidity_stable<T0, T1, T2, T3, T4, T5>(
        arg0: &signer,
        arg1: 0x1::object::Object<pool::Pool>,
        arg2: vector<u64>,
        arg3: u64
    ) {
        abort(0)
    }

    public entry fun swap_exact_in_stable<T0>(// T0 AptosCoin
        arg0: &signer,
        arg1: object::Object<pool::Pool>,
        arg2: object::Object<fungible_asset::Metadata>,
        arg3: u64,
        arg4: object::Object<fungible_asset::Metadata>,
        arg5: u64
    ) {
        abort(0)
    }
}

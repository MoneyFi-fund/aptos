module thalaswap_v2::coin_wrapper {
    use std::signer;
    use std::vector;
    use aptos_framework::object::{Self, Object};

    struct Notacoin {
        dummy_field: bool
    }

    public entry fun add_liquidity_stable<T0, T1, T2, T3, T4, T5>(
        arg0: &signer,
        arg1: 0x1::object::Object<thalaswap_v2::pool::Pool>,
        arg2: vector<u64>,
        arg3: u64
    ) {
        abort(0)
    }
}

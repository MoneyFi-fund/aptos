module leverage::leverage {
    use std::vector;
    use std::signer;
    use aptos_framework::object;
    use aptos_framework::fungible_asset;
    use lending::lending;
    use thalaswap_v2::pool;

    // arg2: Health Factor
    // arg3: loop count 
    // arg4: amount 
    public entry fun loop_supply_x_borrow_x_entry<T0>(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64, arg3: u64, arg4: u64) {
        abort(0);
    }

    public entry fun loop_supply_x_borrow_x_fa_entry(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64, arg3: u64, arg4: u64) {
        abort(0);
    }

    public entry fun loop_supply_x_borrow_y_entry<T0, T1>(arg0: &signer, arg1: object::Object<lending::Market>, arg2: object::Object<lending::Market>, arg3: u64, arg4: u64, arg5: u64) {
        abort(0);
    }

    public entry fun loop_supply_x_borrow_y_fa_entry(arg0: &signer, arg1: object::Object<lending::Market>, arg2: object::Object<lending::Market>, arg3: vector<object::Object<pool::Pool>>, arg4: vector<object::Object<fungible_asset::Metadata>>, arg5: u64, arg6: u64, arg7: u64, arg8: object::Object<fungible_asset::Metadata>) {
        abort(0);
    }
}
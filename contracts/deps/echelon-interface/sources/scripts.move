module lending::scripts {
    use std::vector;
    use std::signer;
    use std::string;
    use aptos_framework::coin;
    use aptos_framework::fungible_asset;
    use aptos_framework::object;

    use lending::lending;
    
    struct Notacoin {
        dummy_field: bool,
    }

    public entry fun withdraw<T0>(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun borrow<T0>(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun claim_reward<T0>(arg0: &signer, arg1: string::String) {
        abort(0x1);
    }
    
    public entry fun claim_reward_fa(arg0: &signer, arg1: object::Object<fungible_asset::Metadata>, arg2: string::String) {
        abort(0x1);
    }
    
    public entry fun borrow_fa(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }

    public entry fun repay<T0>(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun repay_fa(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun supply<T0>(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun supply_fa(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun withdraw_fa(arg0: &signer, arg1: object::Object<lending::Market>, arg2: u64) {
        abort(0x1);
    }
    
    public entry fun claim_all_rewards<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9>(arg0: &signer, arg1: vector<object::Object<fungible_asset::Metadata>>, arg2: vector<string::String>, arg3: vector<string::String>) {
        abort(0x1);
    }

    public entry fun repay_all<T0>(arg0: &signer, arg1: object::Object<lending::Market>) {
        abort(0x1);
    }
    
    public entry fun repay_all_fa(arg0: &signer, arg1: object::Object<lending::Market>) {
        abort(0x1);
    }
    
    public entry fun withdraw_all<T0>(arg0: &signer, arg1: object::Object<lending::Market>) {
        abort(0x1);
    }
    
    public entry fun withdraw_all_fa(arg0: &signer, arg1: object::Object<lending::Market>) {
        abort(0x1);
    }
}
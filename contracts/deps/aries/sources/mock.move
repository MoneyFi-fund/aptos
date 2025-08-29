// #[test_only]
module aries::mock {
    use aptos_std::copyable_any as any;
    use aptos_framework::ordered_map::{Self, OrderedMap};

    struct Mock has key {
        calls: OrderedMap<vector<u8>, vector<any::Any>>
    }

    public fun init(sender: &signer) {
        move_to(sender, Mock { calls: ordered_map::new() })
    }

    public fun on<T: copy + drop + store>(
        method: vector<u8>, return_vaule: T, times: u64
    ) acquires Mock {
        let mock = borrow_global_mut<Mock>(@aries);
        if (!mock.calls.contains(&method)) {
            mock.calls.add(method, vector[]);
        };

        let values = mock.calls.borrow_mut(&method);
        let i = 0;
        while (i < times) {
            values.push_back(any::pack(return_vaule));
            i = i + 1;
        }
    }

    public fun reset() acquires Mock {
        let mock = borrow_global_mut<Mock>(@aries);
        mock.calls = ordered_map::new();
    }

    public fun get_call_data<T: drop>(method: vector<u8>, default: T): T acquires Mock {
        let mock = borrow_global_mut<Mock>(@aries);
        if (mock.calls.contains(&method)) {
            let values = mock.calls.borrow_mut(&method);
            if (values.length() > 0) {
                return any::unpack<T>(values.remove(0));
            }
        };

        default
    }
}

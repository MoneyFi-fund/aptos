module decimal::decimal {
    struct Decimal has copy, drop, store {
        val: u128
    }

    public fun add(arg0: Decimal, arg1: Decimal): Decimal {
        assert!(
            arg0.val + arg1.val <= 340282366920938463463374607431768211455,
            1
        );
        Decimal { val: arg0.val + arg1.val }
    }

    public fun as_percentage(arg0: Decimal): u128 {
        arg0.val / 10000000000000000
    }

    public fun as_u128(arg0: Decimal): u128 {
        arg0.val / 1000000000000000000
    }

    public fun as_u64(arg0: Decimal): u64 {
        let v0 = as_u128(arg0);
        assert!(v0 <= 18446744073709551615, 0);
        v0 as u64
    }

    public fun ceil(arg0: Decimal): Decimal {
        let v0 = floor(arg0);
        if (eq(arg0, v0)) {
            return arg0
        };
        add(v0, from_u64(1))
    }

    public fun ceil_u64(arg0: Decimal): u64 {
        as_u64(ceil(arg0))
    }

    public fun div(arg0: Decimal, arg1: Decimal): Decimal {
        Decimal {
            val: decimal::u128_math::mul_div_u128(
                arg0.val, 1000000000000000000, arg1.val
            )
        }
    }

    public fun div_u128(arg0: Decimal, arg1: u128): Decimal {
        div(arg0, from_u128(arg1))
    }

    public fun div_u64(arg0: Decimal, arg1: u64): Decimal {
        div_u128(arg0, arg1 as u128)
    }

    public fun eq(arg0: Decimal, arg1: Decimal): bool {
        arg0.val == arg1.val
    }

    public fun floor(arg0: Decimal): Decimal {
        let v0 = Decimal { val: arg0.val % 1000000000000000000 };
        sub(arg0, v0)
    }

    public fun floor_u64(arg0: Decimal): u64 {
        as_u64(floor(arg0))
    }

    public fun from_bips(arg0: u128): Decimal {
        from_scaled_val(arg0 * 100000000000000)
    }

    public fun from_millionth(arg0: u128): Decimal {
        from_scaled_val(arg0 * 1000000000000)
    }

    public fun from_percentage(arg0: u128): Decimal {
        mul(from_u128(arg0), hundredth())
    }

    public fun from_scaled_val(arg0: u128): Decimal {
        Decimal { val: arg0 }
    }

    public fun from_u128(arg0: u128): Decimal {
        Decimal { val: 1000000000000000000 * arg0 }
    }

    public fun from_u64(arg0: u64): Decimal {
        from_u128(arg0 as u128)
    }

    public fun from_u8(arg0: u8): Decimal {
        from_u128(arg0 as u128)
    }

    public fun gt(arg0: Decimal, arg1: Decimal): bool {
        arg0.val > arg1.val
    }

    public fun gte(arg0: Decimal, arg1: Decimal): bool {
        arg0.val >= arg1.val
    }

    public fun half(): Decimal {
        Decimal { val: 1000000000000000000 / 2 }
    }

    public fun hundredth(): Decimal {
        Decimal { val: 10000000000000000 }
    }

    public fun lt(arg0: Decimal, arg1: Decimal): bool {
        arg0.val < arg1.val
    }

    public fun lte(arg0: Decimal, arg1: Decimal): bool {
        arg0.val <= arg1.val
    }

    public fun max(arg0: Decimal, arg1: Decimal): Decimal {
        if (gte(arg0, arg1)) {
            return arg0
        };
        arg1
    }

    public fun min(arg0: Decimal, arg1: Decimal): Decimal {
        if (lte(arg0, arg1)) {
            return arg0
        };
        arg1
    }

    public fun mul(arg0: Decimal, arg1: Decimal): Decimal {
        Decimal {
            val: decimal::u128_math::mul_div_u128(
                arg0.val, arg1.val, 1000000000000000000
            )
        }
    }

    public fun mul_div(arg0: Decimal, arg1: Decimal, arg2: Decimal): Decimal {
        from_scaled_val(decimal::u128_math::mul_div_u128(arg0.val, arg1.val, arg2.val))
    }

    public fun mul_u128(arg0: Decimal, arg1: u128): Decimal {
        mul(arg0, from_u128(arg1))
    }

    public fun mul_u64(arg0: Decimal, arg1: u64): Decimal {
        mul_u128(arg0, arg1 as u128)
    }

    public fun one(): Decimal {
        Decimal { val: 1000000000000000000 }
    }

    public fun raw(arg0: Decimal): u128 {
        arg0.val
    }

    public fun round(arg0: Decimal): Decimal {
        let v0 = floor(arg0);
        let v1 = add(v0, from_u64(1));
        if (gte(arg0, div(add(v0, v1), from_u64(2)))) {
            return v1
        };
        v0
    }

    public fun round_u64(arg0: Decimal): u64 {
        as_u64(round(arg0))
    }

    public fun scaling_factor(): u128 {
        1000000000000000000
    }

    public fun sub(arg0: Decimal, arg1: Decimal): Decimal {
        Decimal { val: arg0.val - arg1.val }
    }

    public fun tenth(): Decimal {
        Decimal { val: 1000000000000000000 / 10 }
    }

    public fun zero(): Decimal {
        Decimal { val: 0 }
    }

    // decompiled from Move bytecode v6
}

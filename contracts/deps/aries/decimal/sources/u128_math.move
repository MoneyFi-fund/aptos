module 0x9770fa9c725cbd97eb50b2be5f7416efdfd1f1554beb0750d4dae4c64e860da3::u128_math {
    public fun ascending_u128(arg0: u128, arg1: u128): (u128, u128) {
        if (arg0 <= arg1) {
            (arg0, arg1)
        } else {
            (arg1, arg0)
        }
    }

    public fun bits_u128(arg0: u128): u8 {
        128 - leading_zeros_u128(arg0)
    }

    fun gcd_u128(arg0: u128, arg1: u128): u128 {
        if (arg0 == 0) { arg1 }
        else {
            gcd_u128(arg1 % arg0, arg0)
        }
    }

    fun is_mul_128_safe(arg0: u128, arg1: u128): bool {
        (bits_u128(arg0) as u64) + (bits_u128(arg1) as u64) <= 128
    }

    public fun leading_zeros_u128(arg0: u128): u8 {
        let v0 = 128;
        let v1 = v0;
        if (arg0 >> 64 > 0) {
            v1 = v0 - 64;
            arg0 = arg0 >> 64;
        };
        if (arg0 >> 32 > 0) {
            v1 = v1 - 32;
            arg0 = arg0 >> 32;
        };
        if (arg0 >> 16 > 0) {
            v1 = v1 - 16;
            arg0 = arg0 >> 16;
        };
        if (arg0 >> 8 > 0) {
            v1 = v1 - 8;
            arg0 = arg0 >> 8;
        };
        if (arg0 >> 4 > 0) {
            v1 = v1 - 4;
            arg0 = arg0 >> 4;
        };
        if (arg0 >> 2 > 0) {
            v1 = v1 - 2;
            arg0 = arg0 >> 2;
        };
        if (arg0 >> 1 > 0) { v1 - 2 }
        else {
            v1 - (arg0 as u8)
        }
    }

    public fun mul_div_u128(arg0: u128, arg1: u128, arg2: u128): u128 {
        assert!(arg2 != 0, 2);
        let (v0, v1) = reduce_fraction_u128(arg0, arg2);
        let (v2, v3) = reduce_fraction_u128(arg1, v1);
        if ((bits_u128(v0) as u64) + (bits_u128(v2) as u64) <= 128) {
            v0 * v2 / v3
        } else {
            let v5 = v0 / v3;
            let v6 = v0 % v3;
            let v7 = v2 / v3;
            let v8 = v2 % v3;
            assert!(is_mul_128_safe(v5, v7), 1);
            assert!(is_mul_128_safe(v5 * v7, v3), 1);
            let v9 =
                if ((bits_u128(v6) as u64) + (bits_u128(v8) as u64) <= 128) {
                    v5 * v7 * v3 + v6 * v7 + v5 * v8 + v6 * v8 / v3
                } else {
                    v5 * v7 * v3 + v6 * v7 + v5 * v8
                        + mul_div_u128_when_overflow(v6, v8, v3)
                };
            v9
        }
    }

    fun mul_div_u128_when_overflow(arg0: u128, arg1: u128, arg2: u128): u128 {
        let v0 = bits_u128(arg0) as u64;
        let v1 = bits_u128(arg1) as u64;
        let v2 = v0 + v1 - 128;
        let v3 = v2 * v0 / (v0 + v1);
        let v4 = v2 as u8;
        if (arg2 >> v4 == 0) {
            abort 1
        };
        (arg0 >> (v3 as u8)) * (arg1 >> ((v2 - v3) as u8)) / (arg2 >> v4)
    }

    fun reduce_fraction_u128(arg0: u128, arg1: u128): (u128, u128) {
        let v0 = gcd_u128(arg0, arg1);
        (arg0 / v0, arg1 / v0)
    }

    public fun tailing_zeros_u128(arg0: u128): u8 {
        let v0 = 0;
        let v1 = v0;
        if (arg0 >> 64 > 0) {
            v1 = v0 + 64;
            arg0 = arg0 >> 64;
        };
        if (arg0 >> 32 > 0) {
            v1 = v1 + 32;
            arg0 = arg0 >> 32;
        };
        if (arg0 >> 16 > 0) {
            v1 = v1 + 16;
            arg0 = arg0 >> 16;
        };
        if (arg0 >> 8 > 0) {
            v1 = v1 + 8;
            arg0 = arg0 >> 8;
        };
        if (arg0 >> 4 > 0) {
            v1 = v1 + 4;
            arg0 = arg0 >> 4;
        };
        if (arg0 >> 2 > 0) {
            v1 = v1 + 2;
            arg0 = arg0 >> 2;
        };
        v1 + ((arg0 / 2) as u8)
    }
    // decompiled from Move bytecode v6
}

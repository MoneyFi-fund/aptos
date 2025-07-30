module thala_v2_rate_limiter::rate_limiter {
    struct RateLimiter has copy, drop, store {
        config: RateLimiterConfig,
        window_start: u64,
        prev_qty: u128,
        curr_qty: u128,
    }

    struct RateLimiterConfig has copy, drop, store {
        window_duration: u64,
        window_max_qty: u128,
    }
}

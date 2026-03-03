const std = @import("std");

/// Token bucket rate limiter.
/// Tokens refill at `rate` per second up to `burst` capacity.
pub const RateLimiter = struct {
    tokens: f64,
    max_tokens: f64,
    refill_rate: f64, // tokens per nanosecond
    last_refill: i128,

    pub fn init(requests_per_second: u32, burst_size: u32) RateLimiter {
        // TODO: Exercise 04 - Initialize the rate limiter
        // Steps:
        //   1. Convert burst_size to f64 using @floatFromInt
        //   2. Calculate refill_rate: requests_per_second / ns_per_s
        //      (both converted to f64 via @floatFromInt)
        //   3. Set tokens to burst (starts full)
        //   4. Set last_refill to std.time.nanoTimestamp()
        _ = requests_per_second;
        _ = burst_size;
        return .{
            .tokens = 0,
            .max_tokens = 0,
            .refill_rate = 0,
            .last_refill = 0,
        };
    }

    pub fn allow(self: *RateLimiter) bool {
        // TODO: Exercise 04 - Check if a request is allowed
        // Steps:
        //   1. Call self.refill() to top up tokens
        //   2. If tokens >= 1.0, consume one token and return true
        //   3. Otherwise return false
        _ = self;
        return false;
    }

    fn refill(self: *RateLimiter) void {
        // TODO: Exercise 04 - Refill tokens based on elapsed time
        // Steps:
        //   1. Get current time with std.time.nanoTimestamp()
        //   2. Calculate elapsed = now - self.last_refill
        //   3. If elapsed <= 0, return early
        //   4. Calculate new_tokens = @floatFromInt(elapsed) * self.refill_rate
        //   5. Set tokens to @min(self.max_tokens, self.tokens + new_tokens)
        //   6. Update last_refill = now
        _ = self;
    }
};

// ============================================================================
// Exercise 04 Tests — Token Bucket Rate Limiter
// ============================================================================

test "04-01: init creates limiter with full bucket" {
    const rl = RateLimiter.init(100, 10);
    try std.testing.expectEqual(@as(f64, 10.0), rl.max_tokens);
    try std.testing.expectEqual(@as(f64, 10.0), rl.tokens);
    try std.testing.expect(rl.refill_rate > 0);
}

test "04-02: allow consumes tokens" {
    var rl = RateLimiter.init(100, 5);

    // Should allow 5 requests (burst size)
    var allowed: u32 = 0;
    for (0..5) |_| {
        if (rl.allow()) allowed += 1;
    }
    try std.testing.expectEqual(@as(u32, 5), allowed);
}

test "04-03: allow denies when bucket is empty" {
    var rl = RateLimiter.init(100, 3);

    // Exhaust the bucket
    for (0..3) |_| {
        _ = rl.allow();
    }

    // Next should be denied
    try std.testing.expect(!rl.allow());
    try std.testing.expect(!rl.allow());
}

test "04-04: allow drains exactly the burst amount" {
    var rl = RateLimiter.init(100, 10);

    var allowed: u32 = 0;
    for (0..20) |_| {
        if (rl.allow()) allowed += 1;
    }
    // Should allow exactly 10 (burst size), deny the rest
    try std.testing.expectEqual(@as(u32, 10), allowed);
}

test "04-05: init calculates correct refill rate" {
    const rl = RateLimiter.init(1000, 1);
    // refill_rate should be 1000 / 1_000_000_000
    const expected: f64 = 1000.0 / @as(f64, @floatFromInt(std.time.ns_per_s));
    try std.testing.expectApproxEqRel(expected, rl.refill_rate, 1e-10);
}

test "04-06: refill restores tokens after time passes" {
    var rl = RateLimiter.init(100, 5);

    // Drain all tokens
    for (0..5) |_| {
        _ = rl.allow();
    }
    try std.testing.expect(!rl.allow());

    // Simulate time passing by backdating last_refill
    rl.last_refill -= @as(i128, std.time.ns_per_s); // 1 second ago

    // Should have refilled ~100 tokens, capped at max_tokens (5)
    try std.testing.expect(rl.allow());
}

test "04-07: tokens never exceed max_tokens" {
    var rl = RateLimiter.init(1000, 5);

    // Backdate last_refill by 10 seconds — would generate 10000 tokens
    rl.last_refill -= @as(i128, 10 * std.time.ns_per_s);
    rl.refill();

    // But should be capped at max_tokens
    try std.testing.expect(rl.tokens <= rl.max_tokens);
    try std.testing.expectEqual(@as(f64, 5.0), rl.tokens);
}

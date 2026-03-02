const std = @import("std");

/// Token bucket rate limiter.
/// Tokens refill at `rate` per second up to `burst` capacity.
pub const RateLimiter = struct {
    tokens: f64,
    max_tokens: f64,
    refill_rate: f64, // tokens per nanosecond
    last_refill: i128,

    pub fn init(requests_per_second: u32, burst_size: u32) RateLimiter {
        const burst: f64 = @floatFromInt(burst_size);
        return .{
            .tokens = burst,
            .max_tokens = burst,
            .refill_rate = @as(f64, @floatFromInt(requests_per_second)) / @as(f64, @floatFromInt(std.time.ns_per_s)),
            .last_refill = std.time.nanoTimestamp(),
        };
    }

    pub fn allow(self: *RateLimiter) bool {
        self.refill();
        if (self.tokens >= 1.0) {
            self.tokens -= 1.0;
            return true;
        }
        return false;
    }

    fn refill(self: *RateLimiter) void {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_refill;
        if (elapsed <= 0) return;

        const new_tokens = @as(f64, @floatFromInt(elapsed)) * self.refill_rate;
        self.tokens = @min(self.max_tokens, self.tokens + new_tokens);
        self.last_refill = now;
    }
};

test "rate limiter allows within budget" {
    var rl = RateLimiter.init(100, 10);

    // Should allow up to burst size
    var allowed: u32 = 0;
    for (0..10) |_| {
        if (rl.allow()) allowed += 1;
    }
    try std.testing.expectEqual(@as(u32, 10), allowed);

    // Next one should be denied (no time to refill)
    try std.testing.expect(!rl.allow());
}

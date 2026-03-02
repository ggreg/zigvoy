const std = @import("std");

pub const CircuitBreaker = struct {
    state: State = .closed,
    failure_count: u32 = 0,
    success_count: u32 = 0,
    failure_threshold: u32,
    reset_timeout_ms: u64,
    half_open_max: u32,
    last_failure_time: i64 = 0,
    half_open_requests: u32 = 0,

    pub const State = enum {
        closed, // Normal operation — requests flow through
        open, // Failures exceeded threshold — requests blocked
        half_open, // Testing if backend recovered — limited requests
    };

    pub fn init(failure_threshold: u32, reset_timeout_ms: u64, half_open_max: u32) CircuitBreaker {
        return .{
            .failure_threshold = failure_threshold,
            .reset_timeout_ms = reset_timeout_ms,
            .half_open_max = half_open_max,
        };
    }

    pub fn allowRequest(self: *CircuitBreaker) bool {
        switch (self.state) {
            .closed => return true,
            .open => {
                const now = std.time.milliTimestamp();
                const elapsed: u64 = @intCast(now - self.last_failure_time);
                if (elapsed >= self.reset_timeout_ms) {
                    std.log.info("circuit breaker transitioning to half-open", .{});
                    self.state = .half_open;
                    self.half_open_requests = 0;
                    return true;
                }
                return false;
            },
            .half_open => {
                if (self.half_open_requests < self.half_open_max) {
                    self.half_open_requests += 1;
                    return true;
                }
                return false;
            },
        }
    }

    pub fn recordSuccess(self: *CircuitBreaker) void {
        switch (self.state) {
            .closed => {
                self.failure_count = 0;
            },
            .half_open => {
                self.success_count += 1;
                if (self.success_count >= self.half_open_max) {
                    std.log.info("circuit breaker closing (recovered)", .{});
                    self.state = .closed;
                    self.failure_count = 0;
                    self.success_count = 0;
                }
            },
            .open => {},
        }
    }

    pub fn recordFailure(self: *CircuitBreaker) void {
        self.last_failure_time = std.time.milliTimestamp();
        switch (self.state) {
            .closed => {
                self.failure_count += 1;
                if (self.failure_count >= self.failure_threshold) {
                    std.log.warn("circuit breaker opening after {d} failures", .{self.failure_count});
                    self.state = .open;
                }
            },
            .half_open => {
                std.log.warn("circuit breaker re-opening (half-open failure)", .{});
                self.state = .open;
                self.success_count = 0;
            },
            .open => {},
        }
    }
};

test "circuit breaker state transitions" {
    var cb = CircuitBreaker.init(3, 1000, 2);

    // Starts closed
    try std.testing.expectEqual(CircuitBreaker.State.closed, cb.state);
    try std.testing.expect(cb.allowRequest());

    // Fails up to threshold
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expect(cb.allowRequest()); // still closed
    cb.recordFailure();
    try std.testing.expectEqual(CircuitBreaker.State.open, cb.state);

    // Open — blocks requests
    try std.testing.expect(!cb.allowRequest());
}

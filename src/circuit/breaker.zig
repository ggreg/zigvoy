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
        // TODO: Exercise 05 - Initialize a circuit breaker
        // Return a CircuitBreaker with the given thresholds.
        // All counters start at 0, state starts at .closed.
        _ = failure_threshold;
        _ = reset_timeout_ms;
        _ = half_open_max;
        return .{
            .failure_threshold = 1,
            .reset_timeout_ms = 0,
            .half_open_max = 0,
        };
    }

    pub fn allowRequest(self: *CircuitBreaker) bool {
        // TODO: Exercise 05 - Decide whether to allow a request
        // Use an exhaustive switch on self.state:
        //   .closed → always allow
        //   .open → check if reset_timeout_ms has elapsed since last_failure_time
        //     using std.time.milliTimestamp() and @intCast.
        //     If elapsed, transition to .half_open (reset half_open_requests) and allow.
        //     Otherwise block.
        //   .half_open → allow if half_open_requests < half_open_max,
        //     incrementing the counter. Otherwise block.
        _ = self;
        return false;
    }

    pub fn recordSuccess(self: *CircuitBreaker) void {
        // TODO: Exercise 05 - Record a successful request
        // Switch on state:
        //   .closed → reset failure_count to 0
        //   .half_open → increment success_count; if >= half_open_max,
        //     transition to .closed and reset all counters
        //   .open → do nothing
        _ = self;
    }

    pub fn recordFailure(self: *CircuitBreaker) void {
        // TODO: Exercise 05 - Record a failed request
        // Update last_failure_time to std.time.milliTimestamp().
        // Switch on state:
        //   .closed → increment failure_count; if >= failure_threshold,
        //     transition to .open
        //   .half_open → transition back to .open, reset success_count
        //   .open → do nothing
        _ = self;
    }
};

// ============================================================================
// Exercise 05 Tests — Circuit Breaker State Machine
// ============================================================================

test "05-01: init starts in closed state" {
    const cb = CircuitBreaker.init(5, 30000, 3);
    try std.testing.expectEqual(CircuitBreaker.State.closed, cb.state);
    try std.testing.expectEqual(@as(u32, 5), cb.failure_threshold);
    try std.testing.expectEqual(@as(u64, 30000), cb.reset_timeout_ms);
    try std.testing.expectEqual(@as(u32, 3), cb.half_open_max);
}

test "05-02: closed state allows all requests" {
    var cb = CircuitBreaker.init(5, 30000, 3);
    try std.testing.expect(cb.allowRequest());
    try std.testing.expect(cb.allowRequest());
    try std.testing.expect(cb.allowRequest());
}

test "05-03: failures below threshold keep state closed" {
    var cb = CircuitBreaker.init(3, 30000, 2);
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expectEqual(CircuitBreaker.State.closed, cb.state);
    try std.testing.expect(cb.allowRequest());
}

test "05-04: reaching failure threshold opens the circuit" {
    var cb = CircuitBreaker.init(3, 30000, 2);
    cb.recordFailure();
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expectEqual(CircuitBreaker.State.open, cb.state);
}

test "05-05: open state blocks requests" {
    var cb = CircuitBreaker.init(2, 60000, 1);
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expectEqual(CircuitBreaker.State.open, cb.state);
    try std.testing.expect(!cb.allowRequest());
}

test "05-06: success resets failure count in closed state" {
    var cb = CircuitBreaker.init(3, 30000, 2);
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expectEqual(@as(u32, 2), cb.failure_count);

    cb.recordSuccess();
    try std.testing.expectEqual(@as(u32, 0), cb.failure_count);
}

test "05-07: open transitions to half_open after timeout" {
    var cb = CircuitBreaker.init(2, 100, 2);
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expectEqual(CircuitBreaker.State.open, cb.state);

    // Backdate the failure time so the timeout has elapsed
    cb.last_failure_time -= 200;
    try std.testing.expect(cb.allowRequest());
    try std.testing.expectEqual(CircuitBreaker.State.half_open, cb.state);
}

test "05-08: half_open limits requests to half_open_max" {
    var cb = CircuitBreaker.init(2, 100, 2);
    cb.recordFailure();
    cb.recordFailure();
    cb.last_failure_time -= 200;
    _ = cb.allowRequest(); // triggers transition to half_open

    // Should allow up to half_open_max
    try std.testing.expect(cb.allowRequest()); // 2nd (1st was the transition)
    try std.testing.expect(!cb.allowRequest()); // blocked
}

test "05-09: half_open recovers to closed after enough successes" {
    var cb = CircuitBreaker.init(2, 100, 2);
    cb.recordFailure();
    cb.recordFailure();
    cb.last_failure_time -= 200;
    _ = cb.allowRequest(); // transitions to half_open

    cb.recordSuccess();
    cb.recordSuccess();
    try std.testing.expectEqual(CircuitBreaker.State.closed, cb.state);
    try std.testing.expectEqual(@as(u32, 0), cb.failure_count);
}

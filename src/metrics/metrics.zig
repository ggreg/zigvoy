const std = @import("std");

pub const Metrics = struct {
    total_requests: std.atomic.Value(u64),
    active_connections: std.atomic.Value(u64),
    status_2xx: std.atomic.Value(u64),
    status_4xx: std.atomic.Value(u64),
    status_5xx: std.atomic.Value(u64),
    start_time: i64,

    pub fn init() Metrics {
        // TODO: Exercise 06 - Initialize all atomic counters to 0
        // Use std.atomic.Value(u64).init(0) for each counter.
        // Set start_time to std.time.timestamp().
        return .{
            .total_requests = std.atomic.Value(u64).init(0),
            .active_connections = std.atomic.Value(u64).init(0),
            .status_2xx = std.atomic.Value(u64).init(0),
            .status_4xx = std.atomic.Value(u64).init(0),
            .status_5xx = std.atomic.Value(u64).init(0),
            .start_time = 0,
        };
    }

    pub fn recordRequest(self: *Metrics, status: u16) void {
        // TODO: Exercise 06 - Record a request by status code
        // Steps:
        //   1. Increment total_requests using fetchAdd(1, .monotonic)
        //   2. Classify by status range:
        //      200-299 → increment status_2xx
        //      400-499 → increment status_4xx
        //      500+    → increment status_5xx
        _ = self;
        _ = status;
    }

    pub fn recordConnection(self: *Metrics) void {
        // TODO: Exercise 06 - Increment active connections
        // Use fetchAdd(1, .monotonic) on active_connections.
        _ = self;
    }

    pub fn recordDisconnection(self: *Metrics) void {
        // TODO: Exercise 06 - Decrement active connections
        // Use fetchSub(1, .monotonic) on active_connections.
        _ = self;
    }

    pub fn toJson(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        // TODO: Exercise 06 - Format metrics as a JSON string
        // Use an ArrayList(u8) and its writer to print:
        //   {"uptime_seconds":N,"total_requests":N,"active_connections":N,
        //    "status_2xx":N,"status_4xx":N,"status_5xx":N}
        // Calculate uptime as std.time.timestamp() - self.start_time.
        // Load each atomic value with .load(.monotonic).
        // End with a newline, then return toOwnedSlice.
        _ = self;
        _ = allocator;
        return error.OutOfMemory;
    }
};

// ============================================================================
// Exercise 06 Tests — Atomic Metrics Counters
// ============================================================================

test "06-01: init starts all counters at zero" {
    const m = Metrics.init();
    try std.testing.expectEqual(@as(u64, 0), m.total_requests.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.active_connections.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.status_2xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.status_4xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.status_5xx.load(.monotonic));
}

test "06-02: recordRequest increments total_requests" {
    var m = Metrics.init();
    m.recordRequest(200);
    m.recordRequest(404);
    m.recordRequest(500);
    try std.testing.expectEqual(@as(u64, 3), m.total_requests.load(.monotonic));
}

test "06-03: recordRequest classifies 2xx responses" {
    var m = Metrics.init();
    m.recordRequest(200);
    m.recordRequest(201);
    m.recordRequest(204);
    try std.testing.expectEqual(@as(u64, 3), m.status_2xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.status_4xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.status_5xx.load(.monotonic));
}

test "06-04: recordRequest classifies 4xx responses" {
    var m = Metrics.init();
    m.recordRequest(400);
    m.recordRequest(404);
    m.recordRequest(429);
    try std.testing.expectEqual(@as(u64, 3), m.status_4xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), m.status_2xx.load(.monotonic));
}

test "06-05: recordRequest classifies 5xx responses" {
    var m = Metrics.init();
    m.recordRequest(500);
    m.recordRequest(502);
    m.recordRequest(503);
    try std.testing.expectEqual(@as(u64, 3), m.status_5xx.load(.monotonic));
}

test "06-06: recordConnection and recordDisconnection" {
    var m = Metrics.init();
    m.recordConnection();
    m.recordConnection();
    m.recordConnection();
    try std.testing.expectEqual(@as(u64, 3), m.active_connections.load(.monotonic));

    m.recordDisconnection();
    try std.testing.expectEqual(@as(u64, 2), m.active_connections.load(.monotonic));
}

test "06-07: toJson returns valid JSON" {
    const allocator = std.testing.allocator;
    var m = Metrics.init();
    m.start_time = std.time.timestamp();
    m.recordRequest(200);
    m.recordRequest(404);

    const json = try m.toJson(allocator);
    defer allocator.free(json);

    // Should contain key fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"total_requests\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status_2xx\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status_4xx\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"uptime_seconds\":") != null);
}

test "06-08: toJson includes uptime" {
    const allocator = std.testing.allocator;
    var m = Metrics.init();
    // Set start_time to 10 seconds ago
    m.start_time = std.time.timestamp() - 10;

    const json = try m.toJson(allocator);
    defer allocator.free(json);

    // Uptime should be roughly 10 (give or take 1 second)
    try std.testing.expect(std.mem.indexOf(u8, json, "\"uptime_seconds\":") != null);
    // Should not be 0 since we set start_time 10s ago
    try std.testing.expect(std.mem.indexOf(u8, json, "\"uptime_seconds\":0") == null);
}

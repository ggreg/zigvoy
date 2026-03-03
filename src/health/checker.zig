const std = @import("std");
const Config = @import("../config/config.zig").Config;

pub const HealthChecker = struct {
    allocator: std.mem.Allocator,
    config: Config,
    statuses: std.StringHashMap(EndpointHealth),
    thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub const EndpointHealth = struct {
        healthy: bool = true,
        consecutive_failures: u32 = 0,
        consecutive_successes: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) HealthChecker {
        // TODO: Exercise 07 - Initialize the health checker
        // Return a HealthChecker with:
        //   - the given allocator and config
        //   - an empty StringHashMap(EndpointHealth)
        //   - thread = null, running = false
        _ = allocator;
        _ = config;
        return .{
            .allocator = undefined,
            .config = undefined,
            .statuses = std.StringHashMap(EndpointHealth).init(std.heap.page_allocator),
        };
    }

    pub fn start(self: *HealthChecker) void {
        self.running.store(true, .release);
        self.thread = std.Thread.spawn(.{}, checkLoop, .{self}) catch |err| {
            std.log.warn("health checker failed to start: {}", .{err});
            return;
        };
    }

    fn checkLoop(self: *HealthChecker) void {
        while (self.running.load(.acquire)) {
            for (self.config.upstreams) |upstream| {
                for (upstream.endpoints) |endpoint| {
                    self.checkEndpoint(endpoint);
                }
            }
            std.Thread.sleep(self.config.health_check.interval_ms * std.time.ns_per_ms);
        }
    }

    fn checkEndpoint(self: *HealthChecker, endpoint: Config.Endpoint) void {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}:{d}", .{ endpoint.host, endpoint.port }) catch return;

        const addr = std.net.Address.parseIp4(endpoint.host, endpoint.port) catch return;
        const stream = std.net.tcpConnectToAddress(addr) catch {
            self.recordResult(key, false);
            return;
        };
        defer stream.close();

        const req = "GET /healthz HTTP/1.1\r\nHost: healthcheck\r\nConnection: close\r\n\r\n";
        stream.writeAll(req) catch {
            self.recordResult(key, false);
            return;
        };

        var buf: [1024]u8 = undefined;
        const n = stream.read(&buf) catch {
            self.recordResult(key, false);
            return;
        };
        if (n < 12) {
            self.recordResult(key, false);
            return;
        }

        const status = std.fmt.parseInt(u16, buf[9..12], 10) catch {
            self.recordResult(key, false);
            return;
        };
        self.recordResult(key, status >= 200 and status < 300);
    }

    fn recordResult(self: *HealthChecker, key: []const u8, success: bool) void {
        // TODO: Exercise 07 - Record a health check result
        // Steps:
        //   1. Dupe the key string (allocator.dupe)
        //   2. Use self.statuses.getOrPut(owned_key)
        //   3. If the key already existed, free the duped copy
        //   4. If new entry, initialize with default EndpointHealth
        //   5. On success: reset consecutive_failures, increment consecutive_successes;
        //      if consecutive_successes >= healthy_threshold, mark as healthy
        //   6. On failure: reset consecutive_successes, increment consecutive_failures;
        //      if consecutive_failures >= unhealthy_threshold, mark as unhealthy
        _ = self;
        _ = key;
        _ = success;
    }

    pub fn isHealthy(self: *HealthChecker, host: []const u8, port: u16) bool {
        // TODO: Exercise 07 - Check if an endpoint is currently healthy
        // Steps:
        //   1. Format "host:port" key using std.fmt.bufPrint
        //   2. Look up in self.statuses with .get()
        //   3. If found, return health.healthy
        //   4. If not found, return true (assume healthy until proven otherwise)
        _ = self;
        _ = host;
        _ = port;
        return true;
    }

    pub fn deinit(self: *HealthChecker) void {
        // TODO: Exercise 07 - Clean up all resources
        // Steps:
        //   1. Signal the thread to stop: self.running.store(false, .release)
        //   2. If thread exists, join it
        //   3. Free all keys in self.statuses (iterate with keyIterator)
        //   4. Deinit the hash map
        _ = self;
    }
};

// ============================================================================
// Exercise 07 Tests — Health Check Worker
// ============================================================================

// Helper: build a Config literal for tests (avoids depending on Exercise 03's parse)
fn testConfig() Config {
    return .{
        .allocator = std.testing.allocator,
        .listen_port = 8080,
        .admin_port = 9901,
        .routes = &.{},
        .upstreams = &.{.{
            .name = "test",
            .endpoints = &.{.{
                .host = "127.0.0.1",
                .port = 9999,
            }},
        }},
        .health_check = .{},
        .rate_limit = .{},
        .circuit_breaker = .{},
        .retry = .{},
        ._raw_json = "",
    };
}

test "07-01: init creates checker with empty statuses" {
    const config = testConfig();
    var hc = HealthChecker.init(std.testing.allocator, config);
    defer hc.deinit();

    try std.testing.expectEqual(@as(u32, 0), hc.statuses.count());
    try std.testing.expect(hc.thread == null);
}

test "07-02: isHealthy returns true for unknown endpoints" {
    const config = testConfig();
    var hc = HealthChecker.init(std.testing.allocator, config);
    defer hc.deinit();

    // Never checked — should default to healthy
    try std.testing.expect(hc.isHealthy("10.0.0.1", 3000));
    try std.testing.expect(hc.isHealthy("unknown.host", 9999));
}

test "07-03: recordResult creates entry for new endpoint" {
    const config = testConfig();
    var hc = HealthChecker.init(std.testing.allocator, config);
    defer hc.deinit();

    hc.recordResult("127.0.0.1:3000", true);
    try std.testing.expectEqual(@as(u32, 1), hc.statuses.count());
}

test "07-04: recordResult tracks consecutive successes" {
    const config = testConfig();
    var hc = HealthChecker.init(std.testing.allocator, config);
    defer hc.deinit();

    hc.recordResult("127.0.0.1:3000", true);
    hc.recordResult("127.0.0.1:3000", true);
    hc.recordResult("127.0.0.1:3000", true);

    const health = hc.statuses.get("127.0.0.1:3000") orelse
        return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 3), health.consecutive_successes);
    try std.testing.expectEqual(@as(u32, 0), health.consecutive_failures);
    try std.testing.expect(health.healthy);
}

test "07-05: recordResult marks unhealthy after threshold failures" {
    var config = testConfig();
    config.health_check.unhealthy_threshold = 3;
    var hc = HealthChecker.init(std.testing.allocator, config);
    defer hc.deinit();

    hc.recordResult("127.0.0.1:3000", false);
    hc.recordResult("127.0.0.1:3000", false);
    // Not yet unhealthy (only 2 failures, threshold is 3)
    const h1 = hc.statuses.get("127.0.0.1:3000") orelse
        return error.TestExpectedEqual;
    try std.testing.expect(h1.healthy);

    hc.recordResult("127.0.0.1:3000", false);
    // Now unhealthy
    const h2 = hc.statuses.get("127.0.0.1:3000") orelse
        return error.TestExpectedEqual;
    try std.testing.expect(!h2.healthy);
}

test "07-06: success resets failure counter" {
    var config = testConfig();
    config.health_check.unhealthy_threshold = 3;
    var hc = HealthChecker.init(std.testing.allocator, config);
    defer hc.deinit();

    hc.recordResult("127.0.0.1:3000", false);
    hc.recordResult("127.0.0.1:3000", false);
    hc.recordResult("127.0.0.1:3000", true); // resets failures

    const health = hc.statuses.get("127.0.0.1:3000") orelse
        return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 0), health.consecutive_failures);
    try std.testing.expectEqual(@as(u32, 1), health.consecutive_successes);
}

test "07-07: deinit frees all allocated keys" {
    const config = testConfig();
    var hc = HealthChecker.init(std.testing.allocator, config);

    // Add some entries
    hc.recordResult("127.0.0.1:3000", true);
    hc.recordResult("127.0.0.1:3001", false);
    hc.recordResult("127.0.0.1:3002", true);

    // deinit must free all keys — testing.allocator will catch leaks
    hc.deinit();
}

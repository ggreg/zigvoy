const std = @import("std");

pub const Config = struct {
    allocator: std.mem.Allocator,
    listen_port: u16,
    admin_port: u16,
    routes: []const Route,
    upstreams: []const Upstream,
    health_check: HealthCheckConfig,
    rate_limit: RateLimitConfig,
    circuit_breaker: CircuitBreakerConfig,
    retry: RetryConfig,

    _raw_json: []const u8,

    pub const Route = struct {
        prefix: []const u8,
        upstream: []const u8,
    };

    pub const Upstream = struct {
        name: []const u8,
        endpoints: []const Endpoint,
        lb_policy: LbPolicy = .round_robin,
    };

    pub const Endpoint = struct {
        host: []const u8,
        port: u16,
    };

    pub const LbPolicy = enum {
        round_robin,
        random,
    };

    pub const HealthCheckConfig = struct {
        interval_ms: u64 = 5000,
        timeout_ms: u64 = 2000,
        unhealthy_threshold: u32 = 3,
        healthy_threshold: u32 = 1,
        path: []const u8 = "/healthz",
    };

    pub const RateLimitConfig = struct {
        enabled: bool = false,
        requests_per_second: u32 = 100,
        burst_size: u32 = 50,
    };

    pub const CircuitBreakerConfig = struct {
        enabled: bool = false,
        failure_threshold: u32 = 5,
        reset_timeout_ms: u64 = 30000,
        half_open_max_requests: u32 = 3,
    };

    pub const RetryConfig = struct {
        max_retries: u32 = 3,
        retry_on: []const u16 = &.{ 502, 503, 504 },
    };

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        // TODO: Exercise 03 - Load config from a JSON file
        // Steps:
        //   1. Open the file at `path` using std.fs.cwd().openFile
        //   2. defer file.close()
        //   3. Read entire file content with file.readToEndAlloc (max 1MB)
        //   4. Pass content to parse()
        _ = allocator;
        _ = path;
        return error.FileNotFound;
    }

    pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !Config {
        // TODO: Exercise 03 - Parse a JSON string into a Config struct
        // Steps:
        //   1. Use std.json.parseFromSlice(JsonConfig, ...) with .ignore_unknown_fields = true
        //   2. defer parsed.deinit()
        //   3. Build routes: ArrayList(Route) → iterate jc.routes → append → toOwnedSlice
        //   4. Build upstreams: for each JsonUpstream, build an Endpoint ArrayList,
        //      convert lb_policy string to LbPolicy enum, then toOwnedSlice
        //   5. Map all config fields into the returned Config struct
        //   6. Store json_str as _raw_json (ownership transfers to Config)
        _ = allocator;
        _ = json_str;
        return error.InvalidConfig;
    }

    pub fn deinit(self: Config) void {
        // TODO: Exercise 03 - Free all owned memory
        // Must free:
        //   1. Each upstream's endpoints slice
        //   2. The upstreams slice itself
        //   3. The routes slice
        //   4. The _raw_json string
        _ = self;
    }
};

const JsonConfig = struct {
    listen_port: u16 = 8080,
    admin_port: u16 = 9901,
    routes: []const JsonRoute = &.{},
    upstreams: []const JsonUpstream = &.{},
    health_check: JsonHealthCheck = .{},
    rate_limit: JsonRateLimit = .{},
    circuit_breaker: JsonCircuitBreaker = .{},
    retry: JsonRetry = .{},
};

const JsonRoute = struct {
    prefix: []const u8,
    upstream: []const u8,
};

const JsonUpstream = struct {
    name: []const u8,
    endpoints: []const JsonEndpoint,
    lb_policy: []const u8 = "round_robin",
};

const JsonEndpoint = struct {
    host: []const u8,
    port: u16,
};

const JsonHealthCheck = struct {
    interval_ms: u64 = 5000,
    timeout_ms: u64 = 2000,
    unhealthy_threshold: u32 = 3,
    healthy_threshold: u32 = 1,
    path: []const u8 = "/healthz",
};

const JsonRateLimit = struct {
    enabled: bool = false,
    requests_per_second: u32 = 100,
    burst_size: u32 = 50,
};

const JsonCircuitBreaker = struct {
    enabled: bool = false,
    failure_threshold: u32 = 5,
    reset_timeout_ms: u64 = 30000,
    half_open_max_requests: u32 = 3,
};

const JsonRetry = struct {
    max_retries: u32 = 3,
};

// ============================================================================
// Exercise 03 Tests — JSON Configuration
// ============================================================================

test "03-01: parse minimal config" {
    const json =
        \\{
        \\  "listen_port": 8080,
        \\  "routes": [{"prefix": "/", "upstream": "backend"}],
        \\  "upstreams": [{
        \\    "name": "backend",
        \\    "endpoints": [{"host": "127.0.0.1", "port": 3000}]
        \\  }]
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expectEqual(@as(u16, 8080), config.listen_port);
    try std.testing.expectEqual(@as(usize, 1), config.routes.len);
    try std.testing.expectEqual(@as(usize, 1), config.upstreams.len);
}

test "03-02: parse uses default values" {
    const json =
        \\{
        \\  "routes": [],
        \\  "upstreams": []
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expectEqual(@as(u16, 8080), config.listen_port);
    try std.testing.expectEqual(@as(u16, 9901), config.admin_port);
    try std.testing.expectEqual(@as(u64, 5000), config.health_check.interval_ms);
    try std.testing.expect(!config.rate_limit.enabled);
    try std.testing.expect(!config.circuit_breaker.enabled);
}

test "03-03: parse multiple routes" {
    const json =
        \\{
        \\  "routes": [
        \\    {"prefix": "/api/", "upstream": "backend"},
        \\    {"prefix": "/", "upstream": "frontend"}
        \\  ],
        \\  "upstreams": [
        \\    {"name": "backend", "endpoints": [{"host": "127.0.0.1", "port": 3000}]},
        \\    {"name": "frontend", "endpoints": [{"host": "127.0.0.1", "port": 5173}]}
        \\  ]
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 2), config.routes.len);
    try std.testing.expectEqualStrings("/api/", config.routes[0].prefix);
    try std.testing.expectEqualStrings("/", config.routes[1].prefix);
}

test "03-04: parse upstream with multiple endpoints" {
    const json =
        \\{
        \\  "routes": [{"prefix": "/", "upstream": "api"}],
        \\  "upstreams": [{
        \\    "name": "api",
        \\    "endpoints": [
        \\      {"host": "127.0.0.1", "port": 3000},
        \\      {"host": "127.0.0.1", "port": 3001},
        \\      {"host": "127.0.0.1", "port": 3002}
        \\    ]
        \\  }]
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 3), config.upstreams[0].endpoints.len);
    try std.testing.expectEqual(@as(u16, 3001), config.upstreams[0].endpoints[1].port);
}

test "03-05: parse lb_policy random" {
    const json =
        \\{
        \\  "routes": [],
        \\  "upstreams": [{
        \\    "name": "api",
        \\    "lb_policy": "random",
        \\    "endpoints": [{"host": "127.0.0.1", "port": 3000}]
        \\  }]
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expectEqual(Config.LbPolicy.random, config.upstreams[0].lb_policy);
}

test "03-06: parse rate limit config" {
    const json =
        \\{
        \\  "routes": [],
        \\  "upstreams": [],
        \\  "rate_limit": {
        \\    "enabled": true,
        \\    "requests_per_second": 50,
        \\    "burst_size": 25
        \\  }
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expect(config.rate_limit.enabled);
    try std.testing.expectEqual(@as(u32, 50), config.rate_limit.requests_per_second);
    try std.testing.expectEqual(@as(u32, 25), config.rate_limit.burst_size);
}

test "03-07: parse circuit breaker config" {
    const json =
        \\{
        \\  "routes": [],
        \\  "upstreams": [],
        \\  "circuit_breaker": {
        \\    "enabled": true,
        \\    "failure_threshold": 10,
        \\    "reset_timeout_ms": 60000,
        \\    "half_open_max_requests": 5
        \\  }
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    defer config.deinit();

    try std.testing.expect(config.circuit_breaker.enabled);
    try std.testing.expectEqual(@as(u32, 10), config.circuit_breaker.failure_threshold);
    try std.testing.expectEqual(@as(u64, 60000), config.circuit_breaker.reset_timeout_ms);
}

test "03-08: deinit frees all memory (no leaks)" {
    const json =
        \\{
        \\  "routes": [{"prefix": "/", "upstream": "svc"}],
        \\  "upstreams": [{
        \\    "name": "svc",
        \\    "endpoints": [{"host": "127.0.0.1", "port": 8000}]
        \\  }]
        \\}
    ;
    const allocator = std.testing.allocator;
    const owned = try allocator.dupe(u8, json);
    const config = try Config.parse(allocator, owned);
    // If deinit is wrong, testing.allocator will report a leak
    config.deinit();
}

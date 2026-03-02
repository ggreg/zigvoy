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
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        return try parse(allocator, content);
    }

    pub fn parse(allocator: std.mem.Allocator, json_str: []const u8) !Config {
        const parsed = try std.json.parseFromSlice(JsonConfig, allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const jc = parsed.value;

        var routes: std.ArrayList(Route) = .empty;
        defer routes.deinit(allocator);
        for (jc.routes) |jr| {
            try routes.append(allocator, .{
                .prefix = jr.prefix,
                .upstream = jr.upstream,
            });
        }

        var upstreams: std.ArrayList(Upstream) = .empty;
        defer upstreams.deinit(allocator);
        for (jc.upstreams) |ju| {
            var endpoints: std.ArrayList(Endpoint) = .empty;
            defer endpoints.deinit(allocator);
            for (ju.endpoints) |je| {
                try endpoints.append(allocator, .{
                    .host = je.host,
                    .port = je.port,
                });
            }
            try upstreams.append(allocator, .{
                .name = ju.name,
                .endpoints = try endpoints.toOwnedSlice(allocator),
                .lb_policy = if (std.mem.eql(u8, ju.lb_policy, "random")) .random else .round_robin,
            });
        }

        return .{
            .allocator = allocator,
            .listen_port = jc.listen_port,
            .admin_port = jc.admin_port,
            .routes = try routes.toOwnedSlice(allocator),
            .upstreams = try upstreams.toOwnedSlice(allocator),
            .health_check = .{
                .interval_ms = jc.health_check.interval_ms,
                .timeout_ms = jc.health_check.timeout_ms,
                .unhealthy_threshold = jc.health_check.unhealthy_threshold,
                .healthy_threshold = jc.health_check.healthy_threshold,
                .path = jc.health_check.path,
            },
            .rate_limit = .{
                .enabled = jc.rate_limit.enabled,
                .requests_per_second = jc.rate_limit.requests_per_second,
                .burst_size = jc.rate_limit.burst_size,
            },
            .circuit_breaker = .{
                .enabled = jc.circuit_breaker.enabled,
                .failure_threshold = jc.circuit_breaker.failure_threshold,
                .reset_timeout_ms = jc.circuit_breaker.reset_timeout_ms,
                .half_open_max_requests = jc.circuit_breaker.half_open_max_requests,
            },
            .retry = .{
                .max_retries = jc.retry.max_retries,
            },
            ._raw_json = json_str,
        };
    }

    pub fn deinit(self: Config) void {
        for (self.upstreams) |u| {
            self.allocator.free(u.endpoints);
        }
        self.allocator.free(self.upstreams);
        self.allocator.free(self.routes);
        self.allocator.free(self._raw_json);
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

test "parse minimal config" {
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
    try std.testing.expectEqualStrings("backend", config.upstreams[0].name);
}

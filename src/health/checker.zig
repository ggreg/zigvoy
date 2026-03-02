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
        return .{
            .allocator = allocator,
            .config = config,
            .statuses = std.StringHashMap(EndpointHealth).init(allocator),
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
        const owned_key = self.allocator.dupe(u8, key) catch return;
        const gop = self.statuses.getOrPut(owned_key) catch {
            self.allocator.free(owned_key);
            return;
        };
        if (gop.found_existing) {
            self.allocator.free(owned_key);
        }
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }

        const health = gop.value_ptr;
        if (success) {
            health.consecutive_failures = 0;
            health.consecutive_successes += 1;
            if (health.consecutive_successes >= self.config.health_check.healthy_threshold) {
                if (!health.healthy) {
                    std.log.info("endpoint {s} is now healthy", .{key});
                }
                health.healthy = true;
            }
        } else {
            health.consecutive_successes = 0;
            health.consecutive_failures += 1;
            if (health.consecutive_failures >= self.config.health_check.unhealthy_threshold) {
                if (health.healthy) {
                    std.log.warn("endpoint {s} is now unhealthy", .{key});
                }
                health.healthy = false;
            }
        }
    }

    pub fn isHealthy(self: *HealthChecker, host: []const u8, port: u16) bool {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}:{d}", .{ host, port }) catch return true;
        if (self.statuses.get(key)) |health| {
            return health.healthy;
        }
        return true;
    }

    pub fn deinit(self: *HealthChecker) void {
        self.running.store(false, .release);
        if (self.thread) |t| t.join();
        var it = self.statuses.keyIterator();
        while (it.next()) |k| {
            self.allocator.free(k.*);
        }
        self.statuses.deinit();
    }
};

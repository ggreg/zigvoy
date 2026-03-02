const std = @import("std");
const Config = @import("../config/config.zig").Config;
const HttpRequest = @import("../http/request.zig").HttpRequest;
const HttpResponse = @import("../http/response.zig").HttpResponse;
const Metrics = @import("../metrics/metrics.zig").Metrics;
const RateLimiter = @import("../ratelimit/limiter.zig").RateLimiter;
const CircuitBreaker = @import("../circuit/breaker.zig").CircuitBreaker;
const HealthChecker = @import("../health/checker.zig").HealthChecker;

pub const Server = struct {
    allocator: std.mem.Allocator,
    config: Config,
    listener: ?std.net.Server,
    admin_listener: ?std.net.Server,
    metrics: Metrics,
    rate_limiter: ?RateLimiter,
    circuit_breakers: std.StringHashMap(CircuitBreaker),
    health_checker: HealthChecker,
    rr_counters: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, config: Config) !Server {
        var circuit_breakers = std.StringHashMap(CircuitBreaker).init(allocator);
        if (config.circuit_breaker.enabled) {
            for (config.upstreams) |upstream| {
                try circuit_breakers.put(upstream.name, CircuitBreaker.init(
                    config.circuit_breaker.failure_threshold,
                    config.circuit_breaker.reset_timeout_ms,
                    config.circuit_breaker.half_open_max_requests,
                ));
            }
        }

        var rr_counters = std.StringHashMap(usize).init(allocator);
        for (config.upstreams) |upstream| {
            try rr_counters.put(upstream.name, 0);
        }

        return .{
            .allocator = allocator,
            .config = config,
            .listener = null,
            .admin_listener = null,
            .metrics = Metrics.init(),
            .rate_limiter = if (config.rate_limit.enabled)
                RateLimiter.init(config.rate_limit.requests_per_second, config.rate_limit.burst_size)
            else
                null,
            .circuit_breakers = circuit_breakers,
            .health_checker = HealthChecker.init(allocator, config),
            .rr_counters = rr_counters,
        };
    }

    pub fn run(self: *Server) !void {
        const admin_thread = try std.Thread.spawn(.{}, adminLoop, .{ self, self.config.admin_port });
        admin_thread.detach();

        self.health_checker.start();

        const addr = std.net.Address.parseIp4("0.0.0.0", self.config.listen_port) catch unreachable;
        self.listener = try addr.listen(.{
            .reuse_address = true,
        });
        std.log.info("listening on 0.0.0.0:{d}", .{self.config.listen_port});
        std.log.info("admin on 0.0.0.0:{d}", .{self.config.admin_port});

        while (true) {
            const conn = self.listener.?.accept() catch |err| {
                std.log.warn("accept error: {}", .{err});
                continue;
            };
            const thread = std.Thread.spawn(.{}, handleConnection, .{ self, conn }) catch |err| {
                std.log.warn("thread spawn error: {}", .{err});
                conn.stream.close();
                continue;
            };
            thread.detach();
        }
    }

    fn handleConnection(self: *Server, conn: std.net.Server.Connection) void {
        defer conn.stream.close();
        self.metrics.recordConnection();
        defer self.metrics.recordDisconnection();

        var buf: [8192]u8 = undefined;
        const n = conn.stream.read(&buf) catch |err| {
            std.log.warn("read error: {}", .{err});
            return;
        };
        if (n == 0) return;

        const request = HttpRequest.parse(self.allocator, buf[0..n]) catch {
            sendError(conn.stream, 400, "Bad Request");
            return;
        };
        defer request.deinit();

        // Rate limiting
        if (self.rate_limiter) |*rl| {
            if (!rl.allow()) {
                self.metrics.recordRequest(429);
                sendError(conn.stream, 429, "Too Many Requests");
                return;
            }
        }

        // Route matching
        const route = self.matchRoute(request.path) orelse {
            self.metrics.recordRequest(404);
            sendError(conn.stream, 404, "No matching route");
            return;
        };

        // Find upstream
        const upstream = self.findUpstream(route.upstream) orelse {
            self.metrics.recordRequest(502);
            sendError(conn.stream, 502, "Upstream not found");
            return;
        };

        // Circuit breaker check
        if (self.circuit_breakers.getPtr(upstream.name)) |cb| {
            if (!cb.allowRequest()) {
                self.metrics.recordRequest(503);
                sendError(conn.stream, 503, "Circuit breaker open");
                return;
            }
        }

        // Proxy with retries
        var last_status: u16 = 502;
        for (0..self.config.retry.max_retries + 1) |attempt| {
            const endpoint = self.pickEndpoint(upstream) orelse {
                sendError(conn.stream, 502, "No healthy endpoints");
                return;
            };

            if (self.proxyToBackend(conn.stream, &request, endpoint)) |status| {
                last_status = status;
                self.metrics.recordRequest(status);

                if (self.circuit_breakers.getPtr(upstream.name)) |cb| {
                    if (status >= 500) cb.recordFailure() else cb.recordSuccess();
                }

                if (!shouldRetry(self.config, status)) return;
            } else |_| {
                if (self.circuit_breakers.getPtr(upstream.name)) |cb| {
                    cb.recordFailure();
                }
            }

            if (attempt < self.config.retry.max_retries) {
                std.log.warn("retry {d}/{d} for {s}", .{ attempt + 1, self.config.retry.max_retries, request.path });
            }
        }

        self.metrics.recordRequest(last_status);
        sendError(conn.stream, last_status, "Upstream failed after retries");
    }

    fn proxyToBackend(self: *Server, client_stream: std.net.Stream, request: *const HttpRequest, endpoint: Config.Endpoint) !u16 {
        _ = self;
        const addr = std.net.Address.parseIp4(endpoint.host, endpoint.port) catch
            return error.InvalidAddress;
        const upstream_stream = std.net.tcpConnectToAddress(addr) catch
            return error.ConnectionFailed;
        defer upstream_stream.close();

        const serialized = request.serialize(std.heap.page_allocator) catch
            return error.SerializeFailed;
        defer std.heap.page_allocator.free(serialized);

        upstream_stream.writeAll(serialized) catch return error.WriteFailed;

        var resp_buf: [65536]u8 = undefined;
        var total: usize = 0;
        while (total < resp_buf.len) {
            const bytes = upstream_stream.read(resp_buf[total..]) catch break;
            if (bytes == 0) break;
            total += bytes;
        }

        if (total == 0) return error.EmptyResponse;

        const status = extractStatus(resp_buf[0..total]);
        client_stream.writeAll(resp_buf[0..total]) catch return error.ClientWriteFailed;

        return status;
    }

    fn extractStatus(buf: []const u8) u16 {
        if (buf.len < 12) return 502;
        const status_str = buf[9..12];
        return std.fmt.parseInt(u16, status_str, 10) catch 502;
    }

    fn matchRoute(self: *Server, path: []const u8) ?Config.Route {
        var best: ?Config.Route = null;
        var best_len: usize = 0;
        for (self.config.routes) |route| {
            if (std.mem.startsWith(u8, path, route.prefix)) {
                if (route.prefix.len > best_len) {
                    best = route;
                    best_len = route.prefix.len;
                }
            }
        }
        return best;
    }

    fn findUpstream(self: *Server, name: []const u8) ?Config.Upstream {
        for (self.config.upstreams) |u| {
            if (std.mem.eql(u8, u.name, name)) return u;
        }
        return null;
    }

    fn pickEndpoint(self: *Server, upstream: Config.Upstream) ?Config.Endpoint {
        if (upstream.endpoints.len == 0) return null;

        switch (upstream.lb_policy) {
            .round_robin => {
                const counter = self.rr_counters.getPtr(upstream.name) orelse return upstream.endpoints[0];
                const idx = counter.* % upstream.endpoints.len;
                counter.* +%= 1;
                return upstream.endpoints[idx];
            },
            .random => {
                var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
                const idx = prng.random().uintLessThan(usize, upstream.endpoints.len);
                return upstream.endpoints[idx];
            },
        }
    }

    fn shouldRetry(config: Config, status: u16) bool {
        for (config.retry.retry_on) |s| {
            if (s == status) return true;
        }
        return false;
    }

    fn sendError(stream: std.net.Stream, status: u16, message: []const u8) void {
        var buf: [512]u8 = undefined;
        const body = std.fmt.bufPrint(&buf, "{{\"error\":\"{s}\"}}\n", .{message}) catch return;

        var resp_buf: [1024]u8 = undefined;
        const resp = std.fmt.bufPrint(&resp_buf, "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{
            status,
            HttpResponse.reasonPhrase(status),
            body.len,
            body,
        }) catch return;

        stream.writeAll(resp) catch {};
    }

    fn adminLoop(self: *Server, port: u16) void {
        const addr = std.net.Address.parseIp4("0.0.0.0", port) catch return;
        self.admin_listener = addr.listen(.{ .reuse_address = true }) catch return;

        while (true) {
            const conn = self.admin_listener.?.accept() catch continue;
            defer conn.stream.close();

            var buf: [4096]u8 = undefined;
            const n = conn.stream.read(&buf) catch continue;
            if (n == 0) continue;

            const request = HttpRequest.parse(self.allocator, buf[0..n]) catch continue;
            defer request.deinit();

            if (std.mem.eql(u8, request.path, "/metrics")) {
                const body = self.metrics.toJson(self.allocator) catch continue;
                defer self.allocator.free(body);

                var resp_buf: [4096]u8 = undefined;
                const resp = std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}", .{
                    body.len, body,
                }) catch continue;
                conn.stream.writeAll(resp) catch {};
            } else if (std.mem.eql(u8, request.path, "/healthz")) {
                conn.stream.writeAll("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") catch {};
            } else {
                sendError(conn.stream, 404, "Not found");
            }
        }
    }

    pub fn deinit(self: *Server) void {
        self.circuit_breakers.deinit();
        self.rr_counters.deinit();
        self.health_checker.deinit();
        if (self.listener) |*l| l.deinit();
        if (self.admin_listener) |*l| l.deinit();
    }
};

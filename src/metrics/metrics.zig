const std = @import("std");

pub const Metrics = struct {
    total_requests: std.atomic.Value(u64),
    active_connections: std.atomic.Value(u64),
    status_2xx: std.atomic.Value(u64),
    status_4xx: std.atomic.Value(u64),
    status_5xx: std.atomic.Value(u64),
    start_time: i64,

    pub fn init() Metrics {
        return .{
            .total_requests = std.atomic.Value(u64).init(0),
            .active_connections = std.atomic.Value(u64).init(0),
            .status_2xx = std.atomic.Value(u64).init(0),
            .status_4xx = std.atomic.Value(u64).init(0),
            .status_5xx = std.atomic.Value(u64).init(0),
            .start_time = std.time.timestamp(),
        };
    }

    pub fn recordRequest(self: *Metrics, status: u16) void {
        _ = self.total_requests.fetchAdd(1, .monotonic);
        if (status >= 200 and status < 300) {
            _ = self.status_2xx.fetchAdd(1, .monotonic);
        } else if (status >= 400 and status < 500) {
            _ = self.status_4xx.fetchAdd(1, .monotonic);
        } else if (status >= 500) {
            _ = self.status_5xx.fetchAdd(1, .monotonic);
        }
    }

    pub fn recordConnection(self: *Metrics) void {
        _ = self.active_connections.fetchAdd(1, .monotonic);
    }

    pub fn recordDisconnection(self: *Metrics) void {
        _ = self.active_connections.fetchSub(1, .monotonic);
    }

    pub fn toJson(self: *Metrics, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        const writer = buf.writer(allocator);

        const uptime = std.time.timestamp() - self.start_time;

        try writer.print(
            \\{{"uptime_seconds":{d},"total_requests":{d},"active_connections":{d},"status_2xx":{d},"status_4xx":{d},"status_5xx":{d}}}
        , .{
            uptime,
            self.total_requests.load(.monotonic),
            self.active_connections.load(.monotonic),
            self.status_2xx.load(.monotonic),
            self.status_4xx.load(.monotonic),
            self.status_5xx.load(.monotonic),
        });
        try writer.writeByte('\n');

        return buf.toOwnedSlice(allocator);
    }
};

test "metrics counting" {
    var m = Metrics.init();

    m.recordRequest(200);
    m.recordRequest(200);
    m.recordRequest(404);
    m.recordRequest(503);

    try std.testing.expectEqual(@as(u64, 4), m.total_requests.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 2), m.status_2xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), m.status_4xx.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), m.status_5xx.load(.monotonic));
}

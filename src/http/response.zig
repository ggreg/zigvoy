const std = @import("std");

pub const HttpResponse = struct {
    status: u16,
    reason: []const u8,
    headers: []const Header,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, status: u16, body: []const u8) !HttpResponse {
        var headers: std.ArrayList(Header) = .empty;
        var content_len_buf: [20]u8 = undefined;
        const content_len = std.fmt.bufPrint(&content_len_buf, "{d}", .{body.len}) catch unreachable;
        try headers.append(allocator, .{ .name = "Content-Length", .value = try allocator.dupe(u8, content_len) });
        try headers.append(allocator, .{ .name = "Connection", .value = "close" });

        return .{
            .status = status,
            .reason = reasonPhrase(status),
            .headers = try headers.toOwnedSlice(allocator),
            .body = body,
            .allocator = allocator,
        };
    }

    pub fn parse(allocator: std.mem.Allocator, buf: []const u8) !HttpResponse {
        var headers: std.ArrayList(Header) = .empty;
        defer headers.deinit(allocator);

        const status_end = std.mem.indexOf(u8, buf, "\r\n") orelse return error.MalformedResponse;
        const status_line = buf[0..status_end];

        var parts = std.mem.splitScalar(u8, status_line, ' ');
        _ = parts.next() orelse return error.MalformedResponse;
        const status_str = parts.next() orelse return error.MalformedResponse;
        const reason = parts.rest();

        const status = std.fmt.parseInt(u16, status_str, 10) catch return error.MalformedResponse;

        var pos = status_end + 2;
        while (pos < buf.len) {
            const line_end = std.mem.indexOf(u8, buf[pos..], "\r\n") orelse break;
            const line = buf[pos .. pos + line_end];
            if (line.len == 0) {
                pos += 2;
                break;
            }

            const colon = std.mem.indexOf(u8, line, ":") orelse return error.MalformedHeader;
            try headers.append(allocator, .{
                .name = line[0..colon],
                .value = std.mem.trim(u8, line[colon + 1 ..], " "),
            });
            pos += line_end + 2;
        }

        const body = if (pos < buf.len) buf[pos..] else "";

        return .{
            .status = status,
            .reason = reason,
            .headers = try headers.toOwnedSlice(allocator),
            .body = body,
            .allocator = allocator,
        };
    }

    pub fn serialize(self: *const HttpResponse, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        const writer = out.writer(allocator);

        try writer.print("HTTP/1.1 {d} {s}\r\n", .{ self.status, self.reason });
        for (self.headers) |h| {
            try writer.print("{s}: {s}\r\n", .{ h.name, h.value });
        }
        try writer.writeAll("\r\n");
        if (self.body.len > 0) {
            try writer.writeAll(self.body);
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn deinit(self: *const HttpResponse) void {
        for (self.headers) |h| {
            if (std.mem.eql(u8, h.name, "Content-Length")) {
                self.allocator.free(h.value);
            }
        }
        self.allocator.free(self.headers);
    }

    pub fn reasonPhrase(status: u16) []const u8 {
        return switch (status) {
            200 => "OK",
            201 => "Created",
            204 => "No Content",
            301 => "Moved Permanently",
            302 => "Found",
            304 => "Not Modified",
            400 => "Bad Request",
            401 => "Unauthorized",
            403 => "Forbidden",
            404 => "Not Found",
            429 => "Too Many Requests",
            500 => "Internal Server Error",
            502 => "Bad Gateway",
            503 => "Service Unavailable",
            504 => "Gateway Timeout",
            else => "Unknown",
        };
    }
};

test "create and serialize response" {
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.init(allocator, 200, "hello");
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    const serialized = try resp.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expect(std.mem.startsWith(u8, serialized, "HTTP/1.1 200 OK\r\n"));
}

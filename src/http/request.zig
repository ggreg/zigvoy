const std = @import("std");

pub const HttpRequest = struct {
    method: Method,
    path: []const u8,
    version: []const u8,
    headers: []const Header,
    body: []const u8,
    _buf: []const u8,
    allocator: std.mem.Allocator,

    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };

    pub const Method = enum {
        GET,
        POST,
        PUT,
        DELETE,
        PATCH,
        HEAD,
        OPTIONS,
        CONNECT,

        pub fn fromString(s: []const u8) ?Method {
            const map = std.StaticStringMap(Method).initComptime(.{
                .{ "GET", .GET },
                .{ "POST", .POST },
                .{ "PUT", .PUT },
                .{ "DELETE", .DELETE },
                .{ "PATCH", .PATCH },
                .{ "HEAD", .HEAD },
                .{ "OPTIONS", .OPTIONS },
                .{ "CONNECT", .CONNECT },
            });
            return map.get(s);
        }

        pub fn toString(self: Method) []const u8 {
            return @tagName(self);
        }
    };

    pub fn parse(allocator: std.mem.Allocator, buf: []const u8) !HttpRequest {
        var headers: std.ArrayList(Header) = .empty;
        defer headers.deinit(allocator);

        const req_line_end = std.mem.indexOf(u8, buf, "\r\n") orelse return error.MalformedRequest;
        const request_line = buf[0..req_line_end];

        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method_str = parts.next() orelse return error.MalformedRequest;
        const path = parts.next() orelse return error.MalformedRequest;
        const version = parts.next() orelse return error.MalformedRequest;

        const method = Method.fromString(method_str) orelse return error.UnsupportedMethod;

        var pos = req_line_end + 2;
        while (pos < buf.len) {
            const line_end = std.mem.indexOf(u8, buf[pos..], "\r\n") orelse break;
            const line = buf[pos .. pos + line_end];
            if (line.len == 0) {
                pos += 2;
                break;
            }

            const colon = std.mem.indexOf(u8, line, ":") orelse return error.MalformedHeader;
            const name = line[0..colon];
            const value = std.mem.trim(u8, line[colon + 1 ..], " ");
            try headers.append(allocator, .{ .name = name, .value = value });

            pos += line_end + 2;
        }

        const body = if (pos < buf.len) buf[pos..] else "";

        return .{
            .method = method,
            .path = path,
            .version = version,
            .headers = try headers.toOwnedSlice(allocator),
            .body = body,
            ._buf = buf,
            .allocator = allocator,
        };
    }

    pub fn getHeader(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        for (self.headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }

    pub fn serialize(self: *const HttpRequest, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        const writer = out.writer(allocator);

        try writer.print("{s} {s} {s}\r\n", .{
            self.method.toString(),
            self.path,
            self.version,
        });

        for (self.headers) |h| {
            try writer.print("{s}: {s}\r\n", .{ h.name, h.value });
        }
        try writer.writeAll("\r\n");

        if (self.body.len > 0) {
            try writer.writeAll(self.body);
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn deinit(self: *const HttpRequest) void {
        self.allocator.free(self.headers);
    }
};

test "parse GET request" {
    const raw = "GET /api/users HTTP/1.1\r\nHost: localhost\r\nAccept: */*\r\n\r\n";
    const allocator = std.testing.allocator;
    const req = try HttpRequest.parse(allocator, raw);
    defer req.deinit();

    try std.testing.expectEqual(HttpRequest.Method.GET, req.method);
    try std.testing.expectEqualStrings("/api/users", req.path);
    try std.testing.expectEqualStrings("localhost", req.getHeader("Host").?);
}

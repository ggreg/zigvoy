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
            // TODO: Exercise 01 - Convert a method string to a Method enum
            // Use std.StaticStringMap(Method).initComptime() with pairs like
            //   .{ "GET", .GET }, .{ "POST", .POST }, ...
            // Then call map.get(s) to look up the string.
            _ = s;
            return null;
        }

        pub fn toString(self: Method) []const u8 {
            return @tagName(self);
        }
    };

    pub fn parse(allocator: std.mem.Allocator, buf: []const u8) !HttpRequest {
        // TODO: Exercise 01 - Parse an HTTP request from raw bytes
        // Steps:
        //   1. Find the first "\r\n" using std.mem.indexOf to get the request line
        //   2. Split the request line on ' ' using std.mem.splitScalar
        //      to extract method_str, path, and version
        //   3. Convert method_str to a Method using Method.fromString
        //      (return error.UnsupportedMethod if null)
        //   4. Walk through subsequent lines (each ending with "\r\n"),
        //      parsing "Name: Value" headers. An empty line signals end of headers.
        //   5. Everything after the "\r\n\r\n" separator is the body
        //   6. Return an HttpRequest struct (headers via ArrayList → toOwnedSlice)
        _ = allocator;
        _ = buf;
        return error.MalformedRequest;
    }

    pub fn getHeader(self: *const HttpRequest, name: []const u8) ?[]const u8 {
        // TODO: Exercise 01 - Case-insensitive header lookup
        // Loop through self.headers and use std.ascii.eqlIgnoreCase
        // to compare header names. Return the value if found, null otherwise.
        _ = self;
        _ = name;
        return null;
    }

    pub fn serialize(self: *const HttpRequest, allocator: std.mem.Allocator) ![]u8 {
        // TODO: Exercise 01 - Serialize the request back to HTTP bytes
        // Use an ArrayList(u8) with a writer to build:
        //   "{METHOD} {path} {version}\r\n"
        //   "{header-name}: {header-value}\r\n" for each header
        //   "\r\n"
        //   "{body}" (if non-empty)
        // Return the result via toOwnedSlice.
        _ = allocator;
        _ = self;
        return error.MalformedRequest;
    }

    pub fn deinit(self: *const HttpRequest) void {
        // TODO: Exercise 01 - Free allocated memory
        // The headers slice was allocated with toOwnedSlice — free it.
        _ = self;
    }
};

// ============================================================================
// Exercise 01 Tests — HTTP Request Parser
// ============================================================================

test "01-01: fromString converts known methods" {
    const fromString = HttpRequest.Method.fromString;
    try std.testing.expectEqual(@as(?HttpRequest.Method, .GET), fromString("GET"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .POST), fromString("POST"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .PUT), fromString("PUT"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .DELETE), fromString("DELETE"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .PATCH), fromString("PATCH"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .HEAD), fromString("HEAD"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .OPTIONS), fromString("OPTIONS"));
    try std.testing.expectEqual(@as(?HttpRequest.Method, .CONNECT), fromString("CONNECT"));
}

test "01-02: fromString returns null for unknown methods" {
    try std.testing.expect(HttpRequest.Method.fromString("FOOBAR") == null);
    try std.testing.expect(HttpRequest.Method.fromString("get") == null);
    try std.testing.expect(HttpRequest.Method.fromString("") == null);
}

test "01-03: parse simple GET request" {
    const raw = "GET /api/users HTTP/1.1\r\nHost: localhost\r\nAccept: */*\r\n\r\n";
    const allocator = std.testing.allocator;
    const req = try HttpRequest.parse(allocator, raw);
    defer req.deinit();

    try std.testing.expectEqual(HttpRequest.Method.GET, req.method);
    try std.testing.expectEqualStrings("/api/users", req.path);
    try std.testing.expectEqualStrings("HTTP/1.1", req.version);
    try std.testing.expectEqual(@as(usize, 2), req.headers.len);
}

test "01-04: parse POST request with body" {
    const raw = "POST /submit HTTP/1.1\r\nContent-Length: 13\r\n\r\nHello, World!";
    const allocator = std.testing.allocator;
    const req = try HttpRequest.parse(allocator, raw);
    defer req.deinit();

    try std.testing.expectEqual(HttpRequest.Method.POST, req.method);
    try std.testing.expectEqualStrings("/submit", req.path);
    try std.testing.expectEqualStrings("Hello, World!", req.body);
}

test "01-05: parse returns error on malformed input" {
    const allocator = std.testing.allocator;
    // No \r\n at all
    try std.testing.expectError(error.MalformedRequest, HttpRequest.parse(allocator, "garbage"));
}

test "01-06: parse returns error on unsupported method" {
    const allocator = std.testing.allocator;
    const raw = "FOOBAR /path HTTP/1.1\r\n\r\n";
    try std.testing.expectError(error.UnsupportedMethod, HttpRequest.parse(allocator, raw));
}

test "01-07: getHeader is case-insensitive" {
    const raw = "GET / HTTP/1.1\r\nContent-Type: text/html\r\nX-Custom: hello\r\n\r\n";
    const allocator = std.testing.allocator;
    const req = try HttpRequest.parse(allocator, raw);
    defer req.deinit();

    try std.testing.expectEqualStrings("text/html", req.getHeader("content-type") orelse
        return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("text/html", req.getHeader("CONTENT-TYPE") orelse
        return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("hello", req.getHeader("x-custom") orelse
        return error.TestExpectedEqual);
    try std.testing.expect(req.getHeader("nonexistent") == null);
}

test "01-08: serialize round-trips a GET request" {
    const raw = "GET /test HTTP/1.1\r\nHost: example.com\r\n\r\n";
    const allocator = std.testing.allocator;
    const req = try HttpRequest.parse(allocator, raw);
    defer req.deinit();

    const serialized = try req.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expectEqualStrings(raw, serialized);
}

test "01-09: serialize round-trips a POST request with body" {
    const raw = "POST /data HTTP/1.1\r\nContent-Length: 4\r\n\r\ntest";
    const allocator = std.testing.allocator;
    const req = try HttpRequest.parse(allocator, raw);
    defer req.deinit();

    const serialized = try req.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expectEqualStrings(raw, serialized);
}

test "01-10: toString returns enum tag name" {
    try std.testing.expectEqualStrings("GET", HttpRequest.Method.GET.toString());
    try std.testing.expectEqualStrings("POST", HttpRequest.Method.POST.toString());
    try std.testing.expectEqualStrings("DELETE", HttpRequest.Method.DELETE.toString());
}

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
        // TODO: Exercise 02 - Create a new HTTP response
        // Steps:
        //   1. Create an ArrayList(Header)
        //   2. Format body.len into a stack buffer using std.fmt.bufPrint
        //   3. Append a "Content-Length" header (dupe the formatted value with allocator.dupe)
        //   4. Append a "Connection: close" header
        //   5. Convert headers to owned slice and return the HttpResponse struct
        //      Use reasonPhrase(status) for the reason field.
        _ = allocator;
        _ = status;
        _ = body;
        return error.MalformedResponse;
    }

    pub fn parse(allocator: std.mem.Allocator, buf: []const u8) !HttpResponse {
        // TODO: Exercise 02 - Parse an HTTP response from raw bytes
        // Steps:
        //   1. Find the status line (up to first "\r\n")
        //   2. Split on spaces: skip version, parse status code (std.fmt.parseInt),
        //      and use .rest() for reason phrase
        //   3. Parse headers like in request.zig (lines until empty line)
        //   4. Everything after "\r\n\r\n" is the body
        //   5. Return HttpResponse with headers via toOwnedSlice
        _ = allocator;
        _ = buf;
        return error.MalformedResponse;
    }

    pub fn serialize(self: *const HttpResponse, allocator: std.mem.Allocator) ![]u8 {
        // TODO: Exercise 02 - Serialize the response to HTTP bytes
        // Build: "HTTP/1.1 {status} {reason}\r\n"
        //        "{name}: {value}\r\n" for each header
        //        "\r\n"
        //        "{body}" (if non-empty)
        // Use ArrayList(u8) writer and return toOwnedSlice.
        _ = allocator;
        _ = self;
        return error.MalformedResponse;
    }

    pub fn deinit(self: *const HttpResponse) void {
        // TODO: Exercise 02 - Free allocated memory
        // The Content-Length header value was duped — find it and free it.
        // Then free the headers slice itself.
        _ = self;
    }

    pub fn reasonPhrase(status: u16) []const u8 {
        // TODO: Exercise 02 - Map status codes to reason phrases
        // Use a switch expression to return the correct phrase:
        //   200 → "OK", 201 → "Created", 204 → "No Content",
        //   301 → "Moved Permanently", 302 → "Found", 304 → "Not Modified",
        //   400 → "Bad Request", 401 → "Unauthorized", 403 → "Forbidden",
        //   404 → "Not Found", 429 → "Too Many Requests",
        //   500 → "Internal Server Error", 502 → "Bad Gateway",
        //   503 → "Service Unavailable", 504 → "Gateway Timeout",
        //   else → "Unknown"
        _ = status;
        return "Unknown";
    }
};

// ============================================================================
// Exercise 02 Tests — HTTP Response Builder
// ============================================================================

test "02-01: reasonPhrase returns correct phrases" {
    try std.testing.expectEqualStrings("OK", HttpResponse.reasonPhrase(200));
    try std.testing.expectEqualStrings("Created", HttpResponse.reasonPhrase(201));
    try std.testing.expectEqualStrings("No Content", HttpResponse.reasonPhrase(204));
    try std.testing.expectEqualStrings("Bad Request", HttpResponse.reasonPhrase(400));
    try std.testing.expectEqualStrings("Not Found", HttpResponse.reasonPhrase(404));
    try std.testing.expectEqualStrings("Internal Server Error", HttpResponse.reasonPhrase(500));
    try std.testing.expectEqualStrings("Bad Gateway", HttpResponse.reasonPhrase(502));
    try std.testing.expectEqualStrings("Unknown", HttpResponse.reasonPhrase(999));
}

test "02-02: init creates response with correct status" {
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.init(allocator, 200, "hello");
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("OK", resp.reason);
    try std.testing.expectEqualStrings("hello", resp.body);
}

test "02-03: init sets Content-Length header" {
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.init(allocator, 200, "hello");
    defer resp.deinit();

    var found_cl = false;
    for (resp.headers) |h| {
        if (std.mem.eql(u8, h.name, "Content-Length")) {
            try std.testing.expectEqualStrings("5", h.value);
            found_cl = true;
        }
    }
    try std.testing.expect(found_cl);
}

test "02-04: init sets Connection close header" {
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.init(allocator, 404, "not found");
    defer resp.deinit();

    var found_conn = false;
    for (resp.headers) |h| {
        if (std.mem.eql(u8, h.name, "Connection")) {
            try std.testing.expectEqualStrings("close", h.value);
            found_conn = true;
        }
    }
    try std.testing.expect(found_conn);
}

test "02-05: serialize produces valid HTTP response" {
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.init(allocator, 200, "hello");
    defer resp.deinit();

    const serialized = try resp.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expect(std.mem.startsWith(u8, serialized, "HTTP/1.1 200 OK\r\n"));
    try std.testing.expect(std.mem.endsWith(u8, serialized, "hello"));
}

test "02-06: parse parses a valid response" {
    const raw = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\noops";
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.parse(allocator, raw);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 404), resp.status);
    try std.testing.expectEqualStrings("Not Found", resp.reason);
    try std.testing.expectEqualStrings("oops", resp.body);
    try std.testing.expectEqual(@as(usize, 1), resp.headers.len);
}

test "02-07: parse handles response with no body" {
    const raw = "HTTP/1.1 204 No Content\r\n\r\n";
    const allocator = std.testing.allocator;
    const resp = try HttpResponse.parse(allocator, raw);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 204), resp.status);
    try std.testing.expectEqual(@as(usize, 0), resp.body.len);
}

test "02-08: parse returns error on malformed input" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MalformedResponse, HttpResponse.parse(allocator, "garbage"));
}

test "02-09: serialize then parse round-trips" {
    const allocator = std.testing.allocator;
    const original = try HttpResponse.init(allocator, 200, "round trip");
    defer original.deinit();

    const bytes = try original.serialize(allocator);
    defer allocator.free(bytes);

    const parsed = try HttpResponse.parse(allocator, bytes);
    defer parsed.deinit();

    try std.testing.expectEqual(original.status, parsed.status);
    try std.testing.expectEqualStrings("round trip", parsed.body);
}

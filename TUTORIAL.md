# Zigvoy — Learn Zig by Building an L7 Reverse Proxy

Welcome! In this tutorial you'll implement a fully functional HTTP reverse proxy in Zig, one piece at a time. Each exercise has pre-written failing tests — your job is to make them pass.

## How It Works

1. Pick an exercise (start with 01)
2. Open the source file and find the `// TODO` stubs
3. Implement the functions
4. Run the tests: `zig build test-01`
5. All green? Move to the next exercise!

When all 7 exercises pass, the full reverse proxy works — you can run it with `zig build run`.

## Getting Help

Stuck? You can peek at the solutions:

```bash
# See the full solution for a file
git diff master..solutions -- src/http/request.zig

# See all solutions
git diff master..solutions
```

---

## Exercise 01: HTTP Request Parser

**File:** `src/http/request.zig`
**Run:** `zig build test-01`

### What You'll Learn
- **Enums** and the `Method` type
- **Comptime** data structures with `std.StaticStringMap`
- **Slices** and slice operations
- **Error unions** (`!HttpRequest`)
- `std.mem.splitScalar`, `std.mem.indexOf`, `std.mem.trim`

### Your Task
Implement 5 functions:
1. `Method.fromString` — Convert a string like `"GET"` to a `Method` enum value
2. `parse` — Parse raw HTTP bytes into an `HttpRequest` struct
3. `getHeader` — Case-insensitive header lookup
4. `serialize` — Convert the request back to HTTP bytes
5. `deinit` — Free the allocated headers slice

### Key Concepts

<details>
<summary>StaticStringMap</summary>

`std.StaticStringMap` creates a compile-time optimized lookup table:
```zig
const map = std.StaticStringMap(Method).initComptime(.{
    .{ "GET", .GET },
    .{ "POST", .POST },
});
const method = map.get("GET"); // returns ?Method
```
</details>

<details>
<summary>Splitting strings</summary>

```zig
// Split "GET /path HTTP/1.1" on spaces
var parts = std.mem.splitScalar(u8, line, ' ');
const first = parts.next() orelse return error.Bad;
const second = parts.next() orelse return error.Bad;
```
</details>

<details>
<summary>Finding substrings</summary>

```zig
// Find "\r\n" in a buffer
const pos = std.mem.indexOf(u8, buf, "\r\n") orelse return error.NotFound;
const line = buf[0..pos]; // everything before \r\n
```
</details>

<details>
<summary>ArrayList → owned slice</summary>

```zig
var list: std.ArrayList(Header) = .empty;
defer list.deinit(allocator);
try list.append(allocator, .{ .name = "Host", .value = "localhost" });
const headers = try list.toOwnedSlice(allocator);
// Caller must free: allocator.free(headers)
```
</details>

---

## Exercise 02: HTTP Response Builder

**File:** `src/http/response.zig`
**Run:** `zig build test-02`

### What You'll Learn
- **Struct methods** (`self` parameter)
- **ArrayList writer** pattern for building strings
- **`std.fmt.bufPrint`** for stack-buffer formatting
- **Switch expressions** that return values
- **`allocator.dupe`** for copying slices

### Your Task
Implement 4 functions:
1. `init` — Create a response with auto-generated Content-Length header
2. `parse` — Parse an HTTP response from raw bytes
3. `serialize` — Convert response to HTTP bytes
4. `deinit` — Free the duped Content-Length value and headers slice
5. `reasonPhrase` — Map status codes to reason strings using a switch

### Key Concepts

<details>
<summary>bufPrint for stack formatting</summary>

```zig
var buf: [20]u8 = undefined;
const str = std.fmt.bufPrint(&buf, "{d}", .{42}) catch unreachable;
// str is "42", lives on the stack (buf)
```
</details>

<details>
<summary>allocator.dupe</summary>

```zig
// Copy a slice so it outlives the source
const owned = try allocator.dupe(u8, temporary_string);
// Later: allocator.free(owned)
```
</details>

<details>
<summary>Switch expressions</summary>

```zig
const phrase = switch (status) {
    200 => "OK",
    404 => "Not Found",
    else => "Unknown",
};
```
</details>

---

## Exercise 03: JSON Configuration

**File:** `src/config/config.zig`
**Run:** `zig build test-03`

### What You'll Learn
- **`std.json`** for parsing JSON
- **Nested structs** with default field values
- **`ArrayList` → `toOwnedSlice`** pattern
- **`defer` chains** for cleanup
- **Memory ownership** — who frees what

### Your Task
Implement 3 functions:
1. `loadFromFile` — Read a JSON file and pass it to `parse()`
2. `parse` — Parse a JSON string into a fully populated `Config`
3. `deinit` — Free all owned slices (routes, upstreams, endpoints, raw JSON)

### Key Concepts

<details>
<summary>std.json.parseFromSlice</summary>

```zig
const parsed = try std.json.parseFromSlice(MyStruct, allocator, json_str, .{
    .ignore_unknown_fields = true,
});
defer parsed.deinit();
const value = parsed.value; // your MyStruct
```
</details>

<details>
<summary>Memory ownership pattern</summary>

```zig
// The JSON parser owns the parsed data — it's freed on parsed.deinit().
// To keep data alive, build your own copies via ArrayList → toOwnedSlice.
var routes: std.ArrayList(Route) = .empty;
defer routes.deinit(allocator);
for (jc.routes) |jr| {
    try routes.append(allocator, .{ .prefix = jr.prefix, .upstream = jr.upstream });
}
const owned_routes = try routes.toOwnedSlice(allocator);
// owned_routes must be freed by the caller
```
</details>

<details>
<summary>Defer chains for cleanup</summary>

```zig
const file = try std.fs.cwd().openFile(path, .{});
defer file.close();
const content = try file.readToEndAlloc(allocator, 1024 * 1024);
// content ownership transfers to parse(), which stores it as _raw_json
```
</details>

---

## Exercise 04: Token Bucket Rate Limiter

**File:** `src/ratelimit/limiter.zig`
**Run:** `zig build test-04`

### What You'll Learn
- **`f64` math** for precise rate calculations
- **`@floatFromInt`** builtin for int→float conversion
- **`@min`** builtin for clamping
- **`std.time.nanoTimestamp`** for high-resolution timing
- **Mutable self** (`*RateLimiter`)

### Your Task
Implement 3 functions:
1. `init` — Calculate refill rate and start with a full bucket
2. `allow` — Check/consume a token, returning true/false
3. `refill` — Add tokens based on elapsed nanoseconds

### Key Concepts

<details>
<summary>@floatFromInt</summary>

```zig
const rate: f64 = @floatFromInt(requests_per_second); // u32 → f64
const ns: f64 = @floatFromInt(std.time.ns_per_s);     // comptime_int → f64
const tokens_per_ns = rate / ns;
```
</details>

<details>
<summary>Token bucket algorithm</summary>

The bucket starts full (`burst_size` tokens). Each `allow()` call:
1. Refills tokens based on time elapsed since last refill
2. If tokens >= 1.0, consume one token → allowed
3. Otherwise → denied

Refill formula: `new_tokens = elapsed_ns * (requests_per_second / ns_per_s)`
Tokens are capped at `max_tokens` (burst size).
</details>

<details>
<summary>Mutable self</summary>

```zig
// `*RateLimiter` means the method can modify the struct
pub fn allow(self: *RateLimiter) bool {
    self.tokens -= 1.0; // modifies in place
    return true;
}
```
</details>

---

## Exercise 05: Circuit Breaker State Machine

**File:** `src/circuit/breaker.zig`
**Run:** `zig build test-05`

### What You'll Learn
- **Enum state machines** with `.closed`, `.open`, `.half_open`
- **Exhaustive switch** (compiler enforces all states handled)
- **`std.time.milliTimestamp`** for timing
- **`@intCast`** for safe integer conversion
- **`std.log`** for structured logging

### Your Task
Implement 4 functions:
1. `init` — Create a circuit breaker with given thresholds
2. `allowRequest` — State-dependent request gating
3. `recordSuccess` — Handle success in each state
4. `recordFailure` — Handle failure in each state

### Key Concepts

<details>
<summary>Circuit breaker pattern</summary>

```
     ┌──────────────────────────────────┐
     │           CLOSED                 │
     │  (requests flow normally)        │
     │  failures++ on each failure      │
     └──────────┬───────────────────────┘
                │ failure_count >= threshold
                ▼
     ┌──────────────────────────────────┐
     │            OPEN                  │
     │  (all requests blocked)          │
     │  waits for reset_timeout_ms      │
     └──────────┬───────────────────────┘
                │ timeout elapsed
                ▼
     ┌──────────────────────────────────┐
     │         HALF_OPEN                │
     │  (limited test requests)         │
     │  success → CLOSED                │
     │  failure → OPEN                  │
     └─────────────────────────────────┘
```
</details>

<details>
<summary>Exhaustive switch</summary>

```zig
switch (self.state) {
    .closed => { ... },
    .open => { ... },
    .half_open => { ... },
}
// Zig requires all enum values to be handled — no missing cases!
```
</details>

<details>
<summary>Time-based transitions</summary>

```zig
const now = std.time.milliTimestamp();
const elapsed: u64 = @intCast(now - self.last_failure_time);
if (elapsed >= self.reset_timeout_ms) {
    // Transition!
}
```
</details>

---

## Exercise 06: Atomic Metrics Counters

**File:** `src/metrics/metrics.zig`
**Run:** `zig build test-06`

### What You'll Learn
- **`std.atomic.Value`** for thread-safe counters
- **`fetchAdd` / `fetchSub` / `load`** atomic operations
- **Memory ordering** (`.monotonic`)
- **JSON formatting** with ArrayList writer

### Your Task
Implement 5 functions:
1. `init` — Initialize all atomic counters to 0
2. `recordRequest` — Increment total + classify by status code range
3. `recordConnection` — Atomically increment active connections
4. `recordDisconnection` — Atomically decrement active connections
5. `toJson` — Format all metrics as a JSON string

### Key Concepts

<details>
<summary>Atomic operations</summary>

```zig
// Create an atomic counter
var counter = std.atomic.Value(u64).init(0);

// Increment atomically (returns old value)
_ = counter.fetchAdd(1, .monotonic);

// Decrement atomically
_ = counter.fetchSub(1, .monotonic);

// Read current value
const val = counter.load(.monotonic);
```
</details>

<details>
<summary>Memory ordering</summary>

`.monotonic` is the weakest ordering — it guarantees atomicity but no ordering
relative to other operations. It's sufficient for independent counters that
don't need to synchronize with each other.
</details>

<details>
<summary>JSON formatting with writer</summary>

```zig
var buf: std.ArrayList(u8) = .empty;
const writer = buf.writer(allocator);
try writer.print(
    \\{{"key":{d}}}
, .{value});
return buf.toOwnedSlice(allocator);
```
Note: `\\` is Zig's multiline string literal. `{{` and `}}` are escaped braces.
</details>

---

## Exercise 07: Health Check Worker

**File:** `src/health/checker.zig`
**Run:** `zig build test-07`

### What You'll Learn
- **`std.Thread`** for background workers
- **Atomic booleans** for thread signaling
- **`std.StringHashMap`** for dynamic key-value storage
- **`getOrPut`** for upsert semantics
- **Thread lifecycle** (spawn, signal, join)

### Your Task
Implement 4 functions (network code is provided):
1. `init` — Initialize the checker with allocator, config, and empty hash map
2. `recordResult` — Upsert health status for an endpoint key
3. `isHealthy` — Look up current health status by host:port
4. `deinit` — Stop thread, free all hash map keys, deinit map

### Key Concepts

<details>
<summary>StringHashMap getOrPut</summary>

```zig
// getOrPut returns a result with found_existing and value_ptr
const owned_key = try allocator.dupe(u8, key);
const gop = try map.getOrPut(owned_key);
if (gop.found_existing) {
    allocator.free(owned_key); // don't leak the duplicate
} else {
    gop.value_ptr.* = .{}; // initialize new entry
}
gop.value_ptr.*.some_field = new_value;
```
</details>

<details>
<summary>Thread lifecycle</summary>

```zig
// Start
self.running.store(true, .release);
self.thread = try std.Thread.spawn(.{}, workerFn, .{self});

// Stop (from another thread)
self.running.store(false, .release);
if (self.thread) |t| t.join(); // wait for clean exit
```
</details>

<details>
<summary>Freeing hash map keys</summary>

```zig
var it = self.statuses.keyIterator();
while (it.next()) |k| {
    self.allocator.free(k.*);
}
self.statuses.deinit();
```
</details>

---

## Running Everything

Once all exercises pass individually:

```bash
# Run all tests at once
zig build test

# Run the proxy
zig build run
# or with a custom config:
zig build run -- my-config.json
```

## Architecture Overview

```
                  ┌─────────────┐
  Client ──────▶  │   Server    │
                  │  (proxy/    │
                  │  server.zig)│
                  └──────┬──────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌─────▼─────┐   ┌─────▼─────┐
    │ Request │    │  Config   │   │  Metrics  │
    │ Parser  │    │  (JSON)   │   │ (Atomic)  │
    │ (Ex 01) │    │  (Ex 03)  │   │  (Ex 06)  │
    └─────────┘    └───────────┘   └───────────┘
    ┌─────────┐    ┌───────────┐   ┌───────────┐
    │Response │    │Rate Limit │   │  Health   │
    │ Builder │    │(Token Bkt)│   │  Checker  │
    │ (Ex 02) │    │  (Ex 04)  │   │  (Ex 07)  │
    └─────────┘    └───────────┘   └───────────┘
                   ┌───────────┐
                   │  Circuit  │
                   │  Breaker  │
                   │  (Ex 05)  │
                   └───────────┘
```

Happy hacking!

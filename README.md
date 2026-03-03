# zigvoy

Learn Zig by building a fully functional L7 reverse proxy. 7 exercises, each with pre-written failing tests — implement the stubs, make the tests green, move on.

When all exercises pass, you have a working reverse proxy with rate limiting, circuit breaking, health checks, and metrics.

## Prerequisites

- [Zig 0.15+](https://ziglang.org/download/)
- Git

## Quick Start

```bash
git clone https://github.com/ggreg/zigvoy.git
cd zigvoy

# Start with exercise 01
zig build test-01

# Open the file, find the TODOs, implement them
$EDITOR src/http/request.zig

# Run tests until they pass
zig build test-01
```

## Exercises

| # | Command | File | What You'll Build | Zig Concepts |
|---|---------|------|-------------------|--------------|
| 01 | `zig build test-01` | `src/http/request.zig` | HTTP Request Parser | enums, `StaticStringMap`, slices, error unions |
| 02 | `zig build test-02` | `src/http/response.zig` | HTTP Response Builder | struct methods, ArrayList writer, switch expressions |
| 03 | `zig build test-03` | `src/config/config.zig` | JSON Configuration | `std.json`, nested structs, memory ownership |
| 04 | `zig build test-04` | `src/ratelimit/limiter.zig` | Token Bucket Rate Limiter | `f64` math, `@floatFromInt`, `@min` |
| 05 | `zig build test-05` | `src/circuit/breaker.zig` | Circuit Breaker State Machine | enum state machines, exhaustive switch |
| 06 | `zig build test-06` | `src/metrics/metrics.zig` | Atomic Metrics Counters | `std.atomic.Value`, `fetchAdd`/`fetchSub` |
| 07 | `zig build test-07` | `src/health/checker.zig` | Health Check Worker | `std.Thread`, `StringHashMap`, `getOrPut` |

## How It Works

Each exercise file has:
- **Struct and type definitions** — provided for you
- **Method stubs** — bodies replaced with `// TODO` comments
- **Comprehensive tests** — 7-10 tests that fail until you implement the stubs

```zig
pub fn parse(allocator: std.mem.Allocator, buf: []const u8) !HttpRequest {
    // TODO: Exercise 01 - Parse the HTTP request
    // Steps:
    //   1. Find first \r\n to get the request line
    //   2. Split on spaces to get method, path, version
    //   ...
    _ = allocator;
    _ = buf;
    return error.MalformedRequest;
}
```

## Getting Hints

Detailed hints and Zig concept explanations for each exercise are in [TUTORIAL.md](TUTORIAL.md).

## Peeking at Solutions

The `solutions` branch has the complete working implementation:

```bash
# See the solution for a specific file
git diff master..solutions -- src/http/request.zig

# See all solutions
git diff master..solutions
```

## Running the Proxy

Once all 7 exercises pass:

```bash
# Run all tests
zig build test

# Start the proxy (uses zigvoy.json config)
zig build run

# Or with a custom config
zig build run -- my-config.json
```

## Architecture

```
Client ──▶ Server (proxy/server.zig)
              │
    ┌─────────┼─────────┐
    │         │         │
 Request   Config    Metrics
 Parser    (JSON)    (Atomic)
 (Ex 01)   (Ex 03)   (Ex 06)

Response  Rate Limit  Health
 Builder  (Token Bkt) Checker
 (Ex 02)   (Ex 04)   (Ex 07)

          Circuit
          Breaker
          (Ex 05)
```

## License

MIT

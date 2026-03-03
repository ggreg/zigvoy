// Test shim for Exercise 07 — sets module root to src/ so that
// health/checker.zig can import ../config/config.zig
test {
    _ = @import("health/checker.zig");
}

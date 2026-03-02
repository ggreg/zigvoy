const std = @import("std");
const zigvoy = @import("zigvoy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config_path = if (args.len > 1) args[1] else "zigvoy.json";

    const config = zigvoy.Config.loadFromFile(allocator, config_path) catch |err| {
        std.log.err("failed to load config '{s}': {}", .{ config_path, err });
        std.process.exit(1);
    };
    defer config.deinit();

    std.log.info("zigvoy starting on :{d}", .{config.listen_port});
    std.log.info("  routes: {d}, upstreams: {d}", .{
        config.routes.len,
        config.upstreams.len,
    });

    var server = zigvoy.Server.init(allocator, config) catch |err| {
        std.log.err("failed to init server: {}", .{err});
        std.process.exit(1);
    };
    defer server.deinit();

    server.run() catch |err| {
        std.log.err("server error: {}", .{err});
        std.process.exit(1);
    };
}

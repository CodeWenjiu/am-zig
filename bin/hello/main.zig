const std = @import("std");

/// Simple hello/demo binary:
/// - Prints the executable name.
/// - Prints target triple and CPU features summary.
pub fn main() !void {
    const t = @import("builtin").target;

    std.log.info("hello demo", .{});
    std.log.info("target: {s}-{s}-{s}", .{
        @tagName(t.cpu.arch),
        @tagName(t.os.tag),
        @tagName(t.abi),
    });
    std.log.info("cpu model: {s}", .{t.cpu.model.name});
    std.log.info("cpu features: {}", .{t.cpu.features});
}

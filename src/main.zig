const std = @import("std");

/// Application entrypoint.
///
/// This is intentionally *not* the hosted Zig `main()` shape.
/// Instead, both runtimes call into this function:
/// - native runtime collects OS argv into a fixed buffer and forwards it here
/// - bare-metal runtime parses `-Darg="..."` into argv slices and forwards it here
pub fn main(argv: []const []const u8) !void {
    // Match typical argv conventions: argv[0] is program name (or "app" on bare-metal).
    if (argv.len > 0) {
        std.log.info("argv[0] = {s}", .{argv[0]});
    } else {
        std.log.info("argv is empty", .{});
    }

    for (argv, 0..) |arg, i| {
        std.log.info("arg[{d}] = {s}", .{ i, arg });
    }

    // Example: a tiny flag parser without allocation.
    // Supports: `--name=<value>`
    var name: ?[]const u8 = null;
    for (argv) |arg| {
        const prefix = "--name=";
        if (std.mem.startsWith(u8, arg, prefix)) {
            name = arg[prefix.len..];
        }
    }

    if (name) |n| {
        std.log.info("Hello {s}", .{n});
    } else {
        std.log.info("Hello, World!", .{});
    }
}

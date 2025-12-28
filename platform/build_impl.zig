const std = @import("std");

pub fn missingOptionExit(comptime T: type, name: []const u8) noreturn {
    std.debug.print("Missing required argument: -D{s}=<{s}>\n", .{ name, name });
    std.debug.print("Available options: ", .{});
    const fields = @typeInfo(T).@"enum".fields;
    inline for (fields, 0..) |field, i| {
        std.debug.print("[{s}]", .{field.name});
        if (i < fields.len - 1) std.debug.print(" | ", .{});
    }
    std.debug.print("\n", .{});
    std.process.exit(1);
}

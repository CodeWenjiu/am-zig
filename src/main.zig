const std = @import("std");

pub fn main() void {
    std.log.info("Hello, World!", .{});

    const number = 42;
    std.log.info("The answer is {}", .{number});

    const name = "Zig";
    std.log.info("Hello {s}", .{name});
}

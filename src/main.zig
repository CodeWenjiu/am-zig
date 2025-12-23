const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, {s}!\n", .{"World"});
}

const expect = std.testing.expect;
test "test" {
    try expect(true);
}

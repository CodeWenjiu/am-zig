const std = @import("std");

const HookError = error{CommandFailed};

fn runCmd(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return HookError.CommandFailed,
        else => return HookError.CommandFailed,
    }
}

/// Per-bin hook invoked by the top-level build:
/// - Generates embedded test images and weights into Zig source files.
/// - Keeps runtime freestanding-friendly (no filesystem access at runtime).
pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const gen_images = &[_][]const u8{
        "zig",
        "run",
        "bin/mnist/build_tools/gen_embedded_images.zig",
        "--",
        "--input-dir",
        "bin/mnist/test_images",
        "--output",
        "bin/mnist/generated/embedded_images.zig",
    };

    const gen_weights = &[_][]const u8{
        "zig",
        "run",
        "bin/mnist/build_tools/gen_weights.zig",
        "--",
        "--input-dir",
        "bin/mnist/binarys",
        "--output",
        "bin/mnist/generated/weights.zig",
    };

    std.debug.print("mnist hook: generating embedded images...\n", .{});
    try runCmd(alloc, gen_images);

    std.debug.print("mnist hook: generating weights...\n", .{});
    try runCmd(alloc, gen_weights);

    std.debug.print("mnist hook: done\n", .{});
}

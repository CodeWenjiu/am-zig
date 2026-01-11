const std = @import("std");

const inference_mod = @import("inference.zig");
const Inference = inference_mod.Inference;

/// If you want a "benchmark-only" mode like the Rust version, you can change this
/// constant, or (preferably) wire it to build options / argv in the future.
const BENCHMARK_ONLY_MODE: bool = false;

/// Freestanding-friendly heap size for MNIST inference/benchmark.
/// Increase if you hit OOM from temporary buffers.
const HEAP_BYTES: usize = 256 * 1024;

pub fn main() !void {
    // Freestanding targets (riscv32-freestanding-none) cannot rely on OS primitives that
    // some general-purpose allocators use. Use a fixed buffer allocator instead.
    var heap_buf: [HEAP_BYTES]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&heap_buf);
    const allocator = fba.allocator();

    const infer = Inference.init();

    if (BENCHMARK_ONLY_MODE) {
        try stdoutPrint("=== BENCHMARK-ONLY MODE ===\n", .{});

        try infer.detailedPerformanceAnalysis(allocator);
        try stdoutPrint("\n", .{});

        try infer.runBenchmark(allocator);
        return;
    }

    try stdoutPrint("=== QUICK BENCHMARK ===\n", .{});
    try infer.runBenchmark(allocator);
    try stdoutPrint("\n", .{});

    try infer.runTests(allocator);
}

fn stdoutPrint(comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, fmt, args);

    const writer = if (@hasDecl(@import("root"), "getStdOut"))
        @import("root").getStdOut()
    else
        std.fs.File.stdout().writer();

    try writer.writeAll(msg);
}

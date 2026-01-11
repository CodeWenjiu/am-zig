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
        std.log.info("=== BENCHMARK-ONLY MODE ===", .{});

        try infer.detailedPerformanceAnalysis(allocator);
        std.log.info("", .{});

        try infer.runBenchmark(allocator);
        return;
    }

    std.log.info("=== QUICK BENCHMARK ===", .{});
    try infer.runBenchmark(allocator);
    std.log.info("", .{});

    try infer.runTests(allocator);
}

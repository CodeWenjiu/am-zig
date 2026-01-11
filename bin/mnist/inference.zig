const std = @import("std");

/// MNIST INT8 inference + benchmarking (Zig translation of the provided Rust code).
///
/// Notes / assumptions:
/// - This module is self-contained and does not print via UART-specific mechanisms.
///   It uses `std.log` which should route to your existing platform log hook.
///
/// - Weight binaries are expected at:
///   - `bin/mnist/binarys/fc1_weight.bin`
///   - `bin/mnist/binarys/fc2_weight.bin`
///   - `bin/mnist/binarys/fc3_weight.bin`
///
///   with the same layout assumed by the Rust code:
///   - bytes[0..8]    : unused header
///   - bytes[8..12]   : f32 little-endian "scale"
///   - bytes[12..]    : ROWS*COLS int8 weight bytes, row-major
///
/// - Embedded test images are expected to be provided by an `embedded_images.zig` file
///   under the same directory exporting:
///     `pub const EMBEDDED_TEST_IMAGES: []const []const u8;`
///   where each entry is a binary blob with:
///     - bytes[8]      : label (u8)
///     - bytes[9..]    : 784 bytes image
///
/// Weight binaries are expected to be embedded via `weights.zig` (generated at build time),
/// so we don't rely on `@embedFile` paths (which are fragile in multi-root builds).
const embedded_images = @import("generated/embedded_images.zig");
pub const EMBEDDED_TEST_IMAGES = embedded_images.EMBEDDED_TEST_IMAGES;

const weights_mod = @import("generated/weights.zig");

// Benchmark configuration (mirrors Rust constants)
pub const BENCHMARK_ITERATIONS: usize = 1000;
pub const WARMUP_ITERATIONS: usize = 100;
pub const DETAILED_BENCHMARK_ITERATIONS: usize = 100;

pub const Q16_SHIFT: u5 = 16;

/// Convert float scale to Q16 fixed-point
fn scaleToQ16(scale: f32) i32 {
    // Equivalent to: (scale * (1 << Q16_SHIFT) as f32) as i32
    return @intFromFloat(scale * @as(f32, @floatFromInt(@as(u32, 1) << Q16_SHIFT)));
}

/// Inference object holding weights and per-layer Q16 scales.
///
/// Uses fixed-size arrays like the Rust version:
/// - FC1: 256x784 i8
/// - FC2: 128x256 i8
/// - FC3: 10x128 i8
pub const Inference = struct {
    fc1_weights: [256][784]i8,
    fc2_weights: [128][256]i8,
    fc3_weights: [10][128]i8,

    fc1_scale_q16: i32,
    fc2_scale_q16: i32,
    fc3_scale_q16: i32,

    pub fn init() Inference {
        // Weights are provided by `weights.zig` (generated at build time), mirroring Rust's build.rs approach.
        const fc1_parsed = parseWeightBinaryConst(256, 784, weights_mod.FC1_WEIGHT_DATA);
        const fc2_parsed = parseWeightBinaryConst(128, 256, weights_mod.FC2_WEIGHT_DATA);
        const fc3_parsed = parseWeightBinaryConst(10, 128, weights_mod.FC3_WEIGHT_DATA);

        const fc1_weights = fc1_parsed.weights;
        const fc2_weights = fc2_parsed.weights;
        const fc3_weights = fc3_parsed.weights;

        const fc1_scale = fc1_parsed.scale;
        const fc2_scale = fc2_parsed.scale;
        const fc3_scale = fc3_parsed.scale;

        std.log.info("Model weights loaded successfully!\n", .{});
        std.log.info("FC1: {d}x{d}, scale: {d:.6}\n", .{ fc1_weights.len, fc1_weights[0].len, fc1_scale });
        std.log.info("FC2: {d}x{d}, scale: {d:.6}\n", .{ fc2_weights.len, fc2_weights[0].len, fc2_scale });
        std.log.info("FC3: {d}x{d}, scale: {d:.6}\n\n", .{ fc3_weights.len, fc3_weights[0].len, fc3_scale });

        const fc1_scale_q16 = scaleToQ16(fc1_scale);
        const fc2_scale_q16 = scaleToQ16(fc2_scale);
        const fc3_scale_q16 = scaleToQ16(fc3_scale);

        std.log.info("Quantization Scales (Fixed Point):\n", .{});
        std.log.info("  FC1_SCALE: {d:.6} -> Q16: {d}\n", .{ fc1_scale, fc1_scale_q16 });
        std.log.info("  FC2_SCALE: {d:.6} -> Q16: {d}\n", .{ fc2_scale, fc2_scale_q16 });
        std.log.info("  FC3_SCALE: {d:.6} -> Q16: {d}\n\n", .{ fc3_scale, fc3_scale_q16 });

        return .{
            .fc1_weights = fc1_weights,
            .fc2_weights = fc2_weights,
            .fc3_weights = fc3_weights,
            .fc1_scale_q16 = fc1_scale_q16,
            .fc2_scale_q16 = fc2_scale_q16,
            .fc3_scale_q16 = fc3_scale_q16,
        };
    }

    /// Complete pure INT8 inference (no FP math in the compute pipeline):
    /// 1) normalize input (u8 -> i8)
    /// 2) fc1 matmul -> i32, scale -> i32
    /// 3) i32 -> i8 scaling, ReLU
    /// 4) fc2 ...
    /// 5) fc3 ...
    /// 6) argmax
    pub fn mnistInferencePureInt8(
        self: *const Inference,
        allocator: std.mem.Allocator,
        input_image: []const u8,
    ) !usize {
        if (input_image.len != 784) return error.InvalidInputLen;

        const normalized_input = try normalizeAndQuantizeInput(allocator, input_image);
        defer allocator.free(normalized_input);

        const fc1_out = try int8MatmulSymmetric(allocator, 256, 784, &self.fc1_weights, normalized_input, self.fc1_scale_q16);
        defer allocator.free(fc1_out);

        const fc1_act = try int32ToInt8WithScaling(allocator, fc1_out);
        defer allocator.free(fc1_act);
        reluInt8(fc1_act);

        const fc2_out = try int8MatmulSymmetric(allocator, 128, 256, &self.fc2_weights, fc1_act, self.fc2_scale_q16);
        defer allocator.free(fc2_out);

        const fc2_act = try int32ToInt8WithScaling(allocator, fc2_out);
        defer allocator.free(fc2_act);
        reluInt8(fc2_act);

        const fc3_out = try int8MatmulSymmetric(allocator, 10, 128, &self.fc3_weights, fc2_act, self.fc3_scale_q16);
        defer allocator.free(fc3_out);

        return argmaxInt32(fc3_out);
    }

    /// Test on embedded images.
    pub fn runTests(self: *const Inference, allocator: std.mem.Allocator) !void {
        const test_images_data = EMBEDDED_TEST_IMAGES;
        const total_images = test_images_data.len;
        var correct: usize = 0;

        var idx: usize = 0;
        while (idx < total_images) : (idx += 1) {
            std.log.info("=== Test Image {d} ===", .{idx + 1});

            const parsed = try parseImageBinary(allocator, test_images_data[idx]);
            defer allocator.free(parsed.image);

            std.log.info("True label: {d}", .{parsed.label});

            const predicted = try self.mnistInferencePureInt8(allocator, parsed.image);
            std.log.info("Predicted:  {d}", .{predicted});

            if (predicted == parsed.label) {
                std.log.info("✓ CORRECT PREDICTION!", .{});
                correct += 1;
            } else {
                std.log.info("✗ WRONG PREDICTION!", .{});
            }
        }

        std.log.info("=== FINAL RESULTS ===", .{});
        std.log.info("Total images: {d}", .{total_images});
        std.log.info("Correct predictions: {d}", .{correct});
        const acc = if (total_images == 0) 0.0 else (@as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(total_images))) * 100.0;
        std.log.info("Accuracy: {d:.2}%", .{acc});
    }

    /// Benchmark full inference loop with cycle counting.
    pub fn runBenchmark(self: *const Inference, allocator: std.mem.Allocator) !void {
        std.log.info("=== BENCHMARK MODE ===", .{});
        std.log.info("Warmup iterations: {d}", .{WARMUP_ITERATIONS});
        std.log.info("Benchmark iterations: {d}", .{BENCHMARK_ITERATIONS});

        if (EMBEDDED_TEST_IMAGES.len == 0) return error.NoTestImages;

        const parsed = try parseImageBinary(allocator, EMBEDDED_TEST_IMAGES[0]);
        defer allocator.free(parsed.image);

        std.log.info("Running warmup...\n", .{});

        var i: usize = 0;
        while (i < WARMUP_ITERATIONS) : (i += 1) {
            _ = try self.mnistInferencePureInt8(allocator, parsed.image);
        }

        std.log.info("Running benchmark with cycle counting...\n", .{});

        const start_cycles = readCycleCounter();
        i = 0;
        while (i < BENCHMARK_ITERATIONS) : (i += 1) {
            _ = try self.mnistInferencePureInt8(allocator, parsed.image);
        }
        const end_cycles = readCycleCounter();

        const total_cycles_u = end_cycles - start_cycles;
        const total_cycles: u64 = @intCast(total_cycles_u);

        const cycles_per_inference: u64 = if (BENCHMARK_ITERATIONS == 0) 0 else total_cycles / @as(u64, BENCHMARK_ITERATIONS);

        const inferences_per_second: u64 = if (total_cycles > 0 and BENCHMARK_ITERATIONS > 0)
            (1_000_000_000 * @as(u64, BENCHMARK_ITERATIONS)) / total_cycles
        else
            0;

        std.log.info("=== BENCHMARK RESULTS ===\n", .{});

        std.log.info("Total cycles measured: {d}\n", .{total_cycles});

        std.log.info("Iterations completed: {d}\n", .{BENCHMARK_ITERATIONS});

        std.log.info("Cycles per inference: {d}\n", .{cycles_per_inference});

        std.log.info("Inferences per second (1GHz): {d}\n", .{inferences_per_second});

        std.log.info("Performance classification:\n", .{});

        if (cycles_per_inference < 100_000) {
            std.log.info("Excellent performance\n", .{});
        } else if (cycles_per_inference < 500_000) {
            std.log.info("Good performance\n", .{});
        } else if (cycles_per_inference < 2_000_000) {
            std.log.info("Moderate performance\n", .{});
        } else {
            std.log.info("Needs optimization\n", .{});
        }

        const total_mac_operations: u64 = @as(u64, BENCHMARK_ITERATIONS) * (@as(u64, (784 * 256) + (256 * 128) + (128 * 10)));
        const macs_per_cycle: f64 = if (total_cycles > 0) @as(f64, @floatFromInt(total_mac_operations)) / @as(f64, @floatFromInt(total_cycles)) else 0.0;

        std.log.info("Total MAC operations: {d}\n", .{total_mac_operations});

        std.log.info("MACs per cycle: {d:.4}\n", .{macs_per_cycle});

        std.log.info("Note: Higher MACs/cycle indicates better vectorization\n", .{});

        if (BENCHMARK_ITERATIONS > 0) {
            std.log.info("Benchmark completed successfully\n", .{});
        }

        std.log.info("Use this as baseline for optimization comparisons\n", .{});
    }

    /// Detailed timing of major components (mirrors the Rust detailed analysis).
    pub fn detailedPerformanceAnalysis(self: *const Inference, allocator: std.mem.Allocator) !void {
        std.log.info("=== DETAILED PERFORMANCE ANALYSIS ===", .{});

        if (EMBEDDED_TEST_IMAGES.len == 0) return error.NoTestImages;

        const parsed = try parseImageBinary(allocator, EMBEDDED_TEST_IMAGES[0]);
        defer allocator.free(parsed.image);

        const normalized_input = try normalizeAndQuantizeInput(allocator, parsed.image);
        defer allocator.free(normalized_input);

        var total_cycles: u64 = 0;

        // normalize
        var start = readCycleCounter();
        var i: usize = 0;
        while (i < DETAILED_BENCHMARK_ITERATIONS) : (i += 1) {
            const tmp = try normalizeAndQuantizeInput(allocator, parsed.image);
            allocator.free(tmp);
        }
        var end = readCycleCounter();
        const norm_cycles: u64 = @intCast((end - start) / DETAILED_BENCHMARK_ITERATIONS);
        std.log.info("normalize_input_pure_int8: {d} cycles/call", .{norm_cycles});
        total_cycles += norm_cycles;

        // fc1 matmul
        start = readCycleCounter();
        i = 0;
        while (i < DETAILED_BENCHMARK_ITERATIONS) : (i += 1) {
            const tmp = try int8MatmulSymmetric(allocator, 256, 784, &self.fc1_weights, normalized_input, self.fc1_scale_q16);
            allocator.free(tmp);
        }
        end = readCycleCounter();
        const fc1_cycles: u64 = @intCast((end - start) / DETAILED_BENCHMARK_ITERATIONS);
        std.log.info("FC1 matmul (256x784): {d} cycles/call", .{fc1_cycles});
        total_cycles += fc1_cycles;

        const fc1_output = try int8MatmulSymmetric(allocator, 256, 784, &self.fc1_weights, normalized_input, self.fc1_scale_q16);
        defer allocator.free(fc1_output);

        // scaling
        start = readCycleCounter();
        i = 0;
        while (i < DETAILED_BENCHMARK_ITERATIONS) : (i += 1) {
            const tmp = try int32ToInt8WithScaling(allocator, fc1_output);
            allocator.free(tmp);
        }
        end = readCycleCounter();
        const scale_cycles: u64 = @intCast((end - start) / DETAILED_BENCHMARK_ITERATIONS);
        std.log.info("int32_to_int8_with_scaling: {d} cycles/call", .{scale_cycles});
        total_cycles += scale_cycles;

        // relu
        const fc1_act = try int32ToInt8WithScaling(allocator, fc1_output);
        defer allocator.free(fc1_act);

        start = readCycleCounter();
        i = 0;
        while (i < DETAILED_BENCHMARK_ITERATIONS) : (i += 1) {
            reluInt8(fc1_act);
        }
        end = readCycleCounter();
        const relu_cycles: u64 = @intCast((end - start) / DETAILED_BENCHMARK_ITERATIONS);
        std.log.info("relu6_int8: {d} cycles/call", .{relu_cycles});
        total_cycles += relu_cycles;

        std.log.info("Estimated total cycles per inference: {d}\n", .{total_cycles});

        std.log.info("Breakdown:\n", .{});

        if (total_cycles > 0) {
            std.log.info("  - Input normalization: {d:.1}%\n", .{@as(f64, @floatFromInt(norm_cycles * 100)) / @as(f64, @floatFromInt(total_cycles))});

            std.log.info("  - FC1 matmul: {d:.1}%\n", .{@as(f64, @floatFromInt(fc1_cycles * 100)) / @as(f64, @floatFromInt(total_cycles))});

            std.log.info("  - Scaling: {d:.1}%\n", .{@as(f64, @floatFromInt(scale_cycles * 100)) / @as(f64, @floatFromInt(total_cycles))});

            std.log.info("  - Activation: {d:.1}%\n", .{@as(f64, @floatFromInt(relu_cycles * 100)) / @as(f64, @floatFromInt(total_cycles))});
        }
    }
};

pub const Error = error{
    InvalidWeightBinary,
    InvalidInputLen,
    InvalidImageBinary,
    OutOfMemory,
    NoTestImages,
};

/// Parsed weight result
fn WeightParseResult(comptime ROWS: usize, comptime COLS: usize) type {
    return struct {
        weights: [ROWS][COLS]i8,
        scale: f32,
    };
}

/// Parse weight binary blob at comptime into fixed-size weights + scale.
/// Mirrors the Rust `const fn parse_weight_binary_const`.
fn parseWeightBinaryConst(comptime ROWS: usize, comptime COLS: usize, data: []const u8) WeightParseResult(ROWS, COLS) {
    // Basic length check at comptime (cannot error-return from comptime easily in older Zig),
    // so we defensively bounds-check via indexing; if invalid, compilation will fail.
    const scale_bytes = [4]u8{ data[8], data[9], data[10], data[11] };
    const scale = std.mem.bytesToValue(f32, &scale_bytes);

    var wts: [ROWS][COLS]i8 = undefined;
    var i: usize = 0;
    while (i < ROWS) : (i += 1) {
        var j: usize = 0;
        const start = 12 + i * COLS;
        while (j < COLS) : (j += 1) {
            wts[i][j] = @bitCast(@as(i8, @intCast(data[start + j])));
        }
    }

    return .{ .weights = wts, .scale = scale };
}

/// Normalize input from UINT8 [0,255] to INT8 [-128,127] like the Rust code.
///
/// **Important**: the Rust code uses f32 normalization and then maps to [0..127],
/// not [-127..127]. We keep the same behavior for fidelity.
///
/// quantized = (pixel/255.0 * 127.0) as i32, clamped to [-128,127]
fn normalizeAndQuantizeInput(allocator: std.mem.Allocator, input: []const u8) ![]i8 {
    var out = try allocator.alloc(i8, input.len);
    errdefer allocator.free(out);

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const pixel = input[i];
        const normalized: f32 = @as(f32, @floatFromInt(pixel)) / 255.0;
        const q_i32: i32 = @intFromFloat(normalized * 127.0);

        const clamped: i32 = if (q_i32 < -128) -128 else if (q_i32 > 127) 127 else q_i32;
        out[i] = @intCast(clamped);
    }

    return out;
}

/// Matrix multiply: output[i] = (sum_j weights[i][j] * input[j]) scaled by Q16.
///
/// Returns i32 vector length ROWS.
fn int8MatmulSymmetric(
    allocator: std.mem.Allocator,
    comptime ROWS: usize,
    comptime COLS: usize,
    wts: *const [ROWS][COLS]i8,
    input: []const i8,
    scale_q16: i32,
) ![]i32 {
    if (input.len != COLS) return error.InvalidInputLen;

    var out = try allocator.alloc(i32, ROWS);
    errdefer allocator.free(out);

    var i: usize = 0;
    while (i < ROWS) : (i += 1) {
        var sum: i32 = 0;
        var j: usize = 0;
        while (j < COLS) : (j += 1) {
            sum += @as(i32, wts[i][j]) * @as(i32, input[j]);
        }

        const scaled_i64: i64 = (@as(i64, sum) * @as(i64, scale_q16)) >> Q16_SHIFT;
        out[i] = @intCast(scaled_i64);
    }

    return out;
}

/// Convert i32 slice to i8 with dynamic right shift scaling so max abs <= 127.
fn int32ToInt8WithScaling(allocator: std.mem.Allocator, input: []const i32) ![]i8 {
    var max_abs: i32 = 0;
    for (input) |x| {
        const ax = if (x < 0) -x else x;
        if (ax > max_abs) max_abs = ax;
    }

    var out = try allocator.alloc(i8, input.len);
    errdefer allocator.free(out);

    if (max_abs == 0) {
        @memset(out, 0);
        return out;
    }

    var shift: u5 = 0;
    var max_val: i32 = max_abs;
    while (max_val > 127 and shift < 31) : (shift += 1) {
        max_val >>= 1;
    }

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const x = input[i];
        const shifted: i32 = x >> shift;
        const clamped: i32 = if (shifted < -128) -128 else if (shifted > 127) 127 else shifted;
        out[i] = @intCast(clamped);
    }

    return out;
}

/// ReLU for i8: clamp negatives to 0.
fn reluInt8(data: []i8) void {
    for (data) |*v| {
        if (v.* < 0) v.* = 0;
    }
}

fn argmaxInt32(data: []const i32) usize {
    if (data.len == 0) return 0;
    var best_idx: usize = 0;
    var best_val: i32 = data[0];
    var i: usize = 1;
    while (i < data.len) : (i += 1) {
        const v = data[i];
        if (v > best_val) {
            best_val = v;
            best_idx = i;
        }
    }
    return best_idx;
}

const ParsedImage = struct {
    image: []u8,
    label: usize,
};

fn parseImageBinary(allocator: std.mem.Allocator, data: []const u8) !ParsedImage {
    if (data.len < 9) return error.InvalidImageBinary;
    const label: usize = data[8];

    const img = try allocator.alloc(u8, data.len - 9);
    errdefer allocator.free(img);
    @memcpy(img, data[9..]);

    return .{ .image = img, .label = label };
}

/// Cycle counter access.
/// - On RISC-V: use rdcycle
/// - Otherwise: return 0 (freestanding-friendly; avoids std.time/OS deps)
fn readCycleCounter() usize {
    const builtin = @import("builtin");
    if (builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64) {
        var cycles: usize = 0;
        // `rdcycle` exists in M-mode and is typically enabled on simulators.
        asm volatile ("rdcycle %[out]"
            : [out] "=r" (cycles),
            :
            : .{ .memory = true });
        return cycles;
    }

    // Freestanding-friendly fallback: no timers available here.
    // Callers will see 0 cycles for non-RISC-V targets.
    return 0;
}

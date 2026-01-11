const std = @import("std");

pub fn entryModule(
    b: *std.Build,
    feature_profile: ?[]const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    _ = feature_profile;
    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/spike/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);

    // NOTE:
    // Do not hardcode the ISA start shim here. The top-level build injects
    // the correct `isa_riscv_start` module based on arch/feature selection.
    // (e.g. vector-enabled `_start` vs non-vector `_start`).

    return entry_mod;
}

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("platform/spike/linker.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

fn containsChar(flags: []const u8, ch: u8) bool {
    for (flags) |c| {
        if (c == ch) return true;
    }
    return false;
}

fn containsSubstring(flags: []const u8, substr: []const u8) bool {
    return std.mem.indexOf(u8, flags, substr) != null;
}

fn hasVectorFlag(flags: []const u8) bool {
    if (containsChar(flags, 'v')) return true;
    return containsSubstring(flags, "zv");
}

fn parseZvlBitsLowerBound(flags: []const u8) ?usize {
    // Parse `zvl<NNN>b` from a feature profile string like "im_zve32x_zvl128b".
    // Returns the numeric bit lower bound (e.g. 128), or null if not present.
    //
    // Multiple `zvl*` occurrences are invalid and will hard-fail, because they imply
    // conflicting minimum VLEN requirements.
    const prefix = "zvl";
    const suffix = "b";

    var found: ?usize = null;

    var i: usize = 0;
    while (i + prefix.len <= flags.len) : (i += 1) {
        if (!std.mem.startsWith(u8, flags[i..], prefix)) continue;

        var j = i + prefix.len;

        // Must have at least 1 digit.
        if (j >= flags.len or flags[j] < '0' or flags[j] > '9') continue;

        var value: usize = 0;
        while (j < flags.len) : (j += 1) {
            const ch = flags[j];
            if (ch < '0' or ch > '9') break;
            value = value * 10 + @as(usize, ch - '0');
        }

        // Must end with trailing 'b'.
        if (j < flags.len and std.mem.startsWith(u8, flags[j..], suffix)) {
            if (found != null) {
                std.debug.panic("Invalid feature profile: multiple zvl* occurrences in: {s}", .{flags});
            }
            found = value;
        }
    }

    return found;
}

fn baseRv32IsaForFeatureFlags(flags: []const u8) []const u8 {
    // For Spike, ISA string uses the canonical "rv32<letters>" form.
    // Keep this conservative: only emit combinations we know Spike accepts.
    const has_i = containsChar(flags, 'i');
    const has_m = containsChar(flags, 'm');
    const has_a = containsChar(flags, 'a');
    const has_f = containsChar(flags, 'f');
    const has_d = containsChar(flags, 'd');
    const has_c = containsChar(flags, 'c');

    if (!has_i) std.debug.panic("Base extension 'i' required for spike", .{});

    if (has_m and has_a and has_f and has_d and has_c) return "rv32imafdc";
    if (has_m and has_a and has_f and has_c) return "rv32imafc";
    if (has_m and has_a and has_c) return "rv32imac";
    if (has_m and has_a) return "rv32ima";
    if (has_m and has_f and has_d and has_c) return "rv32imfdc";
    if (has_m and has_f and has_c) return "rv32imfc";
    if (has_m and has_c) return "rv32imc";
    if (has_m) return "rv32im";
    if (has_f and has_d and has_c) return "rv32ifdc";
    if (has_f and has_c) return "rv32ifc";
    if (has_c) return "rv32ic";
    if (has_i) return "rv32i";

    unreachable;
}

fn spikeIsaForFeatureFlags(flags: []const u8) []const u8 {
    const base = baseRv32IsaForFeatureFlags(flags);

    // Vector handling: match QEMU logic style.
    // If profile contains any vector extension (base `v` or any `zv*`), treat as vector-enabled.
    if (hasVectorFlag(flags)) {
        // Default to zvl128b when not specified.
        const vlen_bits = parseZvlBitsLowerBound(flags) orelse 128;
        // Spike ISA string expects extensions separated by '_' and vlen conveyed via zvl*.
        // Keep the vector subset conservative: use zve32x and selected zvl.
        if (std.mem.eql(u8, base, "rv32im")) {
            if (vlen_bits == 32) return "rv32im_zve32x_zvl32b";
            if (vlen_bits == 64) return "rv32im_zve32x_zvl64b";
            if (vlen_bits == 128) return "rv32im_zve32x_zvl128b";
            if (vlen_bits == 256) return "rv32im_zve32x_zvl256b";
            if (vlen_bits == 512) return "rv32im_zve32x_zvl512b";
            if (vlen_bits == 1024) return "rv32im_zve32x_zvl1024b";
            std.debug.panic("Unsupported zvl<{d}>b for spike: {s}", .{ vlen_bits, flags });
        }

        if (std.mem.eql(u8, base, "rv32i")) {
            if (vlen_bits == 32) return "rv32i_zve32x_zvl32b";
            if (vlen_bits == 64) return "rv32i_zve32x_zvl64b";
            if (vlen_bits == 128) return "rv32i_zve32x_zvl128b";
            if (vlen_bits == 256) return "rv32i_zve32x_zvl256b";
            if (vlen_bits == 512) return "rv32i_zve32x_zvl512b";
            if (vlen_bits == 1024) return "rv32i_zve32x_zvl1024b";
            std.debug.panic("Unsupported zvl<{d}>b for spike: {s}", .{ vlen_bits, flags });
        }

        std.debug.panic("Unsupported base ISA for spike vector mode: {s} (from {s})", .{ base, flags });
    }

    return base;
}

pub fn addPlatformSteps(b: *std.Build, feature_profile: ?[]const u8, exe_base_name: []const u8, exe: *std.Build.Step.Compile) void {
    _ = exe_base_name;

    const chosen_flags = feature_profile orelse std.debug.panic("Missing required -Dfeature for platform=spike", .{});

    const run_spike = b.addSystemCommand(&.{
        "spike",
        "--isa",
        spikeIsaForFeatureFlags(chosen_flags),
        "-m0x80000000:0x08000000",
    });

    run_spike.addFileArg(exe.getEmittedBin());
    run_spike.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_spike.step);
}

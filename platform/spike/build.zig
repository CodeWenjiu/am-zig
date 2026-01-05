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

fn spikeIsaForFeatureFlags(flags: []const u8) []const u8 {
    const has_i = containsChar(flags, 'i');
    const has_m = containsChar(flags, 'm');
    const has_a = containsChar(flags, 'a');
    const has_c = containsChar(flags, 'c');
    const has_zve = containsSubstring(flags, "zve");

    if (!has_i) {
        std.debug.panic("Base extension 'i' required for spike", .{});
    }

    if (has_zve) {
        if (has_m) return "rv32im_zve32x_zvl128b";
        return "rv32i";
    }

    if (has_m and has_a and has_c) return "rv32imac";
    if (has_m and !has_a and !has_c) return "rv32im";
    if (has_i and !has_m and !has_a and !has_c) return "rv32i";

    std.debug.panic("Unsupported feature combination: {s}", .{flags});
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

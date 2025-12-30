const std = @import("std");

const root = @import("../build_impl.zig");
const Isa = root.Isa;

pub fn entryModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/spike/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);

    const isa_riscv_start_pkg = b.createModule(.{
        .root_source_file = b.path("isa/riscv/start.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("isa_riscv_start", isa_riscv_start_pkg);

    return entry_mod;
}

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("platform/spike/linker.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

fn spikeIsaForIsa(isa: Isa) []const u8 {
    if (isa == .rv32i) return "rv32i";
    if (isa == .rv32im) return "rv32im";
    if (isa == .rv32im_zve32x) return "rv32im_zve32x_zvl128b";
    if (isa == .rv32imac) return "rv32imac";
    unreachable;
}

pub fn addPlatformSteps(b: *std.Build, isa: ?Isa, exe: *std.Build.Step.Compile) void {
    const chosen_isa = isa orelse root.missingOptionExit(Isa, "isa");
    // const batch = b.option(bool, "batch", "Batch mode (disable interactive debugger)") orelse false;

    const run_spike = b.addSystemCommand(&.{
        "spike",
        "--isa",
        spikeIsaForIsa(chosen_isa),
        "-m0x80000000:0x08000000",
    });

    run_spike.addFileArg(exe.getEmittedBin());
    run_spike.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_spike.step);
}

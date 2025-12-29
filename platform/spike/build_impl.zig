const std = @import("std");

const root = @import("../build_impl.zig");
const Isa = root.Isa;

fn riscv32QueryBase() std.Target.Query {
    return .{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.baseline_rv32 },
        .cpu_features_add = .empty,
        .cpu_features_sub = .empty,
    };
}

pub fn targetQuery(isa: Isa) std.Target.Query {
    var q = riscv32QueryBase();

    const F = std.Target.riscv.Feature;

    q.cpu_features_sub.addFeature(@intFromEnum(F.c));
    q.cpu_features_sub.addFeature(@intFromEnum(F.a));
    q.cpu_features_sub.addFeature(@intFromEnum(F.d));
    q.cpu_features_sub.addFeature(@intFromEnum(F.m));

    switch (isa) {
        .rv32i => {},
        .rv32im => {
            q.cpu_features_add.addFeature(@intFromEnum(F.m));
        },
        .rv32imac => {
            q.cpu_features_add.addFeature(@intFromEnum(F.m));
            q.cpu_features_add.addFeature(@intFromEnum(F.a));
            q.cpu_features_add.addFeature(@intFromEnum(F.c));
        },
        .rv32im_zve32x => {
            q.cpu_features_add.addFeature(@intFromEnum(F.m));
            q.cpu_features_add.addFeature(@intFromEnum(F.zve32x));
        },
    }

    return q;
}

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
    return entry_mod;
}

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("platform/spike/riscv/linker.x"));
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

const std = @import("std");

const root = @import("../build_impl.zig");
const Isa = root.Isa;

fn riscv32QueryBase() std.Target.Query {
    return .{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        // Zig 0.15 baseline_rv32 includes A+C+D+I+M by default.
        // Start from it, then explicitly add/sub features to match the selected ISA.
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.baseline_rv32 },
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
        .root_source_file = b.path("platform/nemu/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);
    return entry_mod;
}

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("platform/nemu/riscv/linker.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

pub fn addPlatformSteps(b: *std.Build, isa: ?Isa, exe: *std.Build.Step.Compile) void {
    _ = exe;
    _ = isa;

    const run_step = b.step("run", "Run the app");
    const warn_step = b.addSystemCommand(&.{ "sh", "-c", "echo warning: run for nemu is not implemented yet" });
    run_step.dependOn(&warn_step.step);
}

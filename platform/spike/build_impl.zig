const std = @import("std");

pub fn targetQuery(comptime Isa: type, isa: Isa) std.Target.Query {
    return switch (isa) {
        .rv32i => .{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
        },
    };
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

pub fn configureExecutable(_: *std.Build, _: *std.Build.Step.Compile) void {}

pub fn addPlatformSteps(_: *std.Build, _: *std.Build.Step.Compile) void {}

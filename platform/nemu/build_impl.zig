const std = @import("std");

const Isa = @import("../build_impl.zig").Isa;

pub fn targetQuery(isa: Isa) std.Target.Query {
    return switch (isa) {
        .rv32i,
        .rv32im,
        .rv32imac,
        .rv32im_zve32x,
        => .{
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

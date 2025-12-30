const std = @import("std");

/// Create the entry module for NEMU: wires app runtime and ISA start shim.
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
    const isa_riscv_start = b.createModule(.{
        .root_source_file = b.path("isa/riscv/start.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);
    entry_mod.addImport("isa_riscv_start", isa_riscv_start);
    return entry_mod;
}

/// NEMU uses the shared RISC-V linker script and _start symbol.
pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("isa/riscv/linker_common.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

/// Add run step for NEMU; isa_name is unused here because run is not implemented.
pub fn addPlatformSteps(b: *std.Build, isa_name: ?[]const u8, exe: *std.Build.Step.Compile) void {
    _ = exe;
    _ = isa_name;

    const run_step = b.step("run", "Run the app");
    const warn_step = b.addSystemCommand(&.{ "sh", "-c", "echo warning: run for nemu is not implemented yet" });
    run_step.dependOn(&warn_step.step);
}

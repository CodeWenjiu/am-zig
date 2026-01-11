const std = @import("std");

/// Create the entry module for NEMU: wires app runtime (ISA start shim is injected by the top-level build).
pub fn entryModule(
    b: *std.Build,
    feature_profile: ?[]const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    _ = feature_profile;

    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/nemu/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });

    entry_mod.addImport("app", app_mod);

    // Expose shared 16550 UART driver as a package for platform runtimes.
    const uart_dev_pkg = b.createModule(.{
        .root_source_file = b.path("platform/device/uart16550.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("uart_dev", uart_dev_pkg);

    return entry_mod;
}

/// NEMU uses the shared RISC-V linker script and _start symbol.
pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("isa/riscv/linker_common.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

/// Add run step for NEMU; feature_profile is unused here because run is not implemented.
pub fn addPlatformSteps(b: *std.Build, feature_profile: ?[]const u8, exe_base_name: []const u8, exe: *std.Build.Step.Compile) void {
    _ = exe;
    _ = feature_profile;
    _ = exe_base_name;

    const run_step = b.step("run", "Run the app");
    const warn_step = b.addSystemCommand(&.{ "sh", "-c", "echo warning: run for nemu is not implemented yet" });
    run_step.dependOn(&warn_step.step);
}

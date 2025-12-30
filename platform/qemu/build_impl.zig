const std = @import("std");

/// Create the entry module for QEMU: wires app runtime and ISA start shim.
pub fn entryModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/qemu/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const isa_riscv_start_pkg = b.createModule(.{
        .root_source_file = b.path("isa/riscv/start.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);
    entry_mod.addImport("isa_riscv_start", isa_riscv_start_pkg);
    return entry_mod;
}

/// QEMU uses the shared RISC-V linker script and _start symbol.
pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("isa/riscv/linker_common.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

fn qemuCpuForIsaName(isa_name: []const u8) []const u8 {
    // Only Zve32x needs explicit vector CPU config; others map to plain rv32.
    if (std.mem.eql(u8, isa_name, "rv32im_zve32x")) return "rv32,v=true,vlen=128";
    return "rv32";
}

/// Add run step for QEMU; isa_name is a string tag (e.g., "rv32imac").
pub fn addPlatformSteps(b: *std.Build, isa_name: ?[]const u8, exe: *std.Build.Step.Compile) void {
    const chosen_isa = isa_name orelse std.debug.panic("Missing required -Disa for platform=qemu", .{});

    const run_qemu = b.addSystemCommand(&.{
        "qemu-system-riscv32",
        "-machine",
        "virt",
        "-cpu",
        qemuCpuForIsaName(chosen_isa),
        "-m",
        "128M",
        "-nographic",
        "-serial",
        "mon:stdio",
        "-bios",
        "none",
        "-kernel",
    });
    run_qemu.addFileArg(exe.getEmittedBin());
    run_qemu.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_qemu.step);
}

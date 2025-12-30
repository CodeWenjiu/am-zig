const std = @import("std");

const Isa = @import("../build_impl.zig").Isa;
const isa_riscv_target = @import("../../isa/riscv/target.zig");

pub fn targetQuery(isa: Isa) std.Target.Query {
    var q = isa_riscv_target.riscv32BaseQuery();
    isa_riscv_target.applyIsaFeatures(&q, isa, .conservative);
    return q;
}

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

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("isa/riscv/linker_common.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

fn qemuCpuForIsa(isa: Isa) []const u8 {
    return switch (isa) {
        .rv32i => "rv32",
        .rv32im => "rv32",
        .rv32imac => "rv32",
        .rv32im_zve32x => "rv32,v=true,vlen=128",
    };
}

pub fn addPlatformSteps(b: *std.Build, isa: ?Isa, exe: *std.Build.Step.Compile) void {
    const chosen_isa = isa orelse @import("../build_impl.zig").missingOptionExit(Isa, "isa");

    const run_qemu = b.addSystemCommand(&.{
        "qemu-system-riscv32",
        "-machine",
        "virt",
        "-cpu",
        qemuCpuForIsa(chosen_isa),
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

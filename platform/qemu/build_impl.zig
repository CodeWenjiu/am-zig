const std = @import("std");

const Isa = @import("../build_impl.zig").Isa;

fn riscv32QueryBase() std.Target.Query {
    return .{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
    };
}

pub fn targetQuery(isa: Isa) std.Target.Query {
    var q = riscv32QueryBase();

    const F = std.Target.riscv.Feature;

    q.cpu_features_sub.addFeature(@intFromEnum(F.c));
    q.cpu_features_sub.addFeature(@intFromEnum(F.a));
    q.cpu_features_sub.addFeature(@intFromEnum(F.d));
    q.cpu_features_sub.addFeature(@intFromEnum(F.m));

    // i is part of all ISA variants we model here; baseline already has it.
    // Now selectively re-enable what the ISA explicitly includes.
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
        .root_source_file = b.path("platform/qemu/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);
    return entry_mod;
}

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("platform/qemu/riscv/linker.x"));
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

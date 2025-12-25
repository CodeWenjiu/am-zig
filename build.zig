const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const optimize = .ReleaseFast;

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/nemu/rv32i/start.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    entry_mod.addImport("app_logic", app_mod);

    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = entry_mod,
    });

    exe.setLinkerScript(b.path("platform/nemu/rv32i/linker.x"));

    exe.entry = .{ .symbol_name = "_start" };

    b.installArtifact(exe);

    const dump_cmd = b.addSystemCommand(&.{ "sh", "-c" });
    dump_cmd.addArg("objdump -d $1 > $2");
    dump_cmd.addArg("--");
    dump_cmd.addArtifactArg(exe);
    dump_cmd.addArg(b.getInstallPath(.bin, "kernel.asm"));

    const dump_step = b.step("dump", "Generate disassembly and save to kernel.asm");
    dump_step.dependOn(&dump_cmd.step);
}

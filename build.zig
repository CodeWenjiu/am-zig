const std = @import("std");

const Platform = enum {
    native,
    nemu,
};

pub fn build(b: *std.Build) void {
    const platform = b.option(Platform, "platform", "Select the platform") orelse .native;

    const optimize = .ReleaseFast;

    const target = switch (platform) {
        .native => b.standardTargetOptions(.{}),
        .nemu => b.resolveTargetQuery(.{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
        }),
    };

    const code_model: std.builtin.CodeModel = if (platform == .nemu) .medium else .default;

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = code_model,
    });

    const entry_src = switch (platform) {
        .native => b.path("platform/native/runtime.zig"),
        .nemu => b.path("platform/nemu/runtime.zig"),
    };

    const entry_mod = b.createModule(.{
        .root_source_file = entry_src,
        .target = target,
        .optimize = optimize,
        .code_model = code_model,
    });

    entry_mod.addImport("app", app_mod);

    const exe_name = if (platform == .nemu) "kernel" else "am-zig";
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = entry_mod,
    });

    switch (platform) {
        .nemu => {
            exe.setLinkerScript(b.path("platform/nemu/rv32i/linker.x"));
            exe.entry = .{ .symbol_name = "_start" };

            const objdump = b.addSystemCommand(&.{ "objdump", "-d" });
            objdump.addFileArg(exe.getEmittedBin());

            const dump_output = objdump.captureStdOut();

            const install_dump = b.addInstallFile(dump_output, "bin/kernel.asm");

            const dump_step = b.step("dump", "Generate disassembly and save to kernel.asm");
            dump_step.dependOn(b.getInstallStep());
            dump_step.dependOn(&install_dump.step);
        },
        .native => {
            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }
            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        },
    }

    b.installArtifact(exe);
}

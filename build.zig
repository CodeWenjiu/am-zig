const std = @import("std");

const lib = @import("platform/lib.zig");
const Platform = lib.Platform;
const Isa = lib.Isa;

pub fn build(b: *std.Build) void {
    const platform = optionOrExit(b, Platform, "platform", "Select the platform");
    const isa = optionOrExit(b, Isa, "isa", "Select the ISA");

    _ = isa;

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

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("platform/lib.zig"),
    });

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = code_model,
    });
    app_mod.addImport("platform_lib", lib_mod);

    const entry_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("platform/{s}/runtime.zig", .{@tagName(platform)})),
        .target = target,
        .optimize = optimize,
        .code_model = code_model,
    });

    entry_mod.addImport("app", app_mod);
    entry_mod.addImport("platform_lib", lib_mod);

    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = entry_mod,
    });

    switch (platform) {
        .nemu => {
            exe.setLinkerScript(b.path("platform/nemu/riscv/linker.x"));
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

fn optionOrExit(b: *std.Build, comptime T: type, name: []const u8, desc: []const u8) T {
    return b.option(T, name, desc) orelse {
        std.debug.print("Missing required argument: -D{s}=<{s}>\n", .{ name, name });
        std.debug.print("Available options: ", .{});
        const fields = @typeInfo(T).@"enum".fields;
        inline for (fields, 0..) |field, i| {
            std.debug.print("[{s}]", .{field.name});
            if (i < fields.len - 1) std.debug.print(" | ", .{});
        }
        std.debug.print("\n", .{});
        std.process.exit(1);
    };
}

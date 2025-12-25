const std = @import("std");

const lib = @import("platform/lib.zig");
const Platform = lib.Platform;
const Isa = lib.Isa;

pub fn build(b: *std.Build) void {
    const platform = optionOrExit(b, Platform, "platform", "Select the platform");

    const isa: ?Isa = b.option(Isa, "isa", "Select the ISA (required for non-native platforms; forbidden for native)");

    if (platform == .native) {
        forbidOption(Isa, "isa", isa, "native ISA is determined by the host");
    } else {
        _ = requireOptionOrExit(Isa, "isa", isa);
    }

    const optimize = .ReleaseFast;

    const target = switch (platform) {
        .native => b.standardTargetOptions(.{}),
        .nemu => b.resolveTargetQuery(.{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
        }),
    };

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("platform/lib.zig"),
    });

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_mod.addImport("platform_lib", lib_mod);

    const entry_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("platform/{s}/runtime.zig", .{@tagName(platform)})),
        .target = target,
        .optimize = optimize,
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
    return b.option(T, name, desc) orelse missingOptionExit(T, name);
}

fn requireOptionOrExit(comptime T: type, name: []const u8, value: ?T) T {
    return value orelse missingOptionExit(T, name);
}

fn forbidOption(comptime T: type, name: []const u8, value: ?T, reason: []const u8) void {
    if (value != null) {
        std.debug.print("Invalid argument: -D{s} is not allowed ({s})\n", .{ name, reason });
        std.process.exit(1);
    }
}

fn missingOptionExit(comptime T: type, name: []const u8) noreturn {
    std.debug.print("Missing required argument: -D{s}=<{s}>\n", .{ name, name });
    std.debug.print("Available options: ", .{});
    const fields = @typeInfo(T).@"enum".fields;
    inline for (fields, 0..) |field, i| {
        std.debug.print("[{s}]", .{field.name});
        if (i < fields.len - 1) std.debug.print(" | ", .{});
    }
    std.debug.print("\n", .{});
    std.process.exit(1);
}

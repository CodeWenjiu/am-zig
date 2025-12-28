const std = @import("std");

pub const Platform = enum {
    native,
    nemu,
    qemu,
    spike,

    pub fn resolvedTarget(self: Platform, b: *std.Build, isa: ?Isa) std.Build.ResolvedTarget {
        return switch (self) {
            .native => {
                if (isa) |_| {
                    std.debug.print("warning: -Disa with -Dplatform=native is ignored (native ISA is determined by the host)\n", .{});
                }
                return b.standardTargetOptions(.{});
            },
            else => {
                const chosen_isa = isa orelse missingOptionExit(Isa, "isa");
                return b.resolveTargetQuery(self.targetQuery(chosen_isa));
            },
        };
    }

    pub fn targetQuery(self: Platform, isa: Isa) std.Target.Query {
        return switch (self) {
            .native => native_target.targetQuery(isa),
            .nemu => nemu_target.targetQuery(isa),
            .qemu => qemu_target.targetQuery(isa),
            .spike => spike_target.targetQuery(isa),
        };
    }

    pub fn entryModule(
        self: Platform,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        app_mod: *std.Build.Module,
    ) *std.Build.Module {
        const entry_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("platform/{s}/runtime.zig", .{@tagName(self)})),
            .target = target,
            .optimize = optimize,
        });
        entry_mod.addImport("app", app_mod);
        return entry_mod;
    }

    pub fn configureExecutable(self: Platform, b: *std.Build, exe: *std.Build.Step.Compile) void {
        switch (self) {
            .nemu => {
                exe.setLinkerScript(b.path("platform/nemu/riscv/linker.x"));
                exe.entry = .{ .symbol_name = "_start" };
            },
            .native => {},
            .qemu => {},
            .spike => {},
        }
    }

    pub fn addPlatformSteps(self: Platform, b: *std.Build, exe: *std.Build.Step.Compile) void {
        switch (self) {
            .nemu => {
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
            .qemu => {},
            .spike => {},
        }
    }
};

pub const IsaFamily = enum {
    riscv,
};

pub const Isa = enum {
    rv32i,

    pub fn getFamily(self: Isa) IsaFamily {
        return switch (self) {
            .rv32i => .riscv,
        };
    }
};

pub fn missingOptionExit(comptime T: type, name: []const u8) noreturn {
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

const native_target = @import("native/target.zig");
const nemu_target = @import("nemu/target.zig");
const qemu_target = @import("qemu/target.zig");
const spike_target = @import("spike/target.zig");

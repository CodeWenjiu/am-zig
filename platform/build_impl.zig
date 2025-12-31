const std = @import("std");

pub const Platform = enum {
    native,
    nemu,
    qemu,
    spike,

    const Impl = struct {
        tag: Platform,
        module: type,
    };

    const impls = [_]Impl{
        .{ .tag = .native, .module = native_build },
        .{ .tag = .nemu, .module = nemu_build },
        .{ .tag = .qemu, .module = qemu_build },
        .{ .tag = .spike, .module = spike_build },
    };

    fn withImpl(self: Platform, comptime Ret: type, ctx: anytype, comptime f: anytype) Ret {
        inline for (impls) |x| {
            if (self == x.tag) return f(x.module, ctx);
        }
        unreachable;
    }

    pub fn entryModule(
        self: Platform,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        app_mod: *std.Build.Module,
    ) *std.Build.Module {
        const Ctx = struct {
            b: *std.Build,
            target: std.Build.ResolvedTarget,
            optimize: std.builtin.OptimizeMode,
            app_mod: *std.Build.Module,
        };
        const ctx: Ctx = .{ .b = b, .target = target, .optimize = optimize, .app_mod = app_mod };

        return self.withImpl(*std.Build.Module, ctx, struct {
            fn call(comptime M: type, c: Ctx) *std.Build.Module {
                return M.entryModule(c.b, c.target, c.optimize, c.app_mod);
            }
        }.call);
    }

    pub fn configureExecutable(self: Platform, b: *std.Build, exe: *std.Build.Step.Compile) void {
        const Ctx = struct { b: *std.Build, exe: *std.Build.Step.Compile };
        const ctx: Ctx = .{ .b = b, .exe = exe };

        return self.withImpl(void, ctx, struct {
            fn call(comptime M: type, c: Ctx) void {
                return M.configureExecutable(c.b, c.exe);
            }
        }.call);
    }

    pub fn addPlatformSteps(
        self: Platform,
        b: *std.Build,
        feature_profile: ?[]const u8,
        exe_base_name: []const u8,
        exe: *std.Build.Step.Compile,
    ) void {
        const objdump = b.addSystemCommand(&.{ "objdump", "-d" });
        objdump.addFileArg(exe.getEmittedBin());

        const dump_output = objdump.captureStdOut();

        // Name outputs as: <bin-name>-<isa>.asm
        // - bin-name: exe_base_name (computed in build.zig; should already include canonical ISA id)
        // - isa: no longer derived here; platform layer should stay ISA-agnostic
        const asm_name = b.fmt("{s}.asm", .{exe_base_name});

        const install_dump = b.addInstallFile(dump_output, b.pathJoin(&.{ @tagName(self), asm_name }));

        const dump_step = b.step(
            b.fmt("dump-{s}", .{@tagName(self)}),
            b.fmt("Generate disassembly and save to {s}", .{asm_name}),
        );
        dump_step.dependOn(b.getInstallStep());
        dump_step.dependOn(&install_dump.step);

        const dump = b.step("dump", b.fmt("Generate disassembly and save to {s}", .{asm_name}));
        dump.dependOn(dump_step);

        const Ctx = struct {
            b: *std.Build,
            feature_profile: ?[]const u8,
            exe_base_name: []const u8,
            exe: *std.Build.Step.Compile,
            dump_step: *std.Build.Step,
        };
        const ctx: Ctx = .{
            .b = b,
            .feature_profile = feature_profile,
            .exe_base_name = exe_base_name,
            .exe = exe,
            .dump_step = dump_step,
        };

        return self.withImpl(void, ctx, struct {
            fn call(comptime M: type, c: Ctx) void {
                // Make dump a prerequisite of run (and any other platform-specific steps).
                // This ensures the disassembly is always produced when you run.
                M.addPlatformSteps(c.b, c.feature_profile, c.exe_base_name, c.exe);

                const run_top = c.b.top_level_steps.get("run") orelse return;
                run_top.step.dependOn(c.dump_step);
            }
        }.call);
    }
};

pub fn attachCommonArgv(
    b: *std.Build,
    entry_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    arg: []const u8,
    exe_name: []const u8,
) void {
    // Expose build options (arg string and executable name) to runtimes.
    const opts = b.addOptions();
    opts.addOption([]const u8, "arg", arg);
    opts.addOption([]const u8, "exe_name", exe_name);
    entry_mod.addOptions("build_options", opts);

    // Expose shared argv utilities as a package named "argv".
    const argv_pkg = b.createModule(.{
        .root_source_file = b.path("platform/argv.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("argv", argv_pkg);
}

const native_build = @import("native/build_impl.zig");
const nemu_build = @import("nemu/build_impl.zig");
const qemu_build = @import("qemu/build_impl.zig");
const spike_build = @import("spike/build_impl.zig");

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

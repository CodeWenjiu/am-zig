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

    pub fn resolvedTarget(self: Platform, b: *std.Build, isa: ?Isa) std.Build.ResolvedTarget {
        if (self != .native) {
            const chosen_isa = isa orelse missingOptionExit(Isa, "isa");
            return b.resolveTargetQuery(self.targetQuery(chosen_isa));
        }

        return native_build.resolvedTarget(b, isa);
    }

    pub fn targetQuery(self: Platform, isa: Isa) std.Target.Query {
        const Ctx = struct { isa: Isa };
        const ctx: Ctx = .{ .isa = isa };

        return self.withImpl(std.Target.Query, ctx, struct {
            fn call(comptime M: type, c: Ctx) std.Target.Query {
                return M.targetQuery(Isa, c.isa);
            }
        }.call);
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

    pub fn addPlatformSteps(self: Platform, b: *std.Build, exe: *std.Build.Step.Compile) void {
        const Ctx = struct { b: *std.Build, exe: *std.Build.Step.Compile };
        const ctx: Ctx = .{ .b = b, .exe = exe };

        return self.withImpl(void, ctx, struct {
            fn call(comptime M: type, c: Ctx) void {
                return M.addPlatformSteps(c.b, c.exe);
            }
        }.call);
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

pub const build = @import("build_impl.zig");
pub const missingOptionExit = build.missingOptionExit;

const native_build = @import("native/build_impl.zig");
const nemu_build = @import("nemu/build_impl.zig");
const qemu_build = @import("qemu/build_impl.zig");
const spike_build = @import("spike/build_impl.zig");

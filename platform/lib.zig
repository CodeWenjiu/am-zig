const std = @import("std");

pub const Platform = enum {
    native,
    nemu,
    qemu,
    spike,

    pub fn resolvedTarget(self: Platform, b: *std.Build, isa: ?Isa) std.Build.ResolvedTarget {
        return switch (self) {
            .native => native_build.resolvedTarget(b, isa),
            else => {
                const chosen_isa = isa orelse missingOptionExit(Isa, "isa");
                return b.resolveTargetQuery(self.targetQuery(chosen_isa));
            },
        };
    }

    pub fn targetQuery(self: Platform, isa: Isa) std.Target.Query {
        return switch (self) {
            .native => native_build.targetQuery(isa),
            .nemu => nemu_build.targetQuery(Isa, isa),
            .qemu => qemu_build.targetQuery(Isa, isa),
            .spike => spike_build.targetQuery(Isa, isa),
        };
    }

    pub fn entryModule(
        self: Platform,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        app_mod: *std.Build.Module,
    ) *std.Build.Module {
        const entry_mod = switch (self) {
            .native => native_build.entryModule(b, target, optimize, app_mod),
            .nemu => nemu_build.entryModule(b, target, optimize, app_mod),
            .qemu => qemu_build.entryModule(b, target, optimize, app_mod),
            .spike => spike_build.entryModule(b, target, optimize, app_mod),
        };
        return entry_mod;
    }

    pub fn configureExecutable(self: Platform, b: *std.Build, exe: *std.Build.Step.Compile) void {
        return switch (self) {
            .native => native_build.configureExecutable(b, exe),
            .nemu => nemu_build.configureExecutable(b, exe),
            .qemu => qemu_build.configureExecutable(b, exe),
            .spike => spike_build.configureExecutable(b, exe),
        };
    }

    pub fn addPlatformSteps(self: Platform, b: *std.Build, exe: *std.Build.Step.Compile) void {
        return switch (self) {
            .native => native_build.addPlatformSteps(b, exe),
            .nemu => nemu_build.addPlatformSteps(b, exe),
            .qemu => qemu_build.addPlatformSteps(b, exe),
            .spike => spike_build.addPlatformSteps(b, exe),
        };
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

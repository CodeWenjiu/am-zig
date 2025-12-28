const std = @import("std");

const Isa = @import("../build_impl.zig").Isa;

pub fn resolvedTarget(b: *std.Build, isa: ?Isa) std.Build.ResolvedTarget {
    if (isa) |_| {
        std.debug.print("warning: -Disa with -Dplatform=native is ignored (native ISA is determined by the host)\n", .{});
    }
    return b.standardTargetOptions(.{});
}

pub fn targetQuery(isa: Isa) std.Target.Query {
    _ = isa;
    return .{};
}

pub fn entryModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/native/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);
    return entry_mod;
}

pub fn configureExecutable(_: *std.Build, _: *std.Build.Step.Compile) void {}

pub fn addPlatformSteps(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

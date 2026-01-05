const std = @import("std");

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

pub fn addPlatformSteps(
    b: *std.Build,
    feature_profile: ?[]const u8,
    exe_base_name: []const u8,
    exe: *std.Build.Step.Compile,
) void {
    _ = feature_profile;
    _ = exe_base_name;

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const std = @import("std");

const platform_lib = @import("platform/build_impl.zig");
const Platform = platform_lib.Platform;
const Isa = platform_lib.Isa;

pub fn build(b: *std.Build) void {
    const platform = b.option(Platform, "platform", "Select the platform") orelse platform_lib.missingOptionExit(Platform, "platform");
    const isa: ?Isa = b.option(Isa, "isa", "Select the ISA (required for non-native platforms; forbidden for native)");
    const bin = b.option([]const u8, "bin", "Select the binary under bin/<name>/main.zig") orelse {
        std.debug.print("Missing required argument: -Dbin=<name>\n", .{});
        std.process.exit(1);
    };
    const arg = b.option([]const u8, "arg", "Optional argument string passed to bare-metal runtime via build options (space-delimited)");

    const target = platform.resolvedTarget(b, isa);

    const optimize = .ReleaseFast;

    const app_mod = b.createModule(.{
        .root_source_file = b.path(b.pathJoin(&.{ "bin", bin, "main.zig" })),
        .target = target,
        .optimize = optimize,
    });

    const entry_mod = platform.entryModule(b, target, optimize, app_mod);


    const exe_name = bin;

    platform_lib.attachCommonArgv(b, entry_mod, target, optimize, arg orelse "", exe_name);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = entry_mod,
    });


    platform.configureExecutable(b, exe);
    platform.addPlatformSteps(b, isa, exe);

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = @tagName(platform) } },
    });
    b.getInstallStep().dependOn(&install_exe.step);
}

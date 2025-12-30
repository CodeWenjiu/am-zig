const std = @import("std");

const platform_lib = @import("platform/build_impl.zig");
const isa_dispatch = @import("isa/build_impl.zig");

const Platform = platform_lib.Platform;

pub fn build(b: *std.Build) void {
    const platform = b.option(Platform, "platform", "Select the platform") orelse platform_lib.missingOptionExit(Platform, "platform");
    const arch_opt = b.option(std.Target.Cpu.Arch, "target", "Select CPU architecture (required for non-native, e.g. riscv32)");
    const feature_opt = b.option([]const u8, "feature", "Optional feature flags without arch prefix (e.g. mac, imac, im_zve32x); defaults per arch");
    const bin = b.option([]const u8, "bin", "Select the binary under bin/<name>/main.zig") orelse {
        std.debug.print("Missing required argument: -Dbin=<name>\n", .{});
        std.process.exit(1);
    };
    const arg = b.option([]const u8, "arg", "Optional argument string passed to bare-metal runtime via build options (space-delimited)");

    const is_native = platform == .native;

    if (is_native) {
        if (arch_opt != null) {
            std.debug.print("warning: -Dtarget is ignored for platform=native (host target is used)\n", .{});
        }
        if (feature_opt != null) {
            std.debug.print("warning: -Dfeature is ignored for platform=native (host features are used)\n", .{});
        }
    }

    const resolved = if (is_native)
        isa_dispatch.ResolvedTarget{ .query = .{}, .feature_profile = null }
    else
        isa_dispatch.resolveNonNativeTarget(arch_opt, feature_opt, b.allocator) catch std.process.exit(1);

    const target = b.resolveTargetQuery(resolved.query);
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
    platform.addPlatformSteps(b, resolved.feature_profile, exe);

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = @tagName(platform) } },
    });
    b.getInstallStep().dependOn(&install_exe.step);
}


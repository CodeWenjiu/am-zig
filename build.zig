const std = @import("std");

const platform_lib = @import("platform/dispatch/platform.zig");
const isa_dispatch = @import("isa/dispatch.zig");

const Platform = platform_lib.Platform;

pub fn build(b: *std.Build) void {
    const platform = b.option(Platform, "platform", "Select the platform") orelse
        platform_lib.missingOptionExit(Platform, "platform");

    const arch_opt = b.option(
        std.Target.Cpu.Arch,
        "target",
        "Select CPU architecture (required for non-native, e.g. riscv32)",
    );
    const feature_opt = b.option(
        []const u8,
        "feature",
        "Optional feature flags without arch prefix (e.g. mac, imac, im_zve32x); defaults per arch",
    );
    const bin = b.option(
        []const u8,
        "bin",
        "Select the binary under bin/<name>/main.zig",
    ) orelse platform_lib.missingArgExit("bin", "name");
    const arg = b.option(
        []const u8,
        "arg",
        "Optional argument string passed to bare-metal runtime via build options (space-delimited)",
    );

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
        isa_dispatch.resolveNonNativeTarget(arch_opt, feature_opt, b.allocator) catch |e| {
            switch (e) {
                error.MissingTarget => {
                    std.debug.print("Missing required argument: -Dtarget=<arch>\n", .{});
                },
                error.UnknownFeature => {
                    const arch = arch_opt orelse unreachable;
                    const profile_flags = isa_dispatch.resolveFeatureProfileString(arch, feature_opt);
                    const hint = isa_dispatch.formatSupportedProfiles(arch);
                    std.debug.print(
                        "Unknown feature flag(s) in: {s}\nSupported format: {s}\n",
                        .{ profile_flags, hint },
                    );
                },
                error.UnsupportedArch => {
                    const arch = arch_opt orelse unreachable;
                    std.debug.print("Unsupported architecture: {s}\n", .{@tagName(arch)});
                },
                error.OutOfMemory => {
                    std.debug.print("Out of memory while resolving target\n", .{});
                },
            }
            std.process.exit(1);
        };

    const target = b.resolveTargetQuery(resolved.query);
    const optimize = .ReleaseFast;

    const app_mod = b.createModule(.{
        .root_source_file = b.path(b.pathJoin(&.{ "bin", bin, "main.zig" })),
        .target = target,
        .optimize = optimize,
    });

    const entry_mod = platform.entryModule(b, resolved.feature_profile, target, optimize, app_mod);

    // Inject ISA-selected start shim into the entry module.
    //
    // ISA owns the semantics of feature profiles (via ProfileInfo); the selected
    // start shim is provided as an import named `isa_riscv_start`.
    //
    // Platform remains responsible for validating platform support for the chosen
    // ISA/profile combo (e.g. nemu may reject vector profiles).
    if (!is_native) {
        const arch = arch_opt orelse unreachable;

        const start_path = isa_dispatch.startShimPathFor(b.allocator, arch, resolved.feature_profile) catch |e| {
            switch (e) {
                error.UnknownFeature => {
                    const profile_flags = isa_dispatch.resolveFeatureProfileString(arch, feature_opt);
                    const hint = isa_dispatch.formatSupportedProfiles(arch);
                    std.debug.print(
                        "Unknown feature flag(s) in: {s}\nSupported format: {s}\n",
                        .{ profile_flags, hint },
                    );
                },
                error.UnsupportedArch => {
                    std.debug.print("Unsupported architecture: {s}\n", .{@tagName(arch)});
                },
                error.OutOfMemory => {
                    std.debug.print("Out of memory while selecting ISA start shim\n", .{});
                },
                error.MissingTarget => unreachable,
            }
            std.process.exit(1);
        };

        const isa_start_mod = b.createModule(.{
            .root_source_file = b.path(start_path),
            .target = target,
            .optimize = optimize,
        });
        entry_mod.addImport("isa_riscv_start", isa_start_mod);
    }

    // Canonical ISA id for artifact naming:
    // - Non-native: "<arch>-<sorted_unique_features>"
    // - Native: "native"
    const isa_suffix = blk: {
        if (is_native) break :blk "native";

        const arch = arch_opt orelse unreachable;
        const profile_flags = isa_dispatch.resolveFeatureProfileString(arch, feature_opt);

        break :blk isa_dispatch.formatCanonicalIsaId(b.allocator, arch, profile_flags) catch |e| {
            switch (e) {
                error.UnknownFeature => {
                    const hint = isa_dispatch.formatSupportedProfiles(arch);
                    std.debug.print(
                        "Unknown feature flag(s) in: {s}\nSupported format: {s}\n",
                        .{ profile_flags, hint },
                    );
                },
                error.UnsupportedArch => {
                    std.debug.print("Unsupported architecture: {s}\n", .{@tagName(arch)});
                },
                error.OutOfMemory => {
                    std.debug.print("Out of memory while formatting ISA name\n", .{});
                },
                error.MissingTarget => unreachable,
            }
            std.process.exit(1);
        };
    };

    const exe_name = b.fmt("{s}-{s}", .{ bin, isa_suffix });

    platform_lib.attachCommonArgv(b, entry_mod, target, optimize, arg orelse "", exe_name);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = entry_mod,
    });

    platform.configureExecutable(b, exe);
    platform.addPlatformSteps(b, resolved.feature_profile, exe_name, exe);

    const install_exe = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = @tagName(platform) } },
    });
    b.getInstallStep().dependOn(&install_exe.step);
}

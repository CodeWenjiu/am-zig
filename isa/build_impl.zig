const std = @import("std");
const riscv = @import("riscv/target.zig");

pub const RiscvStripPreset = riscv.StripPreset;

pub const defaultProfileName = riscv.defaultProfileName;
pub const supportedProfileNames = riscv.supportedProfileNames;
pub const formatSupportedProfiles = riscv.formatSupportedProfiles;

pub const TargetQueryError = error{
    UnsupportedArch,
    UnknownFeature,
};

pub fn targetQueryFromProfile(
    profile_string: []const u8,
    arch: std.Target.Cpu.Arch,
    allocator: std.mem.Allocator,
    strip: ?RiscvStripPreset,
) TargetQueryError!std.Target.Query {
    const tags = riscv.parseFeatureTags(allocator, profile_string) catch |e| switch (e) {
        error.UnknownFeature => return TargetQueryError.UnknownFeature,
        error.OutOfMemory => return TargetQueryError.UnknownFeature,
    };
    defer allocator.free(tags);

    return targetQuery(arch, tags, strip);
}

pub fn targetQuery(
    arch: std.Target.Cpu.Arch,
    features: []const []const u8,
    strip: ?RiscvStripPreset,
) TargetQueryError!std.Target.Query {
    return switch (arch) {
        .riscv32 => riscvQuery(arch, features, strip orelse .none),
        else => TargetQueryError.UnsupportedArch,
    };
}

fn riscvQuery(
    arch: std.Target.Cpu.Arch,
    features: []const []const u8,
    strip: RiscvStripPreset,
) TargetQueryError!std.Target.Query {
    var q = riscv.riscv32BaseQuery();
    riscv.applyFeatures(&q, arch, features, strip) catch |e| switch (e) {
        error.UnknownFeature => return TargetQueryError.UnknownFeature,
    };
    return q;
}

pub const ResolvedTarget = struct {
    query: std.Target.Query,
    feature_profile: ?[]const u8,
};

pub fn resolveNonNativeTarget(
    arch_opt: ?std.Target.Cpu.Arch,
    feature_opt: ?[]const u8,
    allocator: std.mem.Allocator,
) TargetQueryError!ResolvedTarget {
    const arch = arch_opt orelse {
        std.debug.print("Missing required argument: -Dtarget=<arch>\n", .{});
        std.process.exit(1);
    };

    const profile_flags = if (feature_opt) |flags|
        if (flags.len != 0) flags else defaultProfileName(arch)
    else
        defaultProfileName(arch);

    const query = targetQueryFromProfile(profile_flags, arch, allocator, .none) catch |e| {
        switch (e) {
            error.UnknownFeature => {
                const hint = formatSupportedProfiles(allocator);
                std.debug.print("Unknown feature flag(s) in: {s}\nSupported format: {s}\n", .{ profile_flags, hint });
            },
            error.UnsupportedArch => {
                std.debug.print("Unsupported architecture: {s}\n", .{@tagName(arch)});
            },
        }
        std.process.exit(1);
    };

    return ResolvedTarget{
        .query = query,
        .feature_profile = profile_flags,
    };
}

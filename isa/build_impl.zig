const std = @import("std");
const riscv = @import("riscv/target.zig");

pub const RiscvStripPreset = riscv.StripPreset;

pub const defaultProfileName = riscv.defaultProfileName;
pub const supportedProfileNames = riscv.supportedProfileNames;
pub const formatSupportedProfiles = riscv.formatSupportedProfiles;

pub const TargetQueryError = error{
    /// The requested architecture isn't supported by this ISA layer.
    UnsupportedArch,
    /// Feature profile contained an unknown/unsupported feature tag.
    UnknownFeature,
    /// Allocation failed while parsing/processing the feature profile.
    OutOfMemory,
    /// Missing required argument for non-native builds.
    MissingTarget,
};

/// Compute the feature profile string to use, given an architecture and an optional user-provided
/// feature flag string.
///
/// Behavior is kept consistent with the build CLI:
/// - If `feature_opt` is null, use the arch default profile name.
/// - If `feature_opt` is an empty string, treat it as "use default".
/// - Otherwise, use the provided string as-is.
pub fn resolveFeatureProfileString(arch: std.Target.Cpu.Arch, feature_opt: ?[]const u8) []const u8 {
    return if (feature_opt) |flags|
        if (flags.len != 0) flags else defaultProfileName(arch)
    else
        defaultProfileName(arch);
}

pub fn targetQueryFromProfile(
    profile_string: []const u8,
    arch: std.Target.Cpu.Arch,
    allocator: std.mem.Allocator,
    strip: ?RiscvStripPreset,
) TargetQueryError!std.Target.Query {
    const tags = riscv.parseFeatureTags(allocator, profile_string) catch |e| switch (e) {
        error.UnknownFeature => return TargetQueryError.UnknownFeature,
        error.OutOfMemory => return TargetQueryError.OutOfMemory,
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
    const arch = arch_opt orelse return TargetQueryError.MissingTarget;

    const profile_flags = resolveFeatureProfileString(arch, feature_opt);

    const query = try targetQueryFromProfile(profile_flags, arch, allocator, .none);

    return ResolvedTarget{
        .query = query,
        .feature_profile = profile_flags,
    };
}

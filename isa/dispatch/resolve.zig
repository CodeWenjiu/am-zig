const std = @import("std");

const query_mod = @import("query.zig");
const riscv_family = @import("../riscv/family.zig");

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

pub const ResolvedTarget = struct {
    query: std.Target.Query,
    /// The original (or defaulted) feature profile string used for non-native builds.
    /// This is kept for platform configuration and artifact naming.
    feature_profile: ?[]const u8,
};

/// Strip preset type used by the ISA-agnostic query module.
/// (Currently meaningful for RISC-V only.)
pub const StripPreset = query_mod.StripPreset;

/// Default profile name for an architecture (used when `-Dfeature` is missing/empty).
///
/// This is ISA-agnostic: it routes by `arch` to the appropriate ISA-family module.
pub fn defaultProfileName(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => riscv_family.defaultProfileName(arch) catch "unknown",
        else => "unknown",
    };
}

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

/// Resolve a non-native target using the CLI options.
///
/// Behavior:
/// - Requires `arch_opt` (missing => `error.MissingTarget`)
/// - Computes the feature profile string (`resolveFeatureProfileString`)
/// - Produces a `std.Target.Query` with applied features
///
/// Notes:
/// - Delegates Target.Query construction to `dispatch/query.zig` to avoid duplicating ISA family logic.
/// - `dispatch/query.zig` uses the shared `TargetQueryError` type, so no error mapping is needed here.
pub fn resolveNonNativeTarget(
    arch_opt: ?std.Target.Cpu.Arch,
    feature_opt: ?[]const u8,
    allocator: std.mem.Allocator,
) TargetQueryError!ResolvedTarget {
    const arch = arch_opt orelse return TargetQueryError.MissingTarget;

    const profile_flags = resolveFeatureProfileString(arch, feature_opt);

    const query = try query_mod.targetQueryFromProfile(allocator, arch, profile_flags, null);

    return .{
        .query = query,
        .feature_profile = profile_flags,
    };
}

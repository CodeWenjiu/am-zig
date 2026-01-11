const std = @import("std");

const naming = @import("naming.zig");
const ux = @import("ux.zig");
const riscv_family = @import("riscv/family.zig");

/// NOTE:
/// Runner configuration types are owned by `platform/dispatch/platform.zig` (platform dispatch),
/// not by ISA dispatch.
///
/// Rationale:
/// - Platform runners (qemu/spike/...) are implemented under `platform/*/build.zig` and can
///   reliably import platform dispatch types.
/// - Importing ISA dispatch types from platform build modules is fragile in build-context due to
///   differing import roots.
/// - Keeping `RunnerConfig` unified avoids type-mismatch issues across modules.

// Submodules (responsibility split)
pub const resolve = @import("dispatch/resolve.zig");
pub const query = @import("dispatch/query.zig");

// -------------------------
// Public surface (re-exports)
// -------------------------

// Strip preset type used by query construction.
// Note: today this is only meaningful for RISC-V, but the surface is ISA-agnostic.
pub const StripPreset = query.StripPreset;

// Help/UX helpers (static, allocator-free).
pub const defaultProfileName = resolve.defaultProfileName;
pub fn supportedProfileNames(arch: std.Target.Cpu.Arch) []const []const u8 {
    return ux.supportedProfileNames(arch);
}
pub fn formatSupportedProfiles(arch: std.Target.Cpu.Arch) []const u8 {
    return ux.formatSupportedProfiles(arch);
}

// Resolution types & errors.
pub const ResolvedTarget = resolve.ResolvedTarget;
pub const TargetQueryError = resolve.TargetQueryError;

// Resolution helpers.
pub const resolveFeatureProfileString = resolve.resolveFeatureProfileString;
pub const resolveNonNativeTarget = resolve.resolveNonNativeTarget;

// Query helpers (for callers that want direct access).
pub const QueryError = query.Error;
pub const targetQueryFromProfile = query.targetQueryFromProfile;
pub const targetQueryFromTags = query.targetQueryFromTags;

/// Select the ISA start shim source path for the given arch + resolved feature profile.
///
/// Contract:
/// - ISA decides *how to interpret* the feature profile (ProfileInfo semantics).
/// - Platform remains responsible for deciding whether the chosen ISA/profile combination is
///   supported (e.g. nemu may reject vectors), and for reporting errors accordingly.
///
/// Today this only has meaning for RISC-V; other arches return the default path.
pub fn startShimPathFor(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    feature_profile: ?[]const u8,
) TargetQueryError![]const u8 {
    // Default: use the minimal start shim.
    const default_path = "isa/riscv/start.zig";

    // No profile => default start shim.
    const profile = feature_profile orelse return default_path;

    return switch (arch) {
        .riscv32, .riscv64 => blk: {
            const info = riscv_family.parseProfileInfo(allocator, arch, profile) catch |e| switch (e) {
                error.UnsupportedArch => return TargetQueryError.UnsupportedArch,
                error.UnknownFeature => return TargetQueryError.UnknownFeature,
                error.OutOfMemory => return TargetQueryError.OutOfMemory,
                // Treat DuplicateZvl as "unknown feature/profile invalid" at this layer.
                error.DuplicateZvl => return TargetQueryError.UnknownFeature,
            };
            defer info.deinit(allocator);

            if (info.has_vector) break :blk "isa/riscv/start_vector.zig";
            break :blk default_path;
        },
        else => default_path,
    };
}

// Naming helpers.
pub fn formatCanonicalIsaId(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    feature_profile: []const u8,
) TargetQueryError![]const u8 {
    // Parse feature tags via ISA-family module (currently RISC-V), then use ISA-agnostic naming.
    switch (arch) {
        .riscv32, .riscv64 => {
            const parsed = riscv_family.parseFeatureTags(allocator, arch, feature_profile) catch |e| switch (e) {
                error.UnsupportedArch => return TargetQueryError.UnsupportedArch,
                error.UnknownFeature => return TargetQueryError.UnknownFeature,
                error.OutOfMemory => return TargetQueryError.OutOfMemory,
            };
            defer allocator.free(parsed);

            const tags: []const []const u8 = if (parsed.len != 0)
                parsed
            else
                (riscv_family.defaultFeatureTags(arch) catch &.{});

            return naming.formatCanonicalIsaIdFromTags(allocator, arch, tags) catch |e| switch (e) {
                error.UnsupportedArch => return TargetQueryError.UnsupportedArch,
                error.UnknownFeature => return TargetQueryError.UnknownFeature,
                error.OutOfMemory => return TargetQueryError.OutOfMemory,
            };
        },
        else => return TargetQueryError.UnsupportedArch,
    }
}

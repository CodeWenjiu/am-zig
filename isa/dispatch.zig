const std = @import("std");

const naming = @import("naming.zig");
const ux = @import("ux.zig");
const riscv_family = @import("riscv/family.zig");

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

const std = @import("std");

const target = @import("target.zig");
const ux = @import("ux.zig");

/// RISC-V ISA-family facade.
///
/// This module exposes a stable, family-scoped interface that ISA-agnostic layers
/// (e.g. `isa/dispatch/*`, `isa/ux.zig`) can call via `switch (arch)` without
/// importing family internals directly.
///
/// Design goals:
/// - Keep parsing / Target.Query construction here (family-specific).
/// - Keep UX/help text here (family-specific).
/// - Keep allocation behavior explicit (allocator in/out).
/// - Avoid any CLI behavior (no printing / no exiting).
///
/// Note:
/// - The project currently uses RISC-V primarily for riscv32; riscv64 is supported
///   for parsing/UX defaults but Query construction may be extended as needed.
pub const StripPreset = target.StripPreset;

/// Profile info types for downstream consumers (e.g. platforms that need runtime CPU config).
pub const ProfileInfo = target.ProfileInfo;
pub const ProfileInfoError = target.ProfileInfoError;

/// Errors surfaced by RISC-V family operations.
pub const Error = error{
    UnsupportedArch,
    UnknownFeature,
    OutOfMemory,
};

/// Return a sensible default profile name for the given arch.
///
/// This is used when `-Dfeature` is absent or empty.
pub fn defaultProfileName(arch: std.Target.Cpu.Arch) Error![]const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => target.defaultProfileName(arch),
        else => Error.UnsupportedArch,
    };
}

/// Return default feature tags for the given arch.
///
/// This is used when the parsed profile contains no tags.
pub fn defaultFeatureTags(arch: std.Target.Cpu.Arch) Error![]const []const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => target.defaultFeatureTags(arch),
        else => Error.UnsupportedArch,
    };
}

/// Parse a raw profile string (e.g. "imac", "im_zve32x") into feature tags.
///
/// Contract:
/// - Returns an allocator-owned slice of valid tags for the given arch.
/// - Unknown features return `error.UnknownFeature`.
/// - Unsupported arch returns `error.UnsupportedArch`.
/// - Allocation failures return `error.OutOfMemory`.
pub fn parseFeatureTags(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    profile: []const u8,
) Error![]const []const u8 {
    switch (arch) {
        .riscv32, .riscv64 => {},
        else => return Error.UnsupportedArch,
    }

    const tags = target.parseFeatureTags(allocator, profile) catch |e| switch (e) {
        error.UnknownFeature => return Error.UnknownFeature,
        error.OutOfMemory => return Error.OutOfMemory,
    };
    return tags;
}

/// Parse a raw profile string into structured info needed by platform runners.
///
/// This keeps profile semantics (e.g. "duplicate zvl is invalid") within the ISA family.
pub fn parseProfileInfo(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    profile: []const u8,
) ProfileInfoError!ProfileInfo {
    switch (arch) {
        .riscv32, .riscv64 => {},
        else => return ProfileInfoError.UnsupportedArch,
    }

    return target.parseProfileInfo(allocator, profile);
}

/// Build a Target.Query from a profile string.
///
/// This is the family-owned implementation of "profile string -> Query" used by
/// ISA-agnostic dispatch code.
pub fn targetQueryFromProfile(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    profile: []const u8,
    strip: ?StripPreset,
) Error!std.Target.Query {
    // Parse tags first (allocator-owned).
    const tags = try parseFeatureTags(allocator, arch, profile);
    defer allocator.free(tags);

    const effective_tags: []const []const u8 = if (tags.len != 0) tags else try defaultFeatureTags(arch);

    return targetQueryFromTags(arch, effective_tags, strip);
}

/// Build a Target.Query from already-parsed tags.
///
/// `features` should be valid RISC-V tags (single-letter or known multi-letter extensions).
/// Ordering does not matter; duplicates are tolerated (but discouraged).
pub fn targetQueryFromTags(
    arch: std.Target.Cpu.Arch,
    features: []const []const u8,
    strip: ?StripPreset,
) Error!std.Target.Query {
    return switch (arch) {
        .riscv32 => blk: {
            var q = target.riscv32BaseQuery();
            target.applyFeatures(&q, arch, features, strip orelse .none) catch |e| switch (e) {
                error.UnknownFeature => return Error.UnknownFeature,
            };
            break :blk q;
        },
        // Extend when you add riscv64 freestanding targets and models.
        .riscv64 => Error.UnsupportedArch,
        else => Error.UnsupportedArch,
    };
}

/// Family-specific help text for -Dfeature formatting.
pub fn formatSupportedProfiles(arch: std.Target.Cpu.Arch) Error![]const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => ux.formatSupportedProfiles(),
        else => Error.UnsupportedArch,
    };
}

/// Family-specific list of named/alias profiles (may be empty).
pub fn supportedProfileNames(arch: std.Target.Cpu.Arch) Error![]const []const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => ux.supportedProfileNames(),
        else => Error.UnsupportedArch,
    };
}

const std = @import("std");
const riscv = @import("riscv/target.zig");

pub const RiscvStripPreset = riscv.StripPreset;

pub const defaultProfileName = riscv.defaultProfileName;

// These no longer take an allocator; they return static data.
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

pub fn resolveFeatureProfileString(arch: std.Target.Cpu.Arch, feature_opt: ?[]const u8) []const u8 {
    return if (feature_opt) |flags|
        if (flags.len != 0) flags else defaultProfileName(arch)
    else
        defaultProfileName(arch);
}

/// Format a canonical ISA id used for naming outputs.
///
/// Contract:
/// - Non-native: "<arch>-<features>".
/// - Feature tags are parsed (deduplicated by parser), then rendered in a canonical form:
///   - Single-letter extensions (len==1) come first and are ordered in a traditional RISC-V-friendly
///     priority (e.g. "imac" instead of "acim").
///   - Multi-letter extensions (len>1) follow, sorted lexicographically and joined with '_' (e.g. "zve32x_zvl128b").
///   - If both groups exist, they are separated by a single '_' (e.g. "imac_zve32x").
/// - If the parsed feature list is empty, use the default feature tags for that arch.
/// - Native builds should not call this; treat them separately (e.g. "native").
///
/// Examples:
/// - "riscv32-imac"
/// - "riscv32-imac_zve32x"
pub fn formatCanonicalIsaId(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    feature_profile: []const u8,
) TargetQueryError![]const u8 {
    const parsed = riscv.parseFeatureTags(allocator, feature_profile) catch |e| switch (e) {
        error.UnknownFeature => return TargetQueryError.UnknownFeature,
        error.OutOfMemory => return TargetQueryError.OutOfMemory,
    };
    defer allocator.free(parsed);

    const tags: []const []const u8 = if (parsed.len != 0) parsed else riscv.defaultFeatureTags(arch);

    // Split into single-letter and multi-letter tags.
    var singles = try std.ArrayList([]const u8).initCapacity(allocator, tags.len);
    defer singles.deinit(allocator);

    var multis = try std.ArrayList([]const u8).initCapacity(allocator, tags.len);
    defer multis.deinit(allocator);

    for (tags) |t| {
        if (t.len == 1) {
            try singles.append(allocator, t);
        } else {
            try multis.append(allocator, t);
        }
    }

    // Sort single-letter extensions in a traditional RISC-V-friendly order (closest to common "imafdc"
    // reading), while keeping multi-letter extensions lexicographically sorted for stability.
    //
    // Notes:
    // - This is only for naming (human readability). It does not change feature semantics.
    // - Unknown/less-common single-letter extensions fall back to lexical ordering among themselves.
    std.mem.sort([]const u8, singles.items, {}, struct {
        fn rank(ch: u8) u8 {
            // Lower rank = earlier in the string.
            // We weight more common/base extensions first.
            return switch (ch) {
                'i' => 0,
                'e' => 1,
                'm' => 2,
                'a' => 3,
                'f' => 4,
                'd' => 5,
                'c' => 6,
                'b' => 7,
                'v' => 8,
                // Everything else after known common ones.
                else => 100,
            };
        }

        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            // singles are len==1 by construction
            const ra = rank(a[0]);
            const rb = rank(b[0]);
            if (ra != rb) return ra < rb;
            return a[0] < b[0];
        }
    }.lessThan);

    std.mem.sort([]const u8, multis.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Build: "<arch>-<singles><optional '_' + multis-joined-by-underscore>"
    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, @tagName(arch));
    try out.append(allocator, '-');

    for (singles.items) |t| {
        try out.appendSlice(allocator, t);
    }

    if (multis.items.len != 0) {
        if (singles.items.len != 0) try out.append(allocator, '_');
        for (multis.items, 0..) |t, i| {
            if (i != 0) try out.append(allocator, '_');
            try out.appendSlice(allocator, t);
        }
    }

    return try out.toOwnedSlice(allocator);
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

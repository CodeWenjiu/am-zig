const std = @import("std");

pub fn riscv32BaseQuery() std.Target.Query {
    return .{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = .empty,
        .cpu_features_sub = .empty,
    };
}

pub const StripPreset = enum {
    none,
    conservative,
};

pub fn defaultFeatureTags(arch: std.Target.Cpu.Arch) []const []const u8 {
    return switch (arch) {
        .riscv32 => &.{"i"},
        .riscv64 => &.{"i"},
        else => &.{},
    };
}

pub fn defaultProfileName(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .riscv32 => "i",
        .riscv64 => "i",
        else => "unknown",
    };
}

pub const FeatureParseError = error{ UnknownFeature, OutOfMemory };

const known_multi_letter_extensions = &[_][]const u8{
    "zve32x",   "zve32f", "zve64x",  "zve64f",  "zve64d",
    "zvl32b",   "zvl64b", "zvl128b", "zvl256b", "zvl512b",
    "zvl1024b", "zve16f", "zfhmin",  "zfh",     "zvfhmin",
    "zvfh",     "zfa",    "zfbfmin", "zbkb",    "zbkc",
    "zbkx",     "zknd",   "zkne",    "zknh",    "zksed",
    "zksh",     "zkt",    "zvbb",    "zvbc",    "zvkb",
    "zvkg",     "zvkm",   "zvkn",    "zvknc",   "zvkned",
    "zvkng",    "zvknha", "zvknhb",  "zvks",    "zvksc",
    "zvksed",   "zvksg",  "zvksha",  "zvkshb",
};

fn countTags(profile: []const u8) usize {
    if (profile.len == 0) return 0;

    var count: usize = 0;
    var pos: usize = 0;

    while (pos < profile.len) {
        var matched = false;

        for (known_multi_letter_extensions) |ext| {
            if (std.mem.startsWith(u8, profile[pos..], ext)) {
                count += 1;
                pos += ext.len;
                matched = true;
                break;
            }
        }

        if (!matched) {
            if (profile[pos] == '_') {
                pos += 1;
            } else {
                count += 1;
                pos += 1;
            }
        }
    }

    return count;
}

fn fillTags(profile: []const u8, tags: [][]const u8) void {
    if (profile.len == 0) return;

    var idx: usize = 0;
    var pos: usize = 0;

    while (pos < profile.len) {
        var matched = false;

        for (known_multi_letter_extensions) |ext| {
            if (std.mem.startsWith(u8, profile[pos..], ext)) {
                tags[idx] = ext;
                idx += 1;
                pos += ext.len;
                matched = true;
                break;
            }
        }

        if (!matched) {
            if (profile[pos] == '_') {
                pos += 1;
            } else {
                tags[idx] = profile[pos .. pos + 1];
                idx += 1;
                pos += 1;
            }
        }
    }
}

pub fn parseFeatureTags(
    allocator: std.mem.Allocator,
    profile: []const u8,
) (FeatureParseError)![]const []const u8 {
    const count = countTags(profile);
    if (count == 0) {
        return &.{};
    }

    const tags = try allocator.alloc([]const u8, count);
    fillTags(profile, tags);
    return tags;
}

pub fn formatSupportedProfiles(_: std.mem.Allocator) []const u8 {
    return "Combine extensions (order-insensitive), e.g. i | im | imac | imzve32x";
}

pub fn supportedProfileNames(_: std.mem.Allocator) []const []const u8 {
    return &.{};
}

pub fn applyFeatures(
    q: *std.Target.Query,
    arch: std.Target.Cpu.Arch,
    features_opt: ?[]const []const u8,
    strip: StripPreset,
) !void {
    const F = std.Target.riscv.Feature;

    if (strip == .conservative) {
        q.cpu_features_sub.addFeature(@intFromEnum(F.c));
        q.cpu_features_sub.addFeature(@intFromEnum(F.a));
        q.cpu_features_sub.addFeature(@intFromEnum(F.d));
        q.cpu_features_sub.addFeature(@intFromEnum(F.m));
    }

    const tags = blk: {
        const provided = features_opt orelse &.{};
        if (provided.len == 0) break :blk defaultFeatureTags(arch);
        break :blk provided;
    };

    for (tags) |tag| {
        const feature = std.meta.stringToEnum(F, tag) orelse return error.UnknownFeature;
        q.cpu_features_add.addFeature(@intFromEnum(feature));
    }
}

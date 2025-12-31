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

pub fn formatSupportedProfiles() []const u8 {
    return "Combine extensions without arch prefix (order-insensitive), e.g. i | im | imac | im_zve32x";
}

pub fn supportedProfileNames() []const []const u8 {
    // Named/alias profiles (e.g. "gc", "gcv", "rv32imac") are intentionally not defined yet.
    // Today we accept raw, order-insensitive extension tags via -Dfeature=... (e.g. "imac", "im_zve32x").
    //
    // Keeping this API (even when empty) makes it easy to add first-class, documented presets later
    // without changing the build interface.
    return &.{};
}

// IMPORTANT:
//
// We want "longest match wins" while parsing multi-letter extensions to avoid prefix collisions
// (e.g. "zvkned" must not be tokenized as "zvkn" + "e" + "d").
//
// To keep maintenance easy, define extensions once (`known_multi_letter_extensions_raw`) and
// generate a length-sorted view at comptime (`known_multi_letter_extensions_sorted`).
const known_multi_letter_extensions_raw = &[_][]const u8{
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

fn comptimeSortedByLenDesc(comptime input: []const []const u8) [input.len][]const u8 {
    // The comptime sorting of extension strings can exceed the default evaluation branch quota.
    // Keep this localized so it doesn't affect unrelated comptime execution.
    @setEvalBranchQuota(10_000);

    // Make a comptime copy we can sort in-place.
    comptime var tmp: [input.len][]const u8 = undefined;
    inline for (input, 0..) |s, i| tmp[i] = s;

    // Selection sort (comptime-friendly).
    comptime var i: usize = 0;
    while (i < tmp.len) : (i += 1) {
        comptime var max_i: usize = i;
        comptime var j: usize = i + 1;
        while (j < tmp.len) : (j += 1) {
            if (tmp[j].len > tmp[max_i].len) max_i = j;
        }
        if (max_i != i) {
            const t = tmp[i];
            tmp[i] = tmp[max_i];
            tmp[max_i] = t;
        }
    }

    return tmp;
}

const known_multi_letter_extensions_sorted = comptimeSortedByLenDesc(known_multi_letter_extensions_raw);

comptime {
    // Multiple checks below can exceed the default evaluation branch quota (especially the O(n^2)
    // duplicate scan). Keep this localized to comptime verification only.
    @setEvalBranchQuota(20_000);

    // Ensure the generated list is sorted by descending length.
    var i: usize = 1;
    while (i < known_multi_letter_extensions_sorted.len) : (i += 1) {
        const prev = known_multi_letter_extensions_sorted[i - 1];
        const cur = known_multi_letter_extensions_sorted[i];
        if (prev.len < cur.len) {
            @compileError(std.fmt.comptimePrint(
                "known_multi_letter_extensions_sorted must be sorted by descending length; offending pair at index {d}: prev=\"{s}\"(len={d}) < cur=\"{s}\"(len={d})",
                .{ i, prev, prev.len, cur, cur.len },
            ));
        }
    }

    // Ensure the raw list contains no duplicates (helps maintenance).
    // We check the raw list so the error points at the true source of duplication.
    var a: usize = 0;
    while (a < known_multi_letter_extensions_raw.len) : (a += 1) {
        var b: usize = a + 1;
        while (b < known_multi_letter_extensions_raw.len) : (b += 1) {
            const x = known_multi_letter_extensions_raw[a];
            const y = known_multi_letter_extensions_raw[b];
            if (std.mem.eql(u8, x, y)) {
                @compileError(std.fmt.comptimePrint(
                    "known_multi_letter_extensions_raw contains a duplicate entry: \"{s}\" (indices {d} and {d})",
                    .{ x, a, b },
                ));
            }
        }
    }
}

fn parseNextTag(profile: []const u8, pos: *usize) ?[]const u8 {
    while (pos.* < profile.len and profile[pos.*] == '_') {
        pos.* += 1;
    }

    if (pos.* >= profile.len) return null;

    for (known_multi_letter_extensions_sorted) |ext| {
        if (std.mem.startsWith(u8, profile[pos.*..], ext)) {
            const out = ext;
            pos.* += ext.len;
            return out;
        }
    }

    const out = profile[pos.* .. pos.* + 1];
    pos.* += 1;
    return out;
}

pub fn parseFeatureTags(
    allocator: std.mem.Allocator,
    profile: []const u8,
) (FeatureParseError)![]const []const u8 {
    if (profile.len == 0) return &.{};

    // Tokenize while deduplicating (preserve first occurrence order).
    // We keep this O(n^2) intentionally: feature tag counts are small in practice and this avoids
    // allocating a hash map. If this ever becomes a hot path, we can switch to an AutoHashMap.
    var unique = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    errdefer unique.deinit(allocator);

    var pos: usize = 0;
    while (parseNextTag(profile, &pos)) |tag| {
        for (unique.items) |seen| {
            if (std.mem.eql(u8, seen, tag)) break;
        } else {
            try unique.append(allocator, tag);
        }
    }

    if (unique.items.len == 0) return &.{};

    return try unique.toOwnedSlice(allocator);
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

const std = @import("std");

/// Canonical ISA identifier formatting for artifact naming.
///
/// This module is ISA-agnostic: it does *not* parse profile strings and it does *not* know about any
/// ISA family's tag tokenizer. Callers must provide parsed feature tags.
///
/// Output format:
/// - Non-native: "<arch>-<features>"
/// - Native: the caller should use "native" and skip this module.
///
/// Canonical feature rendering rules (generic):
/// - Single-letter extensions (len==1) come first and are ordered in a traditional, readable order:
///     i, e, m, a, f, d, c, b, v, (others...)
///   Unknown single-letter extensions are ordered after known ones, then by ASCII.
/// - Multi-letter extensions (len>1) follow, sorted lexicographically and joined with '_'.
/// - If both groups exist, they are separated by a single '_' (e.g. "imac_zve32x").
///
/// Examples (assuming tags were already assumed to be valid for the arch):
/// - arch=riscv32, tags={"i","m","a","c"}               => "riscv32-imac"
/// - arch=riscv32, tags={"a","c","i","m","zve32x"}      => "riscv32-imac_zve32x"
pub const Error = error{
    UnsupportedArch,
    UnknownFeature,
    OutOfMemory,
};

/// Same as the legacy `formatCanonicalIsaId` but takes already-parsed tags.
///
/// Tags are assumed to be:
/// - deduplicated (recommended)
/// - valid for the selected ISA family (this module does not validate semantics)
/// Ordering does not matter (we will canonicalize).
pub fn formatCanonicalIsaIdFromTags(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    tags: []const []const u8,
) Error![]const u8 {
    // Split into singles and multis.
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

    // Sort singles by RISC-V-friendly rank, then ASCII.
    std.mem.sort([]const u8, singles.items, {}, struct {
        fn rank(ch: u8) u8 {
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

    // Sort multis lexicographically.
    std.mem.sort([]const u8, multis.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Build "<arch>-<singles><optional '_' + multis...>"
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

// NOTE: `formatCanonicalIsaIdFromTags` is defined above. The naming module no longer parses
// profile strings; callers must provide parsed tags.

const std = @import("std");

/// helper to skip leading whitespace in a slice
fn skipSpace(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and std.ascii.isWhitespace(s[i])) : (i += 1) {}
    return s[i..];
}

/// Minimal, allocation-free parser that turns an injected argument string
/// into an argv-like slice. Intended to be shared by all platforms.
///
/// Features / assumptions:
/// - Always emits argv[0] (provided by caller as `argv0`).
/// - Splits on ASCII whitespace only. No quoting/escaping support.
/// - Does not allocate; writes into caller-provided buffer `out`.
/// - Returns the used prefix of `out`.
pub fn parseInjectedArgv(arg_str: []const u8, out: []([]const u8), argv0: []const u8) []const []const u8 {
    if (out.len == 0) return &.{};

    var n: usize = 0;

    // argv[0]
    out[n] = argv0;
    n += 1;

    var rest = arg_str;

    while (n < out.len) {
        rest = skipSpace(rest);
        if (rest.len == 0) break;

        var end: usize = 0;
        while (end < rest.len and !std.ascii.isWhitespace(rest[end])) : (end += 1) {}

        out[n] = rest[0..end];
        n += 1;
        rest = rest[end..];
    }

    return out[0..n];
}

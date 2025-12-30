const std = @import("std");
const app = @import("app");
const build_options = @import("build_options");

/// Native entrypoint.
///
/// This version deliberately does *not* use `std.process.args()` for argv.
/// Instead, it matches the bare-metal behavior by taking arguments from a
/// build-time injected string:
///
///   zig build -Dplatform=native run -Darg="foo bar --name=Zig"
///
/// Notes:
/// - This parser is intentionally simple: ASCII whitespace splitting only.
///   No quoting/escaping.
/// - `argv[0]` is synthesized as "app" to match the convention used by the
///   freestanding runtimes in this repo.
/// - If `app.main` has signature `pub fn main(argv: []const []const u8) ...`,
///   we pass the parsed argv slice. Otherwise, we call `app.main()` (legacy).
pub fn main() !void {
    const fn_info = @typeInfo(@TypeOf(app.main)).@"fn";
    const ret_ty = fn_info.return_type.?;

    if (fn_info.params.len == 1) {
        var argv_storage: [64][]const u8 = undefined;

        var injected = InjectedArgs.init(build_options.arg);
        const argv = injected.fillArray(&argv_storage);

        if (ret_ty == void) {
            app.main(argv);
        } else {
            try app.main(argv);
        }
    } else {
        if (ret_ty == void) {
            app.main();
        } else {
            try app.main();
        }
    }
}

/// Minimal, allocation-free argv builder from a single injected string.
/// Splits on ASCII whitespace. Does not support quotes/escapes.
const InjectedArgs = struct {
    rest: []const u8,
    emitted_argv0: bool = false,

    pub fn init(s: []const u8) InjectedArgs {
        return .{ .rest = s, .emitted_argv0 = false };
    }

    fn skipSpace(self: *InjectedArgs) void {
        while (self.rest.len != 0 and std.ascii.isWhitespace(self.rest[0])) {
            self.rest = self.rest[1..];
        }
    }

    fn nextToken(self: *InjectedArgs) ?[]const u8 {
        self.skipSpace();
        if (self.rest.len == 0) return null;

        var end: usize = 0;
        while (end < self.rest.len and !std.ascii.isWhitespace(self.rest[end])) {
            end += 1;
        }

        const tok = self.rest[0..end];
        self.rest = self.rest[end..];
        return tok;
    }

    /// Returns next argv entry (argv[0] first), then tokens from the injected string.
    pub fn next(self: *InjectedArgs) ?[]const u8 {
        if (!self.emitted_argv0) {
            self.emitted_argv0 = true;
            return "app";
        }
        return self.nextToken();
    }

    /// Fill `out` with argv slices and return the used prefix.
    /// Always includes synthesized argv[0] = "app".
    pub fn fill(self: *InjectedArgs, out: []([]const u8)) []const []const u8 {
        var n: usize = 0;
        while (n < out.len) : (n += 1) {
            const a = self.next() orelse break;
            out[n] = a;
        }
        return out[0..n];
    }

    /// Convenience overload for fixed-size arrays.
    pub fn fillArray(self: *InjectedArgs, out: anytype) []const []const u8 {
        // `out` is expected to be `*[_][]const u8` or `*[_][]const u8`.
        return self.fill(out[0..]);
    }
};

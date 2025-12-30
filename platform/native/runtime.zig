const std = @import("std");
const app = @import("app");
const build_options = @import("build_options");
const argv_util = @import("argv");

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
/// - argv[0] comes from build_options.exe_name (defaults to the executable name
///   set in build.zig).
/// - If `app.main` has signature `pub fn main(argv: []const []const u8) ...`,
///   we pass the parsed argv slice. Otherwise, we call `app.main()` (legacy).
pub fn main() !void {
    const fn_info = @typeInfo(@TypeOf(app.main)).@"fn";
    const ret_ty = fn_info.return_type.?;

    if (fn_info.params.len == 1) {
        var argv_storage: [64][]const u8 = undefined;

        const argv = argv_util.parseInjectedArgv(build_options.arg, &argv_storage, build_options.exe_name);

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

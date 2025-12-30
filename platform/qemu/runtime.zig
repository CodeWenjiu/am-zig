const std = @import("std");
const app = @import("app");
const uart = @import("uart.zig");
const build_options = @import("build_options");
const argv_util = @import("argv");

// ISA abstraction layer
// In a real scenario, this could be selected via build options
const isa = @import("riscv/start.zig");

// Ensure ISA symbols (like _start) are compiled and exported
comptime {
    _ = isa;
}

pub const std_options: std.Options = .{
    .logFn = uartLogFn,
    .log_level = .info,
};

fn uartLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;
    uart.print(prefix ++ format ++ "\n", args);
}

// This function is called by the ISA-specific assembly startup code (_start)
export fn call_main_wrapper() noreturn {
    uart.init();

    // Parse optional injected argument string into argv-style slices.
    // Note: this is a minimal splitter (space-delimited, no quoting/escaping).
    // argv[0] comes from build_options.exe_name (defaults to the exe name set in build.zig).
    var argv_storage: [16][]const u8 = undefined;
    const argv = argv_util.parseInjectedArgv(build_options.arg, &argv_storage, build_options.exe_name);

    const ReturnType = @typeInfo(@TypeOf(app.main)).@"fn".return_type.?;
    const FnInfo = @typeInfo(@TypeOf(app.main)).@"fn";

    if (FnInfo.params.len == 1) {
        if (ReturnType == void) {
            app.main(argv);
        } else {
            if (app.main(argv)) {
                // success
            } else |err| {
                std.log.err("Main returned error: {}", .{err});
            }
        }
    } else {
        if (ReturnType == void) {
            app.main();
        } else {
            if (app.main()) {
                // success
            } else |err| {
                std.log.err("Main returned error: {}", .{err});
            }
        }
    }

    isa.quit();
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\nPANIC: ");
    uart.puts(msg);
    uart.puts("\n");
    isa.quit();
}

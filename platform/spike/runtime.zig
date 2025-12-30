const std = @import("std");
const app = @import("app");
const uart = @import("uart.zig");
const build_options = @import("build_options");

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

fn ArgIterFromString(comptime max_args: usize) type {
    return struct {
        input: []const u8,
        idx: usize = 0,

        fn skipSpaces(self: *@This()) void {
            while (self.idx < self.input.len and self.input[self.idx] == ' ') : (self.idx += 1) {}
        }

        fn nextToken(self: *@This()) ?[]const u8 {
            self.skipSpaces();
            if (self.idx >= self.input.len) return null;

            const start = self.idx;
            while (self.idx < self.input.len and self.input[self.idx] != ' ') : (self.idx += 1) {}
            return self.input[start..self.idx];
        }

        pub fn fill(self: *@This(), out: *[max_args][]const u8) []const []const u8 {
            var n: usize = 0;
            while (n < max_args) {
                const tok = self.nextToken() orelse break;
                out[n] = tok;
                n += 1;
            }
            return out[0..n];
        }
    };
}

fn getInjectedArgs() []const u8 {
    // Build-time injected string forwarded via `entry_mod.addOptions("build_options", ...)`.
    // In `build.zig` we store `arg` as a plain string (possibly empty), so treat it as such.
    // Convention: empty string means "no injected args".
    return build_options.arg;
}

// This function is called by the ISA-specific assembly startup code (_start)
export fn call_main_wrapper() noreturn {
    uart.init();

    // Parse optional injected argument string into argv-style slices.
    // Note: this is a minimal splitter (space-delimited, no quoting/escaping).
    var argv_storage: [16][]const u8 = undefined;
    var it = ArgIterFromString(16){ .input = getInjectedArgs() };
    const argv = it.fill(&argv_storage);

    const ReturnType = @typeInfo(@TypeOf(app.main)).@"fn".return_type.?;
    const FnInfo = @typeInfo(@TypeOf(app.main)).@"fn";

    // If app.main expects argv (one parameter), pass it.
    // Otherwise, call it with no args (legacy behavior).
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

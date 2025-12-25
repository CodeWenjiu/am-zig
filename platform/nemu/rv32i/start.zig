const std = @import("std");

const app = @import("app");

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, _stack_top
        \\ call call_main_wrapper
    );
}

comptime {
    _ = &_start;
}

export fn call_main_wrapper() noreturn {
    app.main();

    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}

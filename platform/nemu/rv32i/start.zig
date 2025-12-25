const std = @import("std");

const app = @import("app_logic");

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

    // 3. 任务结束，进入死循环
    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}

export fn _start() linksection(".text._start") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, _stack_top
        \\ call call_main_wrapper
    );
}

pub fn ebreak() void {
    asm volatile ("ebreak");
}

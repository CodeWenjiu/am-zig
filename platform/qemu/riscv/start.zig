export fn _start() linksection(".text._start") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, _stack_top
        \\ call call_main_wrapper
    );
}

pub fn quit() noreturn {
    asm volatile ("ebreak");
    while (true) {}
}

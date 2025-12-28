export fn _start() linksection(".text._start") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, _stack_top
        \\ call call_main_wrapper
    );
}

const QEMU_TEST_DEVICE: usize = 0x100000;
const QEMU_EXIT_SUCCESS: u32 = 0x5555;
const QEMU_EXIT_FAILURE: u32 = 0x3333;

pub fn quit() noreturn {
    const exit_value: u32 = QEMU_EXIT_SUCCESS;
    const quit_reg = @as(*volatile u32, @ptrFromInt(QEMU_TEST_DEVICE));
    quit_reg.* = exit_value;
    while (true) {}
}

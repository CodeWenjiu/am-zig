export fn _start() linksection(".text._start") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, _stack_top
        \\ call call_main_wrapper
    );
}

const QEMU_TEST_DEVICE: usize = 0x100000;
const QEMU_EXIT_SUCCESS: u32 = 0x5555;
const QEMU_EXIT_FAILURE: u32 = 0x3333;

extern var tohost: u64;

pub fn quit() noreturn {
    @as(*volatile u64, @ptrCast(&tohost)).* = 1;
    while (true) {
        asm volatile ("wfi");
    }
}

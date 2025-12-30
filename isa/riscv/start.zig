/// Common RISC-V start shim used by multiple platforms.
/// - Sets up the stack pointer from linker-provided `_stack_top`.
/// - Jumps into the platform runtime entry `call_main_wrapper`.
/// - All platform-specific differences (e.g. how `quit` exits) should be
///   provided in the platform runtime, not here.
export fn _start() linksection(".text._start") callconv(.naked) noreturn {
    asm volatile (
        \\  la sp, _stack_top
        \\  call call_main_wrapper
    );
}

/// RISC-V start shim for vector-enabled builds.
///
/// This variant enables vector state (mstatus.VS) before entering the platform
/// runtime. Use this module as the start shim when building/running with RVV
/// (e.g. `zve*`) so that the first vector instruction does not trap due to VS=0.
///
/// Requirements:
/// - Linker script provides `_stack_top`.
/// - Platform runtime provides `call_main_wrapper`.
export fn _start() linksection(".text._start") callconv(.naked) noreturn {
    asm volatile (
        \\  la sp, _stack_top
        \\  li a0, 0x200
        \\  csrs mstatus, a0
        \\  call call_main_wrapper
    );
}

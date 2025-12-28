const std = @import("std");

const UART_BASE = 0x10000000;

const UART_THR = 0;
const UART_RHR = 0;
const UART_IER = 1;
const UART_FCR = 2;
const UART_LCR = 3;
const UART_MCR = 4;
const UART_LSR = 5;
const UART_MSR = 6;
const UART_SPR = 7;

const LSR_THRE = 0x20;

pub fn init() void {
    write_reg(UART_IER, 0x00);

    write_reg(UART_LCR, 0x80);

    write_reg(0, 1);
    write_reg(1, 0);

    write_reg(UART_LCR, 0x03);

    write_reg(UART_FCR, 0x01);

    write_reg(UART_MCR, 0x03);
}

fn write_reg(offset: u32, value: u8) void {
    const ptr = @as(*volatile u8, @ptrFromInt(UART_BASE + offset));
    ptr.* = value;
}

fn read_reg(offset: u32) u8 {
    const ptr = @as(*volatile u8, @ptrFromInt(UART_BASE + offset));
    return ptr.*;
}

fn is_tx_ready() bool {
    return (read_reg(UART_LSR) & LSR_THRE) != 0;
}

pub fn putc(char: u8) void {
    while (!is_tx_ready()) {}

    write_reg(UART_THR, char);
}

pub fn puts(str: []const u8) void {
    for (str) |char| {
        putc(char);
        if (char == '\n') {
            putc('\r');
        }
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buffer: [256]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, fmt, args) catch {
        puts("ERROR: format buffer overflow\n");
        return;
    };
    puts(formatted);
}

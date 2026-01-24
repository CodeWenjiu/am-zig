const std = @import("std");
const uart_dev = @import("uart_dev");

const uart = uart_dev.Uart16550{ .base = 0x1000_0000 };

pub fn init() void {
    uart.init();
}

pub fn putc(ch: u8) void {
    uart.putc(ch);
}

pub fn puts(str: []const u8) void {
    uart.puts(str);
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    uart.print(fmt, args);
}

const std = @import("std");

/// 16550-compatible UART driver with configurable base address.
/// Instantiate with `const uart = Uart16550{ .base = 0x1000_0000 };`
/// and call `uart.init();`, then `uart.print/puts/putc(...)`.
pub const Uart16550 = struct {
    base: usize,

    /// Initialize UART for 8N1, divisor = 1 (assumes 115200 baud on typical clocks).
    pub fn init(self: *const Uart16550) void {
        // Disable interrupts.
        self.writeReg(UART_IER, 0x00);

        // Enable DLAB to set divisor.
        self.writeReg(UART_LCR, 0x80);

        // Divisor = 1 (low then high).
        self.writeReg(0, 1);
        self.writeReg(1, 0);

        // 8 bits, no parity, one stop bit; clear DLAB.
        self.writeReg(UART_LCR, 0x03);

        // Enable FIFO.
        self.writeReg(UART_FCR, 0x01);

        // Set DTR/RTS.
        self.writeReg(UART_MCR, 0x03);
    }

    fn writeReg(self: *const Uart16550, offset: u32, value: u8) void {
        const ptr = @as(*volatile u8, @ptrFromInt(self.base + @as(usize, offset)));
        ptr.* = value;
    }

    fn readReg(self: *const Uart16550, offset: u32) u8 {
        const ptr = @as(*volatile u8, @ptrFromInt(self.base + @as(usize, offset)));
        return ptr.*;
    }

    fn isTxReady(self: *const Uart16550) bool {
        return (self.readReg(UART_LSR) & LSR_THRE) != 0;
    }

    pub fn putc(self: *const Uart16550, ch: u8) void {
        while (!self.isTxReady()) {}
        self.writeReg(UART_THR, ch);
    }

    pub fn puts(self: *const Uart16550, str: []const u8) void {
        for (str) |ch| {
            self.putc(ch);
            if (ch == '\n') {
                self.putc('\r');
            }
        }
    }

    pub fn print(self: *const Uart16550, comptime fmt: []const u8, args: anytype) void {
        var buffer: [256]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buffer, fmt, args) catch {
            self.puts("ERROR: format buffer overflow\n");
            return;
        };
        self.puts(formatted);
    }
};

pub const UartStdIo = struct {
    pub const Writer = struct {
        uart: *const Uart16550,

        pub fn writeAll(self: Writer, bytes: []const u8) error{}!void {
            for (bytes) |b| self.uart.putc(b);
            return;
        }
    };

    pub fn writer(uart: *const Uart16550) Writer {
        return .{ .uart = uart };
    }

    pub fn stdoutWriter(uart: *const Uart16550) Writer {
        return writer(uart);
    }

    pub fn stderrWriter(uart: *const Uart16550) Writer {
        return writer(uart);
    }
};

pub const UART_THR = 0;
pub const UART_RHR = 0;
pub const UART_IER = 1;
pub const UART_FCR = 2;
pub const UART_LCR = 3;
pub const UART_MCR = 4;
pub const UART_LSR = 5;
pub const UART_MSR = 6;
pub const UART_SPR = 7;

pub const LSR_THRE = 0x20;

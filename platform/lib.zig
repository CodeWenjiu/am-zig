const std = @import("std");

pub const Platform = enum {
    native,
    nemu,
    qemu,
    spike,

    pub fn resolvedTarget(self: Platform, b: *std.Build, isa: ?Isa) std.Build.ResolvedTarget {
        return switch (self) {
            .native => {
                if (isa) |_| {
                    std.debug.print("warning: -Disa with -Dplatform=native is ignored (native ISA is determined by the host)\n", .{});
                }
                return b.standardTargetOptions(.{});
            },
            else => {
                const chosen_isa = isa orelse missingOptionExit(Isa, "isa");
                return b.resolveTargetQuery(self.targetQuery(chosen_isa));
            },
        };
    }

    pub fn targetQuery(self: Platform, isa: Isa) std.Target.Query {
        return switch (self) {
            .native => native_target.targetQuery(isa),
            .nemu => nemu_target.targetQuery(isa),
            .qemu => qemu_target.targetQuery(isa),
            .spike => spike_target.targetQuery(isa),
        };
    }
};

pub const IsaFamily = enum {
    riscv,
};

pub const Isa = enum {
    rv32i,

    pub fn getFamily(self: Isa) IsaFamily {
        return switch (self) {
            .rv32i => .riscv,
        };
    }
};

fn missingOptionExit(comptime T: type, name: []const u8) noreturn {
    std.debug.print("Missing required argument: -D{s}=<{s}>\n", .{ name, name });
    std.debug.print("Available options: ", .{});
    const fields = @typeInfo(T).@"enum".fields;
    inline for (fields, 0..) |field, i| {
        std.debug.print("[{s}]", .{field.name});
        if (i < fields.len - 1) std.debug.print(" | ", .{});
    }
    std.debug.print("\n", .{});
    std.process.exit(1);
}

const native_target = @import("native/target.zig");
const nemu_target = @import("nemu/target.zig");
const qemu_target = @import("qemu/target.zig");
const spike_target = @import("spike/target.zig");

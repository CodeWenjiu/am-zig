const std = @import("std");

/// ISA families we support.
/// Add new families (e.g. `arm`) here when needed.
pub const IsaFamily = enum {
    riscv,
};

/// ISA variants.
/// Add new variants under the appropriate family.
/// If a platform cannot support a given ISA, the build layer should reject it.
pub const Isa = enum {
    // RISC-V 32-bit variants
    rv32i,
    rv32im,
    rv32imac,
    rv32im_zve32x,

    /// Return the family for this ISA.
    pub fn family(self: Isa) IsaFamily {
        return switch (self) {
            .rv32i,
            .rv32im,
            .rv32imac,
            .rv32im_zve32x,
            => .riscv,
        };
    }

    /// Pretty name for diagnostics.
    pub fn name(self: Isa) []const u8 {
        return @tagName(self);
    }
};

/// Helper to print a nice list of available ISAs for diagnostics.
pub fn printAvailableIsas() void {
    std.debug.print("Available ISAs: ", .{});
    const fields = @typeInfo(Isa).@"enum".fields;
    inline for (fields, 0..) |field, i| {
        std.debug.print("[{s}]", .{field.name});
        if (i < fields.len - 1) std.debug.print(" | ", .{});
    }
    std.debug.print("\n", .{});
}

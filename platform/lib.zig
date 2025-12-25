const std = @import("std");

pub const Platform = enum {
    native,
    nemu,
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

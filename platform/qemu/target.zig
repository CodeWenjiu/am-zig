const std = @import("std");

const lib = @import("../lib.zig");
const Isa = lib.Isa;

pub fn targetQuery(isa: Isa) std.Target.Query {
    return switch (isa) {
        .rv32i => .{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
        },
    };
}

const std = @import("std");
const types = @import("types.zig");
const riscv = @import("riscv/target.zig");

pub const Isa = types.Isa;
pub const IsaFamily = types.IsaFamily;

/// Re-export RISC-V strip presets so platforms can pick conservative vs default.
pub const RiscvStripPreset = riscv.StripPreset;

/// Dispatch ISA-specific target queries.
/// `strip` lets callers request conservative feature stripping (useful for
/// emulators that default-enable optional extensions).
pub fn targetQuery(isa: Isa, strip: ?RiscvStripPreset) std.Target.Query {
    return switch (isa.family()) {
        .riscv => riscvQuery(isa, strip orelse .none),
    };
}

/// Internal: build a RISC-V32 target query from the shared helpers.
fn riscvQuery(isa: Isa, strip: RiscvStripPreset) std.Target.Query {
    var q = riscv.riscv32BaseQuery();
    riscv.applyIsaFeatures(&q, isa, strip);
    return q;
}

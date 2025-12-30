/// RISC-V target helpers: base + strip + apply pattern.
const std = @import("std");
const Isa = @import("../types.zig").Isa;

/// Baseline RISC-V32 target query (freestanding, no OS, no ABI, generic core).
/// Use `applyIsaFeatures` to specialize feature bits for a specific ISA profile.
pub fn riscv32BaseQuery() std.Target.Query {
    return .{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = .empty,
        .cpu_features_sub = .empty,
    };
}

/// How aggressively to strip optional features before applying a specific ISA.
pub const StripPreset = enum {
    /// Keep toolchain defaults; only add features required by the ISA.
    none,

    /// Remove common optional extensions first (c/a/d/m), then re-add what the
    /// ISA profile explicitly includes. Useful for emulators where defaults
    /// may include optional extensions you want to control.
    conservative,
};

/// Apply ISA-specific feature additions (and optional conservative stripping)
/// to an existing RISC-V32 target query.
///
/// Usage:
///   var q = riscv32BaseQuery();
///   applyIsaFeatures(&q, .rv32imac, .conservative);
pub fn applyIsaFeatures(q: *std.Target.Query, isa: Isa, strip: StripPreset) void {
    const F = std.Target.riscv.Feature;

    if (strip == .conservative) {
        q.cpu_features_sub.addFeature(@intFromEnum(F.c));
        q.cpu_features_sub.addFeature(@intFromEnum(F.a));
        q.cpu_features_sub.addFeature(@intFromEnum(F.d));
        q.cpu_features_sub.addFeature(@intFromEnum(F.m));
    }

    switch (isa) {
        .rv32i => {},
        .rv32im => {
            q.cpu_features_add.addFeature(@intFromEnum(F.m));
        },
        .rv32imac => {
            q.cpu_features_add.addFeature(@intFromEnum(F.m));
            q.cpu_features_add.addFeature(@intFromEnum(F.a));
            q.cpu_features_add.addFeature(@intFromEnum(F.c));
        },
        .rv32im_zve32x => {
            q.cpu_features_add.addFeature(@intFromEnum(F.m));
            q.cpu_features_add.addFeature(@intFromEnum(F.zve32x));
        },
    }
}

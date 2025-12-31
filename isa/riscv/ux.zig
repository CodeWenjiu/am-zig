const std = @import("std");

/// RISC-V specific UX / CLI helper utilities.
///
/// This module contains only user-facing help text and suggested named presets.
/// It must not contain parsing / `Target.Query` construction logic.
///
/// The build interface accepted by this project is:
/// - `-Dtarget=<arch>` (required for non-native builds)
/// - `-Dfeature=<flags>` (optional; order-insensitive; no arch prefix)
///
/// Valid examples of `-Dfeature` values:
/// - `i`
/// - `im`
/// - `imac`
/// - `im_zve32x`
/// - `zve32ximac`
///
/// Note: RISC-V tags are interpreted by `isa/riscv/target.zig` (tokenizer + applyFeatures).
pub fn formatSupportedProfiles() []const u8 {
    return "Combine extensions without arch prefix (order-insensitive), e.g. i | im | imac | im_zve32x";
}

/// Return a static list of named/alias profiles for RISC-V.
///
/// Named presets are intentionally optional: today the project accepts raw extension tags via
/// `-Dfeature`, which is more flexible than maintaining a curated preset list.
///
/// If you later introduce true presets (aliases that expand to multiple tags), list them here.
/// Keep this allocator-free and static so it can be used in error messages without allocations.
pub fn supportedProfileNames() []const []const u8 {
    return &.{
        // No named presets yet.
        //
        // Examples you might add later:
        // "i",
        // "im",
        // "imac",
        // "gc",
        // "gcv",
    };
}

/// Optional helper: describe common RISC-V feature-tag conventions.
///
/// This is not used by the build system today, but is handy for future help output.
pub fn featureTagNotes() []const u8 {
    return "Single-letter tags (i,m,a,f,d,c,...) and multi-letter Z* extensions can be combined; '_' may be used as a visual separator.";
}

/// Optional helper: return whether an arch is within the RISC-V family.
/// This can be used by ISA-agnostic routing layers (e.g. `isa/ux.zig`).
pub fn isRiscvArch(arch: std.Target.Cpu.Arch) bool {
    return switch (arch) {
        .riscv32, .riscv64 => true,
        else => false,
    };
}

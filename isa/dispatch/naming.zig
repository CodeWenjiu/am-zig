const std = @import("std");

const top_naming = @import("../naming.zig");
const riscv = @import("../riscv/target.zig");
const resolve = @import("resolve.zig");

/// Naming adapter for the ISA dispatch layer.
///
/// This module exists so that `isa/dispatch.zig` can become a thin re-export surface,
/// while naming logic stays in `isa/naming.zig` and ISA-family defaults stay in their
/// respective implementation modules (e.g. `isa/riscv/target.zig`).
///
/// Contract:
/// - `feature_profile` is the raw feature string (no arch prefix), same as `-Dfeature`.
/// - If `feature_profile` parses to an empty tag list, we fall back to the ISA-family default tags
///   for the given `arch` (currently RISC-V defaults are used for riscv32/riscv64).
/// - Errors are mapped into `resolve.TargetQueryError` so callers have a single error set.
pub fn formatCanonicalIsaId(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    feature_profile: []const u8,
) resolve.TargetQueryError![]const u8 {
    // Default tags are ISA-family specific.
    // Today this project only supports RISC-V in the non-native path, so we use the RISC-V defaults.
    // When adding other ISA families, extend this switch to choose the right default tag set.
    const default_tags: []const []const u8 = switch (arch) {
        .riscv32, .riscv64 => riscv.defaultFeatureTags(arch),
        else => &.{},
    };

    return top_naming.formatCanonicalIsaId(allocator, arch, feature_profile, default_tags) catch |e| switch (e) {
        error.UnsupportedArch => return resolve.TargetQueryError.UnsupportedArch,
        error.UnknownFeature => return resolve.TargetQueryError.UnknownFeature,
        error.OutOfMemory => return resolve.TargetQueryError.OutOfMemory,
    };
}

const std = @import("std");

const resolve = @import("resolve.zig");
const riscv_family = @import("../riscv/family.zig");

/// Strip preset type used by query construction.
///
/// Notes:
/// - Today this is only meaningful for RISC-V.
/// - The query layer is ISA-agnostic; it routes by `arch`, so this type may evolve into a union/enum
///   that covers other ISA families as they are added.
pub const StripPreset = riscv_family.StripPreset;

/// Errors surfaced by ISA query construction.
///
/// - Reuses `resolve.TargetQueryError` so we don't duplicate error sets across modules.
/// - This module never returns `error.MissingTarget` (that's a resolve-layer concern), but it is
///   part of the shared error set for convenience.
pub const Error = resolve.TargetQueryError;

/// Build a `std.Target.Query` from a raw feature profile string (e.g. "imac", "im_zve32x").
///
/// This is ISA-agnostic by design: it routes by `arch` to the appropriate ISA-family module.
/// As new ISA families are added, extend the `switch (arch)` below.
///
/// `strip`:
/// - Currently only meaningful for RISC-V, but kept in the signature for compatibility / future use.
pub fn targetQueryFromProfile(
    allocator: std.mem.Allocator,
    arch: std.Target.Cpu.Arch,
    profile_string: []const u8,
    strip: ?StripPreset,
) Error!std.Target.Query {
    return switch (arch) {
        .riscv32, .riscv64 => riscv_family.targetQueryFromProfile(allocator, arch, profile_string, strip) catch |e| switch (e) {
            error.UnsupportedArch => return Error.UnsupportedArch,
            error.UnknownFeature => return Error.UnknownFeature,
            error.OutOfMemory => return Error.OutOfMemory,
        },
        else => Error.UnsupportedArch,
    };
}

/// Build a `std.Target.Query` from already-parsed feature tags.
///
/// This is ISA-agnostic by design: it routes by `arch` to the appropriate ISA-family module.
/// As new ISA families are added, extend the `switch (arch)` below.
///
/// Note:
/// - `strip` is currently only meaningful for RISC-V.
pub fn targetQueryFromTags(
    arch: std.Target.Cpu.Arch,
    features: []const []const u8,
    strip: ?StripPreset,
) Error!std.Target.Query {
    return switch (arch) {
        .riscv32, .riscv64 => riscv_family.targetQueryFromTags(arch, features, strip) catch |e| switch (e) {
            error.UnsupportedArch => return Error.UnsupportedArch,
            error.UnknownFeature => return Error.UnknownFeature,
            error.OutOfMemory => return Error.OutOfMemory,
        },
        else => Error.UnsupportedArch,
    };
}

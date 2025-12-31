const std = @import("std");

const riscv_ux = @import("riscv/ux.zig");

/// UX / CLI helper utilities for ISA selection (ISA-agnostic routing layer).
///
/// Responsibilities:
/// - Route `arch` to the correct ISA-family UX module.
/// - Keep user-facing help text out of ISA parsing/feature-application modules.
///
/// As new ISA families are added, extend the `switch (arch)` statements below to delegate to the
/// appropriate `<family>/ux.zig` module.
pub fn formatSupportedProfiles(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => riscv_ux.formatSupportedProfiles(),
        else => "No ISA-specific feature profile format is defined for this architecture yet.",
    };
}

/// Return a static list of named/alias profiles for the given architecture.
///
/// Named presets are intentionally optional: the project accepts raw extension tags via `-Dfeature`,
/// which is more flexible than maintaining a curated preset list.
///
/// Keep this allocator-free and static so it can be used freely in error messages and help text.
pub fn supportedProfileNames(arch: std.Target.Cpu.Arch) []const []const u8 {
    return switch (arch) {
        .riscv32, .riscv64 => riscv_ux.supportedProfileNames(),
        else => &.{},
    };
}

const std = @import("std");

const lib = @import("../lib.zig");
const Isa = lib.Isa;

/// Native platform does not use ISA-based target selection.
/// The resolved target is provided via `Platform.resolvedTarget(...)` using
/// Zig's standard target options (supports `-Dtarget`).
///
/// This function exists only to satisfy the uniform interface across platforms.
pub fn targetQuery(_: Isa) std.Target.Query {
    return .{};
}

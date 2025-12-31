const std = @import("std");

/// Add a disassembly (objdump) step for an executable and wire it into a per-platform `dump-<platform>`
/// step as well as the global `dump` step.
///
/// Output:
/// - Installs `<exe_base_name>.asm` into `zig-out/<platform_tag>/` (same dest dir as other platform artifacts).
///
/// Notes:
/// - `exe_base_name` is expected to already include any ISA suffix you want in the filename
///   (e.g. `<bin>-<isa>`).
pub fn addDumpSteps(
    b: *std.Build,
    platform_tag: []const u8,
    exe_base_name: []const u8,
    exe: *std.Build.Step.Compile,
) struct {
    /// The platform-specific dump step (e.g. `dump-qemu`).
    platform_dump_step: *std.Build.Step,
    /// The install step that writes the `.asm` file.
    install_dump_step: *std.Build.Step,
} {
    const objdump = b.addSystemCommand(&.{ "objdump", "-d" });
    objdump.addFileArg(exe.getEmittedBin());

    const dump_output = objdump.captureStdOut();

    const asm_name = b.fmt("{s}.asm", .{exe_base_name});
    const install_dump = b.addInstallFile(dump_output, b.pathJoin(&.{ platform_tag, asm_name }));

    const platform_dump_step = b.step(
        b.fmt("dump-{s}", .{platform_tag}),
        b.fmt("Generate disassembly and save to {s}", .{asm_name}),
    );
    platform_dump_step.dependOn(b.getInstallStep());
    platform_dump_step.dependOn(&install_dump.step);

    const dump = b.step("dump", b.fmt("Generate disassembly and save to {s}", .{asm_name}));
    dump.dependOn(platform_dump_step);

    return .{
        .platform_dump_step = platform_dump_step,
        .install_dump_step = &install_dump.step,
    };
}

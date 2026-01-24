const std = @import("std");

pub fn entryModule(
    b: *std.Build,
    feature_profile: ?[]const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    _ = feature_profile;
    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/remu/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);

    // Expose shared 16550 UART driver as a package for platform runtimes.
    const uart_dev_pkg = b.createModule(.{
        .root_source_file = b.path("platform/device/uart16550.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("uart_dev", uart_dev_pkg);

    // NOTE:
    // Do not hardcode the ISA start shim here. The top-level build injects
    // the correct `isa_riscv_start` module based on arch/feature selection.
    // (e.g. vector-enabled `_start` vs non-vector `_start`).

    return entry_mod;
}

pub fn configureExecutable(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.setLinkerScript(b.path("isa/riscv/linker_common.x"));
    exe.entry = .{ .symbol_name = "_start" };
}

fn containsChar(flags: []const u8, ch: u8) bool {
    for (flags) |c| {
        if (c == ch) return true;
    }
    return false;
}

fn containsSubstring(flags: []const u8, substr: []const u8) bool {
    return std.mem.indexOf(u8, flags, substr) != null;
}

fn hasVectorFlag(flags: []const u8) bool {
    if (containsChar(flags, 'v')) return true;
    return containsSubstring(flags, "zv");
}

fn parseZvlBitsLowerBound(flags: []const u8) ?usize {
    // Parse `zvl<NNN>b` from a feature profile string like "im_zve32x_zvl128b".
    // Returns the numeric bit lower bound (e.g. 128), or null if not present.
    //
    // Multiple `zvl*` occurrences are invalid and will hard-fail, because they imply
    // conflicting minimum VLEN requirements.
    const prefix = "zvl";
    const suffix = "b";

    var found: ?usize = null;

    var i: usize = 0;
    while (i + prefix.len <= flags.len) : (i += 1) {
        if (!std.mem.startsWith(u8, flags[i..], prefix)) continue;

        var j = i + prefix.len;

        // Must have at least 1 digit.
        if (j >= flags.len or flags[j] < '0' or flags[j] > '9') continue;

        var value: usize = 0;
        while (j < flags.len) : (j += 1) {
            const ch = flags[j];
            if (ch < '0' or ch > '9') break;
            value = value * 10 + @as(usize, ch - '0');
        }

        // Must end with trailing 'b'.
        if (j < flags.len and std.mem.startsWith(u8, flags[j..], suffix)) {
            if (found != null) {
                std.debug.panic("Invalid feature profile: multiple zvl* occurrences in: {s}", .{flags});
            }
            found = value;
        }
    }

    return found;
}

fn remuCpuForFeatureFlags(allocator: std.mem.Allocator, flags: []const u8) []const u8 {
    // Start with the base ISA
    var isa = allocator.dupe(u8, "riscv32") catch return "rv32";

    // Check for single-letter extensions (e.g., "m")
    var i: usize = 0;
    while (i < flags.len and flags[i] >= 'a' and flags[i] <= 'z') : (i += 1) {
        const new_isa = std.mem.concat(allocator, u8, &.{ isa, flags[i .. i + 1] }) catch return "rv32";
        isa = new_isa;
    }

    // Check for multi-letter extensions (e.g., "zve32x", "zvl128b")
    while (i < flags.len) {
        if (flags[i] == '_') {
            const start = i + 1;
            i += 1;
            while (i < flags.len and flags[i] != '_') i += 1;

            // Ensure start is less than or equal to i
            if (start < i) {
                const new_isa = std.mem.concat(allocator, u8, &.{ isa, "_", flags[start..i] }) catch return "rv32";
                isa = new_isa;
            }
        } else {
            i += 1;
        }
    }

    return isa;
}

pub fn addPlatformSteps(b: *std.Build, feature_profile: ?[]const u8, exe_base_name: []const u8, exe: *std.Build.Step.Compile) void {
    _ = exe_base_name;

    const chosen_flags = feature_profile orelse std.debug.panic("Missing required -Dfeature for platform=remu", .{});

    const cpu_config = remuCpuForFeatureFlags(b.allocator, chosen_flags);

    const abs_elf_path = b.fmt("{s}/zig-out/remu/{s}", .{ b.pathFromRoot("."), exe.name });
    const run_remu = b.addSystemCommand(&.{
        "direnv",
        "exec",
        "../remu",
        "just",
        "--justfile",
        "../remu/justfile",
        "dev",
        "--",
        "--isa",
        cpu_config,
        "--mem",
        "ram@0x8000_0000:0x8800_0000",
        "--elf",
        abs_elf_path,
    });

    run_remu.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_remu.step);
}

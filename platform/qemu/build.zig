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
        .root_source_file = b.path("platform/qemu/runtime.zig"),
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

fn qemuCpuForFeatureFlags(allocator: std.mem.Allocator, flags: []const u8) []const u8 {
    const has_m = containsChar(flags, 'm');
    const has_a = containsChar(flags, 'a');
    const has_f = containsChar(flags, 'f');
    const has_d = containsChar(flags, 'd');
    const has_c = containsChar(flags, 'c');
    const has_vector = hasVectorFlag(flags);

    var parts: [8][]const u8 = undefined;
    var part_count: usize = 0;

    parts[part_count] = "rv32";
    part_count += 1;

    if (has_m) {
        parts[part_count] = "m=true";
        part_count += 1;
    }
    if (has_a) {
        parts[part_count] = "a=true";
        part_count += 1;
    }
    if (has_f) {
        parts[part_count] = "f=true";
        part_count += 1;
    }
    if (has_d) {
        parts[part_count] = "d=true";
        part_count += 1;
    }
    if (has_c) {
        parts[part_count] = "c=true";
        part_count += 1;
    }
    if (has_vector) {
        parts[part_count] = "v=true";
        part_count += 1;

        const vlen_bits = parseZvlBitsLowerBound(flags) orelse 128;
        const vlen_opt = std.fmt.allocPrint(allocator, "vlen={d}", .{vlen_bits}) catch "vlen=128";
        parts[part_count] = vlen_opt;
        part_count += 1;
    }

    const total_len = blk: {
        var len: usize = 0;
        for (parts[0..part_count]) |part| {
            len += part.len + 1;
        }
        break :blk len;
    };

    const cpu_str = allocator.alloc(u8, total_len) catch return "rv32";
    var pos: usize = 0;

    for (parts[0..part_count], 0..) |part, i| {
        if (i == 0) {
            @memcpy(cpu_str[pos .. pos + part.len], part);
            pos += part.len;
        } else {
            cpu_str[pos] = ',';
            pos += 1;
            @memcpy(cpu_str[pos .. pos + part.len], part);
            pos += part.len;
        }
    }

    return cpu_str[0..pos];
}

pub fn addPlatformSteps(b: *std.Build, feature_profile: ?[]const u8, exe_base_name: []const u8, exe: *std.Build.Step.Compile) void {
    _ = exe_base_name;

    const chosen_flags = feature_profile orelse std.debug.panic("Missing required -Dfeature for platform=qemu", .{});

    const cpu_config = qemuCpuForFeatureFlags(b.allocator, chosen_flags);

    const run_qemu = b.addSystemCommand(&.{
        "qemu-system-riscv32",
        "-machine",
        "virt",
        "-cpu",
        cpu_config,
        "-m",
        "128M",
        "-nographic",
        "-serial",
        "mon:stdio",
        "-bios",
        "none",
        "-kernel",
    });
    run_qemu.addFileArg(exe.getEmittedBin());
    run_qemu.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_qemu.step);
}

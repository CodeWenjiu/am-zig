const std = @import("std");

pub fn entryModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    app_mod: *std.Build.Module,
) *std.Build.Module {
    const entry_mod = b.createModule(.{
        .root_source_file = b.path("platform/qemu/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const isa_riscv_start_pkg = b.createModule(.{
        .root_source_file = b.path("isa/riscv/start.zig"),
        .target = target,
        .optimize = optimize,
    });
    entry_mod.addImport("app", app_mod);
    entry_mod.addImport("isa_riscv_start", isa_riscv_start_pkg);
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

fn qemuCpuForFeatureFlags(allocator: std.mem.Allocator, flags: []const u8) []const u8 {
    const has_m = containsChar(flags, 'm');
    const has_a = containsChar(flags, 'a');
    const has_f = containsChar(flags, 'f');
    const has_d = containsChar(flags, 'd');
    const has_c = containsChar(flags, 'c');
    const has_zve = containsSubstring(flags, "zve");

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
    if (has_zve) {
        parts[part_count] = "v=true";
        part_count += 1;
        parts[part_count] = "vlen=128";
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

pub fn addPlatformSteps(b: *std.Build, feature_profile: ?[]const u8, exe: *std.Build.Step.Compile) void {
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

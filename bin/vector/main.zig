const std = @import("std");

fn vector_add(a: []const u32, b: []const u32, c: []u32) void {
    // Minimal checks to keep behavior sane; remove if you want pure "benchmark" style.
    std.debug.assert(a.len == b.len);
    std.debug.assert(c.len == a.len);

    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        c[i] = a[i] + b[i];
    }
}

fn vector_dot(a: []const u32, b: []const u32) u32 {
    std.debug.assert(a.len == b.len);

    var sum: u32 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        sum +%= a[i] *% b[i];
    }
    return sum;
}

fn matrix_mult(a: []const u32, b: []const u32, c: []u32, n: usize) void {
    // a, b, c are row-major n*n.
    std.debug.assert(a.len == n * n);
    std.debug.assert(b.len == n * n);
    std.debug.assert(c.len == n * n);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        var j: usize = 0;
        while (j < n) : (j += 1) {
            var sum: u32 = 0;
            var k: usize = 0;
            while (k < n) : (k += 1) {
                const av = a[i * n + k];
                const bv = b[k * n + j];
                sum +%= av *% bv;
            }
            c[i * n + j] = sum;
        }
    }
}

pub fn main() !void {
    const a = [_]u32{ 1, 2, 3, 4 };
    const b = [_]u32{ 5, 6, 7, 8 };
    var c = [_]u32{ 0, 0, 0, 0 };

    vector_add(a[0..], b[0..], c[0..]);
    std.log.info("Vector Add: {any}", .{c});

    const dot = vector_dot(a[0..], b[0..]);
    std.log.info("Vector Dot: {d}", .{dot});

    const m1 = [_]u32{ 1, 2, 3, 4 };
    const m2 = [_]u32{ 5, 6, 7, 8 };
    var m3 = [_]u32{ 0, 0, 0, 0 };

    matrix_mult(m1[0..], m2[0..], m3[0..], 2);
    std.log.info("Matrix Mult: {any}", .{m3});
}

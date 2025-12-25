const std = @import("std");
const app = @import("app");

pub fn main() !void {
    const ReturnType = @typeInfo(@TypeOf(app.main)).Fn.return_type.?;

    if (ReturnType == void) {
        app.main();
    } else {
        try app.main();
    }
}

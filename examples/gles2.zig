const run = @import("support/run.zig");

pub fn main() !void {
    try run.egl("OpenGL ES 2 context", .{
        .flags = .{ .centered = true, .translucent = true },
    }, null);
}

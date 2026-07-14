const run = @import("support/run.zig");

pub fn main() !void {
    try run.egl("EGL context", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true, .no_resize = true, .translucent = true },
    }, null);
}

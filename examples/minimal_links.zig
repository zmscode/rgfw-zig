const run = @import("support/run.zig");

pub fn main() !void {
    try run.window("Minimal RGFW links", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true, .no_resize = true },
    }, null);
}

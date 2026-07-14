const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("Monitor information", .{
        .flags = .{ .centered = true },
    }, showMonitor);
}

var printed = false;

fn showMonitor(window: *rgfw.Window) void {
    if (printed) return;
    var monitor = window.monitor() orelse return;
    const area = monitor.workArea();
    std.debug.print("Monitor {s}: {d}x{d} at {d},{d}\n", .{
        monitor.name(),
        area.width,
        area.height,
        area.x,
        area.y,
    });
    printed = true;
}

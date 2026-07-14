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
    const area = monitor.workArea() catch return;
    const mode = monitor.currentMode() catch return;
    const scale = monitor.scale() catch return;
    const modes = monitor.supportedModes(std.heap.smp_allocator) catch return;
    defer std.heap.smp_allocator.free(modes);
    const name = monitor.name() orelse "unnamed";
    std.debug.print("Monitor {s}: {d}x{d} at {d},{d}, scale {d:.2}x{d:.2}, {d} modes\n", .{
        name,
        mode.width,
        mode.height,
        area.x,
        area.y,
        scale.x,
        scale.y,
        modes.len,
    });
    printed = true;
}

const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("Clipboard", .{
        .flags = .{ .centered = true },
    }, update);
}

fn update(window: *rgfw.Window) void {
    const control = window.keyDown(.control_left) or window.keyDown(.control_right);
    if (control and window.keyPressed(.c)) {
        rgfw.Clipboard.write(.text, "Copied from rgfw-zig") catch
            std.debug.print("Clipboard write failed.\n", .{});
    }
    if (control and window.keyPressed(.v)) {
        const text = rgfw.Clipboard.readTextAlloc(std.heap.smp_allocator) catch return;
        defer std.heap.smp_allocator.free(text);
        std.debug.print("Clipboard: {s}\n", .{text});
    }
}

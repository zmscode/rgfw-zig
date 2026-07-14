const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("Native backend handle", .{
        .flags = .{ .centered = true },
    }, showNativeHandle);
}

var printed = false;

fn showNativeHandle(window: *rgfw.Window) void {
    if (printed) return;
    const native = window.nativeHandle() catch return;
    switch (native) {
        .cocoa => |handle| std.debug.print("NSView: {*}\n", .{handle.view}),
        .win32 => |handle| std.debug.print("HWND: {*}\n", .{handle.hwnd}),
        .x11 => |handle| std.debug.print("X11 window: {d}\n", .{handle}),
        .wayland => |handle| std.debug.print("wl_surface: {*}\n", .{handle}),
        .custom => |handle| std.debug.print("custom backend source: {*}\n", .{handle}),
    }
    printed = true;
}

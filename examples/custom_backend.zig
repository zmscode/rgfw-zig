const builtin = @import("builtin");
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
    const handle = window.handle orelse return;
    switch (builtin.os.tag) {
        .macos => std.debug.print("NSView: {?}\n", .{rgfw.raw.RGFW_window_getView_OSX(handle)}),
        .windows => std.debug.print("HWND: {?}\n", .{rgfw.raw.RGFW_window_getHWND(handle)}),
        else => std.debug.print("X11 window: {d}\n", .{
            rgfw.raw.RGFW_window_getWindow_X11(handle),
        }),
    }
    printed = true;
}

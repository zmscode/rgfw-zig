const builtin = @import("builtin");
const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    if (builtin.os.tag != .windows) return error.DirectXRequiresWindows;
    try @import("support/run.zig").window("DirectX 11 interop", .{
        .flags = .{ .centered = true },
    }, showWindowHandle);
}

var printed = false;

fn showWindowHandle(window: *rgfw.Window) void {
    if (printed) return;
    const handle = window.handle orelse return;
    std.debug.print("Create the DXGI swapchain for HWND {?}.\n", .{
        rgfw.raw.RGFW_window_getHWND(handle),
    });
    printed = true;
}

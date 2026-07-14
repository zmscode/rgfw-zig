const builtin = @import("builtin");
const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    if (builtin.os.tag != .macos) return error.MetalRequiresMacOS;
    try @import("support/run.zig").window("Metal interop", .{
        .width = 640,
        .height = 480,
        .flags = .{ .centered = true },
    }, showView);
}

var printed = false;

fn showView(window: *rgfw.Window) void {
    if (printed) return;
    const native = window.nativeHandleAs(.cocoa) catch return;
    std.debug.print("Attach CAMetalLayer to NSView {*}.\n", .{native.view});
    printed = true;
}

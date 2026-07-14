const builtin = @import("builtin");
const std = @import("std");
const rgfw = @import("rgfw");

const IDXGIFactory = opaque {};
const IUnknownDevice = opaque {};
const IDXGISwapChain = opaque {};

/// Real applications use the equivalent COM types from their DirectX package.
fn createSwapChain(
    window: *rgfw.Window,
    factory: *IDXGIFactory,
    device: *IUnknownDevice,
) !*IDXGISwapChain {
    return rgfw.DirectX.createSwapChain(*IDXGISwapChain, window, factory, device);
}

pub fn main() !void {
    if (builtin.os.tag != .windows) return error.DirectXRequiresWindows;
    _ = createSwapChain;
    try @import("support/run.zig").window("DirectX 11 interop", .{
        .flags = .{ .centered = true },
    }, showWindowHandle);
}

var printed = false;

fn showWindowHandle(window: *rgfw.Window) void {
    if (printed) return;
    const native = window.nativeHandleAs(.win32) catch return;
    std.debug.print("Create the DXGI swapchain for HWND {*}.\n", .{native.hwnd});
    printed = true;
}

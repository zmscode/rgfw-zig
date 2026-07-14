const std = @import("std");
const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    var context = try rgfw.init("gamma", .{ .backend = .opengl });
    defer context.deinit();
    var window = try context.createWindow("Monitor gamma", .{
        .flags = .{ .centered = true, .open_gl = true },
    });
    defer window.deinit();
    var monitor = window.monitor() orelse return error.MonitorUnavailable;
    var original_ramp = try monitor.gammaRamp(std.heap.smp_allocator);
    defer original_ramp.deinit(std.heap.smp_allocator);
    try monitor.setGamma(0.8);
    // Best-effort restoration during shutdown; there is no useful recovery path here.
    defer monitor.setGamma(1.0) catch {};

    rgfw.OpenGL.makeCurrent(&window);
    while (window.isOpen()) {
        window.pumpEvents();
        gl.clear(&window, .{ 0.20, 0.20, 0.20, 1.0 });
        rgfw.OpenGL.swapBuffers(&window);
    }
}

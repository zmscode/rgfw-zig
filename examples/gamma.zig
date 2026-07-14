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
    if (!monitor.setGamma(0.8)) return error.GammaChangeFailed;
    defer _ = monitor.setGamma(1.0);

    rgfw.OpenGL.makeCurrent(&window);
    while (!window.shouldClose()) {
        rgfw.pollEvents();
        gl.clear(&window, .{ 0.20, 0.20, 0.20, 1.0 });
        rgfw.OpenGL.swapBuffers(&window);
    }
}

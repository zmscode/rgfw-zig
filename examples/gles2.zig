const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("rgfw-zig-gles2", .{ .backend = .egl });
    defer context.deinit();

    var window = try context.createWindow("OpenGL ES 2 context", .{
        .flags = .{ .centered = true, .translucent = true },
    });
    defer window.deinit();

    const graphics_context = try rgfw.EGL.createContext(&window, .{
        .hints = .{ .profile = .embedded, .major_version = 2, .minor_version = 0 },
    });
    rgfw.EGL.makeCurrent(&window);
    if (rgfw.EGL.getContext(&window).?.rawHandle() != graphics_context.rawHandle()) {
        return error.UnexpectedContext;
    }
    rgfw.EGL.swapInterval(&window, 1);
    while (window.isOpen()) {
        window.pumpEvents();
        rgfw.EGL.swapBuffers(&window);
    }
}

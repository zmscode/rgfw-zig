const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    var context = try rgfw.init("rgfw-zig-gl33", .{ .backend = .opengl });
    defer context.deinit();

    var window = try context.createWindow("Explicit OpenGL 3.3 context", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();

    const graphics_context = try rgfw.OpenGL.createContext(&window, .{
        .hints = .{ .profile = .core, .major_version = 3, .minor_version = 3 },
    });
    rgfw.OpenGL.makeCurrent(&window);
    if (rgfw.OpenGL.getContext(&window).?.rawHandle() != graphics_context.rawHandle()) {
        return error.UnexpectedContext;
    }
    rgfw.OpenGL.swapInterval(&window, 1);
    while (window.isOpen()) {
        window.pumpEvents();
        draw(&window);
        rgfw.OpenGL.swapBuffers(&window);
    }
}

fn draw(window: *rgfw.Window) void {
    gl.clear(window, .{ 0.04, 0.22, 0.12, 1.0 });
}

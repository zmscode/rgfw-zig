const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    var context = try rgfw.init("first-person-camera", .{ .backend = .opengl });
    defer context.deinit();
    var window = try context.createWindow("First-person input", .{
        .width = 800,
        .height = 450,
        .flags = .{
            .centered = true,
            .no_resize = true,
            .focus_on_show = true,
            .open_gl = true,
            .hide_mouse = true,
        },
    });
    defer window.deinit();
    window.setRawMouseMode(true);
    defer window.setRawMouseMode(false);

    rgfw.OpenGL.makeCurrent(&window);
    while (!window.shouldClose()) {
        rgfw.pollEvents();
        var movement: f32 = 0;
        if (window.keyDown(.w)) movement += 0.2;
        if (window.keyDown(.s)) movement -= 0.2;
        const mouse = rgfw.Input.mouseVector();
        const red = @min(1.0, @abs(mouse.x) / 100.0);
        gl.clear(&window, .{ red, 0.2 + movement, 0.25, 1.0 });
        rgfw.OpenGL.swapBuffers(&window);
    }
}

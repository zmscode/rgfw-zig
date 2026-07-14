const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    try @import("support/run.zig").openGL("Explicit OpenGL context", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true, .no_resize = true },
    }, draw);
}

fn draw(window: *rgfw.Window) void {
    gl.clear(window, .{ 0.04, 0.22, 0.12, 1.0 });
}

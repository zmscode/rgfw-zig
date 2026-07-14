const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    try @import("support/run.zig").openGL("OpenGL 3.3", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true, .scale_to_monitor = true },
    }, draw);
}

fn draw(window: *rgfw.Window) void {
    gl.clear(window, .{ 0.18, 0.08, 0.22, 1.0 });
}

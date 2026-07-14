const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    try @import("support/run.zig").openGL("OpenGL 1.1", .{
        .flags = .{ .centered = true },
    }, draw);
}

fn draw(window: *rgfw.Window) void {
    gl.clear(window, .{ 0.10, 0.16, 0.24, 1.0 });
}

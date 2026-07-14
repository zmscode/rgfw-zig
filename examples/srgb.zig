const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    try @import("support/run.zig").openGL("sRGB framebuffer", .{
        .flags = .{ .centered = true },
    }, draw);
}

fn draw(window: *rgfw.Window) void {
    gl.clear(window, .{ 0.214, 0.214, 0.214, 1.0 });
}

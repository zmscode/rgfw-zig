const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    try @import("support/run.zig").openGL("Smooth resize", .{
        .width = 500,
        .height = 300,
        .flags = .{ .centered = true },
    }, draw);
}

fn draw(window: *rgfw.Window) void {
    const size = window.sizeInPixels();
    const red = @as(f32, @floatFromInt(@mod(size.width, 255))) / 255.0;
    const green = @as(f32, @floatFromInt(@mod(size.height, 255))) / 255.0;
    gl.clear(window, .{ red, green, 0.3, 1.0 });
}

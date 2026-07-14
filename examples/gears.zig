const rgfw = @import("rgfw");
const gl = @import("support/opengl.zig");

pub fn main() !void {
    try @import("support/run.zig").openGL("Animated gears", .{
        .flags = .{ .centered = true },
    }, draw);
}

var frame_index: u32 = 0;

fn draw(window: *rgfw.Window) void {
    frame_index +%= 1;
    const phase: f32 = @floatFromInt(frame_index % 240);
    const red = phase / 240.0;
    gl.clear(window, .{ red, 0.15, 0.35 - red * 0.2, 1.0 });
}

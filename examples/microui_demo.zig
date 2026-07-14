const software = @import("support/software.zig");

pub fn main() !void {
    try software.run("microui-style panels", draw);
}

fn draw(pixels: []u8, frame_index: u32) void {
    _ = frame_index;
    @memset(pixels, 35);
    panel(pixels, .{ .x = 30, .y = 30, .width = 210, .height = 180 }, .{ 65, 75, 95, 255 });
    panel(pixels, .{ .x = 260, .y = 80, .width = 210, .height = 300 }, .{ 85, 65, 85, 255 });
    panel(pixels, .{ .x = 50, .y = 240, .width = 170, .height = 100 }, .{ 55, 95, 75, 255 });
}

const Panel = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
};

fn panel(pixels: []u8, bounds: Panel, color: [4]u8) void {
    const stride: usize = @intCast(software.width);
    for (bounds.y..bounds.y + bounds.height) |y| {
        for (bounds.x..bounds.x + bounds.width) |x| {
            const offset = (y * stride + x) * 4;
            pixels[offset..][0..4].* = color;
        }
    }
}

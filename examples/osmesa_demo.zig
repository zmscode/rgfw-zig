const software = @import("support/software.zig");

pub fn main() !void {
    // This keeps the upstream example's CPU framebuffer presentation path.
    try software.run("Off-screen software rendering", draw);
}

fn draw(pixels: []u8, frame_index: u32) void {
    @memset(pixels, 0);
    const square_size: usize = 160;
    const frame_offset: usize = frame_index % 200;
    for (0..square_size) |y| {
        for (0..square_size) |x| {
            const pixel_x = x + frame_offset;
            const pixel_y = y + 170;
            const index = (pixel_y * @as(usize, software.width) + pixel_x) * 4;
            pixels[index..][0..4].* = .{ 240, 80, 70, 255 };
        }
    }
}

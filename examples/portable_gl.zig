const software = @import("support/software.zig");

pub fn main() !void {
    try software.run("PortableGL-style triangle", draw);
}

fn draw(pixels: []u8, frame_index: u32) void {
    _ = frame_index;
    @memset(pixels, 24);
    const width: usize = @intCast(software.width);
    const height: usize = @intCast(software.height);
    for (0..height) |y| {
        const half_width = y / 2;
        const center = width / 2;
        const start = center - @min(center, half_width);
        const end = @min(width, center + half_width);
        for (start..end) |x| {
            const offset = (y * width + x) * 4;
            pixels[offset..][0..4].* = .{ 40, @truncate(y), @truncate(x), 255 };
        }
    }
}

const std = @import("std");
const software = @import("support/software.zig");

pub fn main() !void {
    // Zig owns the framebuffer allocation, making its lifetime explicit.
    try software.run("Zig allocator ownership", draw);
}

fn draw(pixels: []u8, frame_index: u32) void {
    std.debug.assert(pixels.len == software.pixel_count * software.bytes_per_pixel);
    software.gradient(pixels, frame_index);
}

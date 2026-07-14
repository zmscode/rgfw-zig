const std = @import("std");
const rgfw = @import("rgfw");
const software = @import("support/software.zig");

pub fn main() !void {
    var hooks = rgfw.AllocatorHooks.init(std.heap.smp_allocator);
    hooks.install();
    defer rgfw.AllocatorHooks.uninstall();

    // Both RGFW resources and the framebuffer now use Zig allocators.
    try software.run("Zig allocator ownership", draw);
}

fn draw(pixels: []u8, frame_index: u32) void {
    std.debug.assert(pixels.len == software.pixel_count * software.bytes_per_pixel);
    software.gradient(pixels, frame_index);
}

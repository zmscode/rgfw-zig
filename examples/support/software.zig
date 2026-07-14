const std = @import("std");
const rgfw = @import("rgfw");

pub const width: i32 = 500;
pub const height: i32 = 500;
pub const bytes_per_pixel: usize = 4;
pub const pixel_count: usize = @as(usize, width) * @as(usize, height);

pub fn run(title: [:0]const u8, draw: *const fn ([]u8, u32) void) !void {
    var context = try rgfw.init("rgfw-zig-software-example", .{});
    defer context.deinit();

    var window = try context.createWindow(title, .{
        .width = width,
        .height = height,
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();

    const gpa = std.heap.c_allocator;
    const pixels = try gpa.alloc(u8, pixel_count * bytes_per_pixel);
    defer gpa.free(pixels);

    var surface = try rgfw.Surface.init(pixels, width, height, .rgba8);
    defer surface.deinit();

    var frame_index: u32 = 0;
    while (!window.shouldClose()) : (frame_index +%= 1) {
        rgfw.pollEvents();
        while (window.nextEvent()) |event| {
            if (event.kind() == .window_close) window.requestClose();
        }
        draw(pixels, frame_index);
        surface.blit(&window);
    }
}

pub fn gradient(pixels: []u8, frame_index: u32) void {
    for (0..pixel_count) |index| {
        const x: u32 = @intCast(index % @as(usize, width));
        const y: u32 = @intCast(index / @as(usize, width));
        const offset = index * bytes_per_pixel;
        pixels[offset + 0] = @truncate(x + frame_index);
        pixels[offset + 1] = @truncate(y + frame_index);
        pixels[offset + 2] = @truncate(x + y);
        pixels[offset + 3] = 255;
    }
}

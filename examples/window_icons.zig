const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("window-icons", .{});
    defer context.deinit();
    var window = try context.createWindow("Procedural window icon", .{
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();

    var pixels = iconPixels();
    const handle = window.handle orelse return error.WindowClosed;
    if (rgfw.raw.RGFW_window_setIconEx(
        handle,
        &pixels,
        @intCast(icon_size),
        @intCast(icon_size),
        @intFromEnum(rgfw.ImageFormat.rgba8),
        @intCast(rgfw.raw.RGFW_iconBoth),
    ) == 0) return error.IconAssignmentFailed;

    while (!window.shouldClose()) rgfw.pollEvents();
}

const icon_size: usize = 16;

fn iconPixels() [icon_size * icon_size * 4]u8 {
    var pixels: [icon_size * icon_size * 4]u8 = undefined;
    for (0..icon_size * icon_size) |index| {
        const offset = index * 4;
        const x = index % icon_size;
        const y = index / icon_size;
        const inside = x > 2 and x < 13 and y > 2 and y < 13;
        pixels[offset..][0..4].* = if (inside)
            .{ 70, 150, 255, 255 }
        else
            .{ 0, 0, 0, 0 };
    }
    return pixels;
}

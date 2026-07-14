const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("mouse-icons", .{});
    defer context.deinit();
    var window = try context.createWindow("Custom mouse icon", .{
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();

    var pixels = checkerboard();
    const mouse = rgfw.raw.RGFW_createMouse(
        &pixels,
        @intCast(icon_size),
        @intCast(icon_size),
        @intFromEnum(rgfw.ImageFormat.rgba8),
    ) orelse return error.MouseCreationFailed;
    defer rgfw.raw.RGFW_freeMouse(mouse);
    if (rgfw.raw.RGFW_window_setMouse(window.handle, mouse) == 0) {
        return error.MouseAssignmentFailed;
    }

    while (!window.shouldClose()) {
        rgfw.pollEvents();
        while (window.nextEvent()) |_| {}
        if (window.keyPressed(.space)) window.showMouse(false);
        if (window.keyReleased(.space)) window.showMouse(true);
    }
}

const icon_size: usize = 16;

fn checkerboard() [icon_size * icon_size * 4]u8 {
    var pixels: [icon_size * icon_size * 4]u8 = undefined;
    for (0..icon_size * icon_size) |index| {
        const offset = index * 4;
        const light = ((index % icon_size) + (index / icon_size)) % 2 == 0;
        const value: u8 = if (light) 255 else 32;
        pixels[offset..][0..4].* = .{ value, 80, 255 - value, 255 };
    }
    return pixels;
}

const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("RGFW Zig example", .{});
    defer context.deinit();

    var window = try context.createWindow("RGFW Zig example", .{
        .flags = .{
            .centered = true,
            .no_resize = true,
        },
    });
    defer window.deinit();

    while (!window.shouldClose()) {
        rgfw.pollEvents();
        while (window.nextEvent()) |event| {
            if (event.kind() == .window_close) window.requestClose();
        }
    }
}

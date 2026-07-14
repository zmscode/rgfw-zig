const rgfw = @import("rgfw");

pub fn main() !void {
    // No Zig standard-library facilities are needed for this event loop.
    var context = try rgfw.init("no-zig-stdlib-usage", .{});
    defer context.deinit();
    var window = try context.createWindow("No Zig std usage", .{
        .width = 300,
        .height = 180,
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();
    while (!window.shouldClose()) {
        rgfw.pollEvents();
    }
}

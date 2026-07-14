const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("multi-window", .{});
    defer context.deinit();

    var first = try context.createWindow("Window one", .{
        .x = 100,
        .y = 100,
        .width = 500,
        .height = 400,
    });
    defer first.deinit();
    var second = try context.createWindow("Window two", .{
        .x = 650,
        .y = 100,
        .width = 300,
        .height = 240,
        .flags = .{ .no_resize = true },
    });
    defer second.deinit();

    while (!first.shouldClose() and !second.shouldClose()) {
        rgfw.pollEvents();
        processEvents(&first);
        processEvents(&second);
    }
}

fn processEvents(window: *rgfw.Window) void {
    while (window.nextEvent()) |_| {}
}

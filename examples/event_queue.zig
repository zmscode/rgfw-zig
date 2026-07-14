const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("event-queue", .{});
    defer context.deinit();
    var window = try context.createWindow("Event queue", .{
        .flags = .{ .centered = true, .allow_drag_and_drop = true },
    });
    defer window.deinit();

    while (window.isOpen()) {
        context.waitForNextEvent();
        context.pollEvents();
        var events = window.events();
        while (events.next()) |event| {
            std.debug.print("Queued event: {s}\n", .{@tagName(event.payload())});
        }
    }
}

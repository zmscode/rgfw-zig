const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("callbacks", .{});
    defer context.deinit();
    var window = try context.createWindow("Callbacks", .{
        .flags = .{ .centered = true, .allow_drag_and_drop = true },
    });
    defer window.deinit();

    const raw = rgfw.raw;
    const event_types = [_]raw.RGFW_eventType{
        @intCast(raw.RGFW_windowMoved),
        @intCast(raw.RGFW_windowResized),
        @intCast(raw.RGFW_windowClose),
        @intCast(raw.RGFW_keyPressed),
        @intCast(raw.RGFW_keyReleased),
        @intCast(raw.RGFW_mouseButtonPressed),
        @intCast(raw.RGFW_mouseButtonReleased),
        @intCast(raw.RGFW_monitorConnected),
        @intCast(raw.RGFW_monitorDisconnected),
    };
    for (event_types) |event_type| {
        _ = raw.RGFW_setEventCallback(event_type, eventCallback);
    }

    while (!window.shouldClose()) {
        rgfw.pollEvents();
        while (window.nextEvent()) |event| {
            if (event.kind() == .window_close) window.requestClose();
        }
    }
}

fn eventCallback(event: [*c]const rgfw.raw.RGFW_event) callconv(.c) void {
    if (event == null) return;
    std.debug.print("RGFW event: {d}\n", .{event.*.type});
}

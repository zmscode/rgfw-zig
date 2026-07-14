const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("callbacks", .{});
    defer context.deinit();
    var window = try context.createWindow("Callbacks", .{
        .flags = .{ .centered = true, .allow_drag_and_drop = true },
    });
    defer window.deinit();

    var state: CallbackState = .{};

    var moved = try context.on(rgfw.callback.window_moved, windowMoved);
    defer moved.deinit();
    var resized = try context.onWithContext(
        rgfw.callback.window_resized,
        &state,
        windowResized,
    );
    defer resized.deinit();
    var key_pressed = try context.on(rgfw.callback.key_pressed, keyPressed);
    defer key_pressed.deinit();
    var closed = try context.on(rgfw.callback.window_close, windowClosed);
    defer closed.deinit();

    while (window.isOpen()) window.pumpEvents();
}

fn windowMoved(position: rgfw.Point) void {
    std.debug.print("moved to {d}, {d}\n", .{ position.x, position.y });
}

const CallbackState = struct {
    resize_count: usize = 0,
};

fn windowResized(state: *CallbackState, size: rgfw.Size) void {
    state.resize_count += 1;
    std.debug.print("resize #{d}: {d} x {d}\n", .{
        state.resize_count,
        size.width,
        size.height,
    });
}

fn keyPressed(key: rgfw.KeyEvent) void {
    std.debug.print("key pressed: {s}\n", .{@tagName(key.key)});
}

fn windowClosed() void {
    std.debug.print("window closed\n", .{});
}

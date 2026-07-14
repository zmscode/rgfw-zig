const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("Standard cursors", .{
        .flags = .{ .centered = true, .no_resize = true },
    }, update);
}

var cursor_index: usize = 0;

fn update(window: *rgfw.Window) void {
    if (!window.mousePressed(.left)) return;
    const cursors = [_]rgfw.Cursor{
        .arrow,
        .text,
        .crosshair,
        .pointing_hand,
        .resize_horizontal,
        .resize_vertical,
        .not_allowed,
        .wait,
    };
    cursor_index = (cursor_index + 1) % cursors.len;
    _ = window.setStandardCursor(cursors[cursor_index]);
}

const std = @import("std");
const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("State checking", .{
        .flags = .{ .centered = true, .allow_drag_and_drop = true },
    }, update);
}

fn update(window: *rgfw.Window) void {
    if (!window.keyPressed(.space)) return;
    const position = window.position();
    const size = window.size();
    const mouse = window.mousePosition();
    const vector = rgfw.Input.mouseVector();
    const scroll = rgfw.Input.mouseScroll();
    std.debug.print(
        "position={d},{d} size={d}x{d} mouse={d},{d} delta={d:.1},{d:.1} " ++
            "scroll={d:.1},{d:.1} focus={} fullscreen={}\n",
        .{
            position.x,
            position.y,
            size.width,
            size.height,
            mouse.x,
            mouse.y,
            vector.x,
            vector.y,
            scroll.x,
            scroll.y,
            window.focused(),
            window.fullscreen(),
        },
    );
}

const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("Window flags", .{
        .flags = .{ .centered = true, .allow_drag_and_drop = true },
    }, update);
}

fn update(window: *rgfw.Window) void {
    if (window.keyPressed(.b)) window.setBorder(window.borderless());
    if (window.keyPressed(.d)) window.setDragAndDrop(!window.allowsDragAndDrop());
    if (window.keyPressed(.f)) window.setFullscreen(!window.fullscreen());
    if (window.keyPressed(.m)) {
        if (window.maximized()) window.restore() else window.maximize();
    }
    if (window.keyPressed(.h)) {
        if (window.hidden()) window.show() else window.hide();
    }
    if (window.keyPressed(.c)) window.center();
}

const rgfw = @import("rgfw");

pub fn main() !void {
    try @import("support/run.zig").window("Window flash", .{
        .flags = .{ .centered = true },
    }, update);
}

fn update(window: *rgfw.Window) void {
    if (window.keyPressed(.space)) {
        const request: rgfw.FlashRequest = if (window.focused()) .briefly else .until_focused;
        window.flash(request);
    }
}

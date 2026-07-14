const rgfw = @import("rgfw");

fn wrongHandler(_: u32) void {}

test "typed event handlers reject the wrong payload" {
    var context: rgfw.Context = undefined;
    _ = context.on(rgfw.callback.window_resized, wrongHandler) catch unreachable;
}

const rgfw = @import("rgfw");

test "native handle requests must match the configured window system" {
    const wrong: rgfw.WindowSystem = switch (rgfw.window_system) {
        .cocoa => .win32,
        else => .cocoa,
    };
    var window: rgfw.Window = .{ .handle = null };
    _ = window.nativeHandleAs(wrong) catch {};
}

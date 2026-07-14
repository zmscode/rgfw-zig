const rgfw = @import("rgfw");

const ForeignInstanceOpaque = opaque {};
const ForeignSurfaceOpaque = opaque {};
const ForeignInstance = ?*ForeignInstanceOpaque;
const ForeignSurface = ?*ForeignSurfaceOpaque;

/// A WebGPU package can pass its own opaque handle types without application casts.
fn createSurface(window: *rgfw.Window, instance: ForeignInstance) !ForeignSurface {
    return rgfw.WebGPU.createSurfaceAs(ForeignSurface, window, instance);
}

pub fn main() !void {
    _ = createSurface;
    var context = try rgfw.init("rgfw-zig-webgpu", .{});
    defer context.deinit();
    var window = try context.createWindow("WebGPU surface interop", .{
        .flags = .{ .centered = true },
    });
    defer window.deinit();
    while (window.isOpen()) window.pumpEvents();
}

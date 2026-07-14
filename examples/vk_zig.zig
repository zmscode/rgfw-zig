const rgfw = @import("rgfw");
const vk = @import("vulkan");

pub fn main() !void {
    var context = try rgfw.init("rgfw-vk-zig", .{ .backend = .vulkan });
    defer context.deinit();

    var window = try context.createWindow("RGFW + vk-zig", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true },
    });
    defer window.deinit();

    var loader = try vk.Loader.init();
    defer loader.deinit();
    const entry = try loader.entry();

    var extensions: vk.ExtensionSet(4) = .{};
    try rgfw.Vulkan.appendRequiredInstanceExtensions(&extensions);
    try extensions.appendAll(vk.Portability.instanceExtensions());

    var instance = try entry.createInstance(.{
        .application_name = "rgfw-vk-zig",
        .engine_name = "rgfw-zig",
        .extensions = extensions.slice(),
        .enumerate_portability = vk.platform == .metal,
    });
    defer instance.deinit();

    var surface = try rgfw.Vulkan.createOwnedSurfaceAs(
        vk.raw.VkSurfaceKHR,
        &window,
        &instance,
    );
    defer surface.deinit();

    while (window.isOpen()) window.pumpEvents();
}

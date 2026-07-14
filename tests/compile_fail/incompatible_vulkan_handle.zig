const rgfw = @import("rgfw");

test "foreign Vulkan handles must be ABI compatible" {
    var window: rgfw.Window = .{ .handle = null };
    _ = rgfw.Vulkan.createSurfaceAs(u8, &window, @as(u8, 1)) catch {};
}

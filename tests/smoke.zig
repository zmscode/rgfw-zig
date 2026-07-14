const std = @import("std");
const rgfw = @import("rgfw");

test "core RGFW declarations are available" {
    try std.testing.expect(@hasDecl(rgfw.raw, "RGFW_init"));
    try std.testing.expect(@hasDecl(rgfw.raw, "RGFW_createWindow"));
    try std.testing.expect(@hasDecl(rgfw.raw, "RGFW_pollEvents"));
    try std.testing.expect(@hasDecl(rgfw.raw, "RGFW_window_close"));
}

test "window flags can be combined from Zig" {
    const flags: rgfw.WindowFlags = .{ .centered = true, .no_resize = true };
    const raw_flags = flags.toRaw();
    try std.testing.expect(raw_flags != 0);
}

test "raw bindings contain no eager translation failures" {
    try std.testing.expect(!@hasDecl(rgfw.raw, "RGFWDEF"));
    try std.testing.expect(!@hasDecl(rgfw.raw, "RGFW_ENUM"));
    try std.testing.expect(!@hasDecl(rgfw.raw, "RGFW_STATIC_ASSERT"));
    try std.testing.expectEqual(@as(rgfw.raw.RGFW_bool, 1), rgfw.raw.RGFW_TRUE);
}

test "Vulkan declarations and helpers follow the feature option" {
    if (!rgfw.features.vulkan) {
        try std.testing.expect(!@hasDecl(rgfw.raw, "VkInstance"));
        return;
    }

    try std.testing.expect(@hasDecl(rgfw.raw, "VkInstance"));
    try std.testing.expect(@hasDecl(rgfw.raw, "RGFW_window_createSurface_Vulkan"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "requiredInstanceExtensions"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "createSurface"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "presentationSupported"));
}

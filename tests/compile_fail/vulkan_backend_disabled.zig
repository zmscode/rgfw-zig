const rgfw = @import("rgfw");

test "disabled Vulkan APIs explain how to enable them" {
    rgfw.Vulkan.requireEnabled();
}

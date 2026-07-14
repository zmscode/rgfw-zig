const builtin = @import("builtin");
const rgfw = @import("rgfw");

pub fn main() !void {
    const vk = rgfw.raw;
    var context = try rgfw.init("vulkan-example", .{ .backend = .vulkan });
    defer context.deinit();
    var window = try context.createWindow("Vulkan 1.0 surface", .{
        .width = 800,
        .height = 600,
        .flags = .{ .centered = true },
    });
    defer window.deinit();

    const create_instance = load(vk.PFN_vkCreateInstance, null, "vkCreateInstance") orelse {
        return error.VulkanEntryPointMissing;
    };
    const required = rgfw.Vulkan.requiredInstanceExtensions();
    if (required.len != 2) return error.UnexpectedExtensionCount;

    const portability: [*:0]const u8 = "VK_KHR_portability_enumeration";
    var extensions: [3][*c]const u8 = .{ required[0], required[1], null };
    const use_portability = builtin.os.tag == .macos;
    if (use_portability) extensions[2] = portability;

    const application: vk.VkApplicationInfo = .{
        .sType = @intCast(vk.VK_STRUCTURE_TYPE_APPLICATION_INFO),
        .pApplicationName = "rgfw-zig-vulkan",
        .applicationVersion = 1,
        .pEngineName = "rgfw-zig",
        .engineVersion = 1,
        .apiVersion = 1 << 22,
    };
    const create_info: vk.VkInstanceCreateInfo = .{
        .sType = @intCast(vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO),
        .flags = if (use_portability)
            @intCast(vk.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR)
        else
            0,
        .pApplicationInfo = &application,
        .enabledExtensionCount = if (use_portability) 3 else 2,
        .ppEnabledExtensionNames = &extensions,
    };

    var instance: vk.VkInstance = null;
    if (create_instance(&create_info, null, &instance) != vk.VK_SUCCESS) {
        return error.InstanceCreationFailed;
    }
    const destroy_instance = load(vk.PFN_vkDestroyInstance, instance, "vkDestroyInstance") orelse {
        return error.VulkanEntryPointMissing;
    };
    defer destroy_instance(instance, null);

    const surface = try rgfw.Vulkan.createSurface(&window, instance);
    const destroy_surface = load(
        vk.PFN_vkDestroySurfaceKHR,
        instance,
        "vkDestroySurfaceKHR",
    ) orelse return error.VulkanEntryPointMissing;
    defer destroy_surface(instance, surface, null);

    while (window.isOpen()) window.pumpEvents();
}

fn load(
    comptime Function: type,
    instance: rgfw.raw.VkInstance,
    name: [*:0]const u8,
) Function {
    const procedure = rgfw.raw.RGFW_getInstanceProcAddress_Vulkan(instance, name) orelse {
        return null;
    };
    return @ptrCast(procedure);
}

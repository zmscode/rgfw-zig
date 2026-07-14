#if defined(__APPLE__) && defined(RGFW_VULKAN)
#include <dlfcn.h>
#include <string.h>

static void* rgfw_zig_dlopen(const char* path, int mode);
#define dlopen rgfw_zig_dlopen
#define vkCreateMacOSSurfaceMVK rgfw_zig_vkCreateMacOSSurfaceMVK
#endif

#include "RGFW.h"

#if defined(__APPLE__) && defined(RGFW_VULKAN)
#undef dlopen

static void* rgfw_zig_dlopen(const char* path, int mode) {
    void* handle = dlopen(path, mode);
    if (handle != NULL || strstr(path, "vulkan") == NULL) return handle;

    handle = dlopen("/opt/homebrew/lib/libvulkan.1.dylib", mode);
    if (handle != NULL) return handle;
    return dlopen("/usr/local/lib/libvulkan.1.dylib", mode);
}

VKAPI_ATTR VkResult VKAPI_CALL rgfw_zig_vkCreateMacOSSurfaceMVK(
    VkInstance instance,
    const VkMacOSSurfaceCreateInfoMVK* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* surface
) {
    PFN_vkCreateMacOSSurfaceMVK create_surface = NULL;
    RGFW_proc function = RGFW_getInstanceProcAddress_Vulkan(
        instance,
        "vkCreateMacOSSurfaceMVK"
    );
    RGFW_MEMCPY(&create_surface, &function, sizeof(create_surface));
    if (create_surface == NULL) return VK_ERROR_INITIALIZATION_FAILED;
    return create_surface(instance, create_info, allocator, surface);
}
#endif

#if defined(__APPLE__) && defined(RGFW_VULKAN)
#include <dlfcn.h>
#include <string.h>

#define VK_USE_PLATFORM_METAL_EXT
#define VK_USE_PLATFORM_MACOS_MVK
#include <vulkan/vulkan.h>

/*
 * The vendored RGFW release still builds its macOS Vulkan path around the
 * deprecated MVK surface extension. These translation aliases preserve its
 * internal control flow while the shim below supplies a CAMetalLayer to the
 * standard EXT entry point. The public extension list is replaced as well.
 */
static void* rgfw_zig_dlopen(const char* path, int mode);
VKAPI_ATTR VkResult VKAPI_CALL rgfw_zig_vkCreateMetalSurfaceEXT(
    VkInstance instance,
    const VkMetalSurfaceCreateInfoEXT* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* surface
);

#define dlopen rgfw_zig_dlopen
#define RGFW_getRequiredInstanceExtensions_Vulkan \
    rgfw_zig_upstream_getRequiredInstanceExtensions_Vulkan
#define VkMacOSSurfaceCreateInfoMVK VkMetalSurfaceCreateInfoEXT
#define VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK \
    VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT
#define vkCreateMacOSSurfaceMVK rgfw_zig_vkCreateMetalSurfaceEXT
#define pView pLayer
#endif

#include "RGFW.h"

#if defined(__APPLE__) && defined(RGFW_VULKAN)
#undef dlopen
#undef RGFW_getRequiredInstanceExtensions_Vulkan
#undef VkMacOSSurfaceCreateInfoMVK
#undef VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK
#undef vkCreateMacOSSurfaceMVK
#undef pView

static void* rgfw_zig_dlopen(const char* path, int mode) {
    void* handle = dlopen(path, mode);
    if (handle != NULL || strstr(path, "vulkan") == NULL) return handle;

    handle = dlopen("/opt/homebrew/lib/libvulkan.1.dylib", mode);
    if (handle != NULL) return handle;
    return dlopen("/usr/local/lib/libvulkan.1.dylib", mode);
}

const char** RGFW_getRequiredInstanceExtensions_Vulkan(size_t* count) {
    static const char* extensions[2] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
    };
    if (count != NULL) *count = 2;
    return extensions;
}

VKAPI_ATTR VkResult VKAPI_CALL rgfw_zig_vkCreateMetalSurfaceEXT(
    VkInstance instance,
    const VkMetalSurfaceCreateInfoEXT* create_info,
    const VkAllocationCallbacks* allocator,
    VkSurfaceKHR* surface
) {
    PFN_vkCreateMetalSurfaceEXT create_surface = NULL;
    RGFW_proc function = RGFW_getInstanceProcAddress_Vulkan(
        instance,
        "vkCreateMetalSurfaceEXT"
    );
    RGFW_MEMCPY(&create_surface, &function, sizeof(create_surface));
    if (create_surface == NULL) return VK_ERROR_INITIALIZATION_FAILED;

    id view = (id)create_info->pLayer;
    if (view == NULL) return VK_ERROR_INITIALIZATION_FAILED;
    id layer = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layer"));
    if (layer == NULL) return VK_ERROR_INITIALIZATION_FAILED;

    VkMetalSurfaceCreateInfoEXT metal_create_info = *create_info;
    metal_create_info.pLayer = layer;
    return create_surface(instance, &metal_create_info, allocator, surface);
}
#endif

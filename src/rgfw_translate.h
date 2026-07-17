#ifndef RGFW_ZIG_TRANSLATE_H
#define RGFW_ZIG_TRANSLATE_H

/*
 * This file is an altered translation-only adapter, not part of upstream RGFW.
 * These facilities are only used by RGFW's C implementation, so hiding their
 * macros keeps translate-c from exporting thousands of unrelated SDK macros.
 */
#define RGFW_ASSERT(condition)
#define RGFW_STATIC_ASSERT(name, condition)
#define RGFW_ALLOC(size)
#define RGFW_FREE(pointer)
#define RGFW_MEMZERO(pointer, size)
#define RGFW_MEMCPY(destination, source, length)
#define RGFW_STRNCMP(left, right, length)
#define RGFW_STRNCPY(destination, source, length)
#define RGFW_STRSTR(string, substring)
#define RGFW_STRTOL(string, end_pointer, base)
#define RGFW_ATOF(number)
#define RGFW_SNPRINTF(...)
#define RGFW_PRINTF(...)
#define RGFWDEF extern
#define RGFW_NO_INFO

#define RGFW_INT_DEFINED
typedef unsigned char u8;
typedef signed char i8;
typedef unsigned short u16;
typedef signed short i16;
typedef unsigned int u32;
typedef signed int i32;
typedef unsigned long long u64;
typedef signed long long i64;

#define RGFW_BOOL_DEFINED
typedef u8 RGFW_bool;

#ifdef RGFW_VULKAN
/*
 * RGFW's public ABI only needs Vulkan core handles and results. Avoid pulling
 * native window-system headers into translate-c; the C implementation still
 * includes the complete platform Vulkan header.
 */
#include <vulkan/vulkan_core.h>
#define RGFW_NO_INCLUDE_VULKAN

#ifdef RGFW_WINDOWS
typedef struct VkWin32SurfaceCreateInfoKHR VkWin32SurfaceCreateInfoKHR;
#elif defined(RGFW_X11)
typedef struct VkXlibSurfaceCreateInfoKHR VkXlibSurfaceCreateInfoKHR;
typedef struct _XDisplay Display;
typedef unsigned long VisualID;
#elif defined(RGFW_WAYLAND)
typedef struct VkWaylandSurfaceCreateInfoKHR VkWaylandSurfaceCreateInfoKHR;
#endif
#endif

#ifdef RGFW_WEBGPU
/* RGFW's public WebGPU ABI needs only these two opaque handles. Keep the full
 * generated WebGPU API in the consumer's chosen package, not rgfw.raw. */
#define WEBGPU_H_
typedef struct WGPUInstanceImpl* WGPUInstance;
typedef struct WGPUSurfaceImpl* WGPUSurface;
#endif

#ifdef RGFW_ZIG_CUSTOM_BACKEND_HEADER
#include RGFW_ZIG_CUSTOM_BACKEND_HEADER
#else
#include "RGFW.h"
#endif

#endif

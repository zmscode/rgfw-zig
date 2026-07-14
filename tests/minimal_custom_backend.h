#ifndef RGFW_ZIG_MINIMAL_CUSTOM_BACKEND_H
#define RGFW_ZIG_MINIMAL_CUSTOM_BACKEND_H

#define RGFW_CUSTOM_BACKEND

struct RGFW_window_src {
    void* user_data;
};

struct RGFW_nativeImage {
    void* user_data;
};

#include "RGFW.h"

#ifdef RGFW_IMPLEMENTATION

i32 RGFW_initPlatform(const char* class_name, RGFW_initFlags flags) {
    RGFW_UNUSED(class_name);
    RGFW_UNUSED(flags);
    return 0;
}

void RGFW_deinitPlatform(void) {}
void RGFW_initKeycodesPlatform(void) {}
void RGFW_pollEvents(void) {}
void RGFW_pollMonitors(void) {}

RGFW_window* RGFW_createWindowPlatform(
    const char* name,
    RGFW_windowFlags flags,
    RGFW_window* window
) {
    RGFW_UNUSED(name);
    RGFW_UNUSED(flags);
    return window;
}

void RGFW_window_closePlatform(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_focus(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_raise(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_show(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_hide(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_maximize(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_minimize(RGFW_window* window) { RGFW_UNUSED(window); }
void RGFW_window_restore(RGFW_window* window) { RGFW_UNUSED(window); }

void RGFW_window_move(RGFW_window* window, i32 x, i32 y) {
    window->x = x;
    window->y = y;
}

void RGFW_window_resize(RGFW_window* window, i32 width, i32 height) {
    window->w = width;
    window->h = height;
}

void RGFW_window_setMinSize(RGFW_window* window, i32 width, i32 height) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(width);
    RGFW_UNUSED(height);
}

void RGFW_window_setMaxSize(RGFW_window* window, i32 width, i32 height) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(width);
    RGFW_UNUSED(height);
}

void RGFW_window_setBorder(RGFW_window* window, RGFW_bool border) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(border);
}

void RGFW_window_setFloating(RGFW_window* window, RGFW_bool floating) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(floating);
}

void RGFW_window_setFullscreen(RGFW_window* window, RGFW_bool fullscreen) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(fullscreen);
}

void RGFW_window_setName(RGFW_window* window, const char* name) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(name);
}

void RGFW_window_moveMouse(RGFW_window* window, i32 x, i32 y) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(x);
    RGFW_UNUSED(y);
}

void RGFW_window_showMouse(RGFW_window* window, RGFW_bool show) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(show);
}

void RGFW_window_captureMousePlatform(RGFW_window* window, RGFW_bool state) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(state);
}

void RGFW_window_setRawMouseModePlatform(RGFW_window* window, RGFW_bool state) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(state);
}

RGFW_bool RGFW_window_isMaximized(RGFW_window* window) {
    RGFW_UNUSED(window);
    return RGFW_FALSE;
}

RGFW_bool RGFW_window_isMinimized(RGFW_window* window) {
    RGFW_UNUSED(window);
    return RGFW_FALSE;
}

RGFW_bool RGFW_window_setIconEx(
    RGFW_window* window,
    u8* data,
    i32 width,
    i32 height,
    RGFW_format format,
    RGFW_icon type
) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(data);
    RGFW_UNUSED(width);
    RGFW_UNUSED(height);
    RGFW_UNUSED(format);
    RGFW_UNUSED(type);
    return RGFW_TRUE;
}

RGFW_mouse* RGFW_createMouseStandard(RGFW_mouseIcon mouse) {
    RGFW_UNUSED(mouse);
    return NULL;
}

RGFW_bool RGFW_window_setMousePlatform(RGFW_window* window, RGFW_mouse* mouse) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(mouse);
    return RGFW_TRUE;
}

void RGFW_freeMouse(RGFW_mouse* mouse) { RGFW_UNUSED(mouse); }

RGFW_bool RGFW_createSurfacePtr(
    u8* data,
    i32 width,
    i32 height,
    RGFW_format format,
    RGFW_surface* surface
) {
    surface->data = data;
    surface->w = width;
    surface->h = height;
    surface->format = format;
    surface->convertFunc = NULL;
    surface->native.user_data = NULL;
    return RGFW_TRUE;
}

void RGFW_surface_freePtr(RGFW_surface* surface) { RGFW_UNUSED(surface); }

void RGFW_window_blitSurface(RGFW_window* window, RGFW_surface* surface) {
    RGFW_UNUSED(window);
    RGFW_UNUSED(surface);
}

RGFW_monitor* RGFW_window_getMonitor(RGFW_window* window) {
    RGFW_UNUSED(window);
    return NULL;
}

void RGFW_monitorNode_free(RGFW_monitorNode* node) { RGFW_UNUSED(node); }

size_t RGFW_monitor_getModesPtr(RGFW_monitor* monitor, RGFW_monitorMode** modes) {
    RGFW_UNUSED(monitor);
    RGFW_UNUSED(modes);
    return 0;
}

RGFW_bool RGFW_monitor_requestMode(
    RGFW_monitor* monitor,
    RGFW_monitorMode* mode,
    RGFW_modeRequest request
) {
    RGFW_UNUSED(monitor);
    RGFW_UNUSED(mode);
    RGFW_UNUSED(request);
    return RGFW_FALSE;
}

size_t RGFW_monitor_getGammaRampPtr(RGFW_monitor* monitor, RGFW_gammaRamp* ramp) {
    RGFW_UNUSED(monitor);
    RGFW_UNUSED(ramp);
    return 0;
}

RGFW_bool RGFW_monitor_setGammaRamp(RGFW_monitor* monitor, RGFW_gammaRamp* ramp) {
    RGFW_UNUSED(monitor);
    RGFW_UNUSED(ramp);
    return RGFW_FALSE;
}

RGFW_bool RGFW_readClipboardPtr(
    RGFW_dataTransferType requested_type,
    u8* buffer,
    size_t capacity,
    RGFW_dataTransfer* data
) {
    RGFW_UNUSED(requested_type);
    RGFW_UNUSED(buffer);
    RGFW_UNUSED(capacity);
    if (data != NULL) RGFW_MEMZERO(data, sizeof(*data));
    return RGFW_FALSE;
}

#endif

#endif

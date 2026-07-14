const std = @import("std");
const build_options = @import("rgfw_build_options");

/// Complete, mechanically translated RGFW API for functionality not wrapped below.
pub const raw = @import("rgfw_raw");

pub const features: Features = .{
    .opengl = build_options.opengl,
    .egl = build_options.egl,
    .vulkan = build_options.vulkan,
    .debug = build_options.rgfw_debug,
};

pub const Features = struct {
    opengl: bool,
    egl: bool,
    vulkan: bool,
    debug: bool,
};

pub const Backend = enum {
    none,
    opengl,
    egl,
    vulkan,
};

pub const InitOptions = struct {
    backend: Backend = .none,
};

pub const InitError = error{
    BackendNotEnabled,
    InitializationFailed,
};

pub const Context = struct {
    active: bool = true,
    warning_code: ?i32 = null,

    pub fn deinit(context: *Context) void {
        if (!context.active) return;
        raw.RGFW_deinit();
        context.active = false;
    }

    pub fn createWindow(
        context: *const Context,
        title: [:0]const u8,
        options: Window.Options,
    ) Window.Error!Window {
        std.debug.assert(context.active);
        return Window.create(title, options);
    }
};

pub fn init(class_name: [:0]const u8, options: InitOptions) InitError!Context {
    const flags: raw.RGFW_initFlags = switch (options.backend) {
        .none => 0,
        .opengl => if (features.opengl)
            @intCast(raw.RGFW_initOpenGL)
        else
            return error.BackendNotEnabled,
        .egl => if (features.egl)
            @intCast(raw.RGFW_initEGL)
        else
            return error.BackendNotEnabled,
        .vulkan => if (features.vulkan)
            @intCast(raw.RGFW_initVulkan)
        else
            return error.BackendNotEnabled,
    };

    const status = raw.RGFW_init(class_name.ptr, flags);
    if (status < 0) return error.InitializationFailed;
    return .{ .warning_code = if (status > 0) status else null };
}

pub fn pollEvents() void {
    raw.RGFW_pollEvents();
}

pub fn waitForNextEvent() void {
    raw.RGFW_waitForEvent(@intCast(raw.RGFW_eventWaitNext));
}

pub const Input = struct {
    pub fn keyPressed(key: Key) bool {
        return raw.RGFW_isKeyPressed(@intFromEnum(key)) != 0;
    }

    pub fn keyReleased(key: Key) bool {
        return raw.RGFW_isKeyReleased(@intFromEnum(key)) != 0;
    }

    pub fn keyDown(key: Key) bool {
        return raw.RGFW_isKeyDown(@intFromEnum(key)) != 0;
    }

    pub fn mousePressed(button: MouseButton) bool {
        return raw.RGFW_isMousePressed(@intFromEnum(button)) != 0;
    }

    pub fn mouseReleased(button: MouseButton) bool {
        return raw.RGFW_isMouseReleased(@intFromEnum(button)) != 0;
    }

    pub fn mouseDown(button: MouseButton) bool {
        return raw.RGFW_isMouseDown(@intFromEnum(button)) != 0;
    }

    pub fn mouseVector() Vector {
        var x: f32 = 0;
        var y: f32 = 0;
        raw.RGFW_getMouseVector(&x, &y);
        return .{ .x = x, .y = y };
    }

    pub fn mouseScroll() Vector {
        var x: f32 = 0;
        var y: f32 = 0;
        raw.RGFW_getMouseScroll(&x, &y);
        return .{ .x = x, .y = y };
    }
};

pub const Clipboard = struct {
    pub fn readText() ?[]const u8 {
        const transfer = raw.RGFW_readClipboardString();
        if (transfer == null) return null;
        if (transfer.*.data == null) return null;
        return transfer.*.data[0..transfer.*.length];
    }

    pub fn writeText(text: []const u8) bool {
        const transfer: raw.RGFW_dataTransfer = .{
            .data = text.ptr,
            .length = text.len,
            .type = @intCast(raw.RGFW_dataText),
        };
        return raw.RGFW_writeClipboard(&transfer) != 0;
    }
};

pub const Window = struct {
    handle: ?*raw.RGFW_window,

    pub const Error = error{
        InvalidSize,
        CreationFailed,
    };

    pub const Options = struct {
        x: i32 = 0,
        y: i32 = 0,
        width: i32 = 800,
        height: i32 = 450,
        flags: WindowFlags = .{},
        exit_key: ?raw.RGFW_key = @intCast(raw.RGFW_keyEscape),
    };

    fn create(title: [:0]const u8, options: Options) Error!Window {
        if (options.width <= 0) return error.InvalidSize;
        if (options.height <= 0) return error.InvalidSize;

        const handle = raw.RGFW_createWindow(
            title.ptr,
            options.x,
            options.y,
            options.width,
            options.height,
            options.flags.toRaw(),
        ) orelse return error.CreationFailed;

        if (options.exit_key) |key| raw.RGFW_window_setExitKey(handle, key);
        return .{ .handle = handle };
    }

    pub fn deinit(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_close(handle);
        window.handle = null;
    }

    pub fn shouldClose(window: *const Window) bool {
        const handle = window.handle orelse return true;
        return raw.RGFW_window_shouldClose(handle) != 0;
    }

    pub fn isOpen(window: *const Window) bool {
        return !window.shouldClose();
    }

    pub fn requestClose(window: *Window) void {
        const handle = window.handle orelse return;
        if (raw.RGFW_window_shouldClose(handle) != 0) return;
        raw.RGFW_window_setShouldClose(handle, 1);
    }

    pub fn size(window: *const Window) Size {
        const handle = window.handle orelse return .{ .width = 0, .height = 0 };
        var width: i32 = 0;
        var height: i32 = 0;
        if (raw.RGFW_window_getSize(handle, &width, &height) == 0) {
            return .{ .width = 0, .height = 0 };
        }
        return .{ .width = width, .height = height };
    }

    pub fn sizeInPixels(window: *const Window) Size {
        const handle = window.handle orelse return .{ .width = 0, .height = 0 };
        var width: i32 = 0;
        var height: i32 = 0;
        if (raw.RGFW_window_getSizeInPixels(handle, &width, &height) == 0) {
            return .{ .width = 0, .height = 0 };
        }
        return .{ .width = width, .height = height };
    }

    pub fn position(window: *const Window) Point {
        const handle = window.handle orelse return .{ .x = 0, .y = 0 };
        var x: i32 = 0;
        var y: i32 = 0;
        _ = raw.RGFW_window_getPosition(handle, &x, &y);
        return .{ .x = x, .y = y };
    }

    pub fn mousePosition(window: *const Window) Point {
        const handle = window.handle orelse return .{ .x = 0, .y = 0 };
        var x: i32 = 0;
        var y: i32 = 0;
        _ = raw.RGFW_window_getMouse(handle, &x, &y);
        return .{ .x = x, .y = y };
    }

    pub fn keyPressed(window: *const Window, key: Key) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isKeyPressed(handle, @intFromEnum(key)) != 0;
    }

    pub fn keyReleased(window: *const Window, key: Key) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isKeyReleased(handle, @intFromEnum(key)) != 0;
    }

    pub fn keyDown(window: *const Window, key: Key) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isKeyDown(handle, @intFromEnum(key)) != 0;
    }

    pub fn mousePressed(window: *const Window, button: MouseButton) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMousePressed(handle, @intFromEnum(button)) != 0;
    }

    pub fn mouseReleased(window: *const Window, button: MouseButton) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMouseReleased(handle, @intFromEnum(button)) != 0;
    }

    pub fn mouseDown(window: *const Window, button: MouseButton) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMouseDown(handle, @intFromEnum(button)) != 0;
    }

    pub fn focused(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isInFocus(handle) != 0;
    }

    pub fn fullscreen(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isFullscreen(handle) != 0;
    }

    pub fn minimized(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMinimized(handle) != 0;
    }

    pub fn maximized(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMaximized(handle) != 0;
    }

    pub fn hidden(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isHidden(handle) != 0;
    }

    pub fn floating(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isFloating(handle) != 0;
    }

    pub fn borderless(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_borderless(handle) != 0;
    }

    pub fn allowsDragAndDrop(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_allowsDND(handle) != 0;
    }

    pub fn setFullscreen(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_setFullscreen(handle, @intFromBool(enabled));
    }

    pub fn setFloating(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_setFloating(handle, @intFromBool(enabled));
    }

    pub fn setBorder(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_setBorder(handle, @intFromBool(enabled));
    }

    pub fn setDragAndDrop(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_setDND(handle, @intFromBool(enabled));
    }

    pub fn showMouse(window: *Window, visible: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_showMouse(handle, @intFromBool(visible));
    }

    pub fn setRawMouseMode(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_setRawMouseMode(handle, @intFromBool(enabled));
    }

    pub fn captureMouse(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_captureMouse(handle, @intFromBool(enabled));
    }

    pub fn center(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_center(handle);
    }

    pub fn maximize(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_maximize(handle);
    }

    pub fn minimize(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_minimize(handle);
    }

    pub fn restore(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_restore(handle);
    }

    pub fn show(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_show(handle);
    }

    pub fn hide(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_hide(handle);
    }

    pub fn scaleToMonitor(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_scaleToMonitor(handle);
    }

    pub fn flash(window: *Window, request: FlashRequest) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_flash(handle, @intFromEnum(request));
    }

    pub fn setName(window: *Window, name: [:0]const u8) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_setName(handle, name.ptr);
    }

    pub fn setStandardCursor(window: *Window, cursor: Cursor) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_setMouseStandard(handle, @intFromEnum(cursor)) != 0;
    }

    pub fn monitor(window: *const Window) ?Monitor {
        const handle = window.handle orelse return null;
        const monitor_handle = raw.RGFW_window_getMonitor(handle);
        if (monitor_handle == null) return null;
        return .{ .handle = @ptrCast(monitor_handle) };
    }

    pub fn nextEvent(window: *Window) ?Event {
        const handle = window.handle orelse return null;
        var event: raw.RGFW_event = undefined;
        if (raw.RGFW_window_checkEvent(handle, &event) == 0) return null;
        return .{ .raw_event = event };
    }

    /// Polls the platform once and discards queued event payloads after RGFW updates its state.
    pub fn pumpEvents(window: *Window) void {
        if (window.handle == null) return;
        raw.RGFW_pollEvents();
        window.discardEvents();
    }

    /// Discards currently queued event payloads without polling the platform.
    pub fn discardEvents(window: *Window) void {
        const handle = window.handle orelse return;
        var event: raw.RGFW_event = undefined;
        while (raw.RGFW_window_checkQueuedEvent(handle, &event) != 0) {}
    }
};

pub const Size = struct {
    width: i32,
    height: i32,
};

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Vector = struct {
    x: f32,
    y: f32,
};

pub const WindowFlags = struct {
    no_border: bool = false,
    no_resize: bool = false,
    allow_drag_and_drop: bool = false,
    hide_mouse: bool = false,
    fullscreen: bool = false,
    translucent: bool = false,
    centered: bool = false,
    raw_mouse: bool = false,
    scale_to_monitor: bool = false,
    hidden: bool = false,
    maximized: bool = false,
    center_cursor: bool = false,
    floating: bool = false,
    focus_on_show: bool = false,
    minimized: bool = false,
    focused: bool = false,
    capture_mouse: bool = false,
    open_gl: bool = false,
    egl: bool = false,

    pub fn toRaw(flags: WindowFlags) raw.RGFW_windowFlags {
        var result: raw.RGFW_windowFlags = 0;
        addFlag(&result, flags.no_border, raw.RGFW_windowNoBorder);
        addFlag(&result, flags.no_resize, raw.RGFW_windowNoResize);
        addFlag(&result, flags.allow_drag_and_drop, raw.RGFW_windowAllowDND);
        addFlag(&result, flags.hide_mouse, raw.RGFW_windowHideMouse);
        addFlag(&result, flags.fullscreen, raw.RGFW_windowFullscreen);
        addFlag(&result, flags.translucent, raw.RGFW_windowTranslucent);
        addFlag(&result, flags.centered, raw.RGFW_windowCenter);
        addFlag(&result, flags.raw_mouse, raw.RGFW_windowRawMouse);
        addFlag(&result, flags.scale_to_monitor, raw.RGFW_windowScaleToMonitor);
        addFlag(&result, flags.hidden, raw.RGFW_windowHide);
        addFlag(&result, flags.maximized, raw.RGFW_windowMaximize);
        addFlag(&result, flags.center_cursor, raw.RGFW_windowCenterCursor);
        addFlag(&result, flags.floating, raw.RGFW_windowFloating);
        addFlag(&result, flags.focus_on_show, raw.RGFW_windowFocusOnShow);
        addFlag(&result, flags.minimized, raw.RGFW_windowMinimize);
        addFlag(&result, flags.focused, raw.RGFW_windowFocus);
        addFlag(&result, flags.capture_mouse, raw.RGFW_windowCaptureMouse);
        addFlag(&result, flags.open_gl, raw.RGFW_windowOpenGL);
        addFlag(&result, flags.egl, raw.RGFW_windowEGL);
        return result;
    }

    fn addFlag(result: *raw.RGFW_windowFlags, enabled: bool, value: c_int) void {
        if (enabled) result.* |= @intCast(value);
    }
};

pub const Key = enum(raw.RGFW_key) {
    escape = raw.RGFW_keyEscape,
    space = raw.RGFW_keySpace,
    enter = raw.RGFW_keyEnter,
    a = raw.RGFW_keyA,
    b = raw.RGFW_keyB,
    c = raw.RGFW_keyC,
    d = raw.RGFW_keyD,
    e = raw.RGFW_keyE,
    f = raw.RGFW_keyF,
    g = raw.RGFW_keyG,
    h = raw.RGFW_keyH,
    i = raw.RGFW_keyI,
    j = raw.RGFW_keyJ,
    k = raw.RGFW_keyK,
    l = raw.RGFW_keyL,
    m = raw.RGFW_keyM,
    n = raw.RGFW_keyN,
    o = raw.RGFW_keyO,
    p = raw.RGFW_keyP,
    q = raw.RGFW_keyQ,
    r = raw.RGFW_keyR,
    s = raw.RGFW_keyS,
    t = raw.RGFW_keyT,
    u = raw.RGFW_keyU,
    v = raw.RGFW_keyV,
    w = raw.RGFW_keyW,
    x = raw.RGFW_keyX,
    y = raw.RGFW_keyY,
    z = raw.RGFW_keyZ,
    control_left = raw.RGFW_keyControlL,
    control_right = raw.RGFW_keyControlR,
    up = raw.RGFW_keyUp,
    down = raw.RGFW_keyDown,
    left = raw.RGFW_keyLeft,
    right = raw.RGFW_keyRight,
    _,
};

pub const MouseButton = enum(raw.RGFW_mouseButton) {
    left = raw.RGFW_mouseLeft,
    middle = raw.RGFW_mouseMiddle,
    right = raw.RGFW_mouseRight,
    _,
};

pub const Cursor = enum(raw.RGFW_mouseIcon) {
    normal = raw.RGFW_mouseNormal,
    arrow = raw.RGFW_mouseArrow,
    text = raw.RGFW_mouseText,
    crosshair = raw.RGFW_mouseCrosshair,
    pointing_hand = raw.RGFW_mousePointingHand,
    resize_horizontal = raw.RGFW_mouseResizeEW,
    resize_vertical = raw.RGFW_mouseResizeNS,
    resize_all = raw.RGFW_mouseResizeAll,
    not_allowed = raw.RGFW_mouseNotAllowed,
    wait = raw.RGFW_mouseWait,
    progress = raw.RGFW_mouseProgress,
    _,
};

pub const FlashRequest = enum(raw.RGFW_flashRequest) {
    cancel = raw.RGFW_flashCancel,
    briefly = raw.RGFW_flashBriefly,
    until_focused = raw.RGFW_flashUntilFocused,
};

pub const ImageFormat = enum(raw.RGFW_format) {
    rgb8 = raw.RGFW_formatRGB8,
    bgr8 = raw.RGFW_formatBGR8,
    rgba8 = raw.RGFW_formatRGBA8,
    argb8 = raw.RGFW_formatARGB8,
    bgra8 = raw.RGFW_formatBGRA8,
    abgr8 = raw.RGFW_formatABGR8,
};

pub const Surface = struct {
    handle: ?*raw.RGFW_surface,

    pub const Error = error{
        InvalidDimensions,
        BufferTooSmall,
        CreationFailed,
    };

    pub fn init(
        pixels: []u8,
        width: i32,
        height: i32,
        format: ImageFormat,
    ) Error!Surface {
        if (width <= 0) return error.InvalidDimensions;
        if (height <= 0) return error.InvalidDimensions;

        const channels: usize = switch (format) {
            .rgb8, .bgr8 => 3,
            else => 4,
        };
        const pixel_count = std.math.mul(usize, @intCast(width), @intCast(height)) catch {
            return error.InvalidDimensions;
        };
        const required_bytes = std.math.mul(usize, pixel_count, channels) catch {
            return error.InvalidDimensions;
        };
        if (pixels.len < required_bytes) return error.BufferTooSmall;

        const handle = raw.RGFW_createSurface(
            pixels.ptr,
            width,
            height,
            @intFromEnum(format),
        ) orelse return error.CreationFailed;
        return .{ .handle = handle };
    }

    pub fn deinit(surface: *Surface) void {
        const handle = surface.handle orelse return;
        raw.RGFW_surface_free(handle);
        surface.handle = null;
    }

    pub fn blit(surface: *const Surface, window: *const Window) void {
        const surface_handle = surface.handle orelse return;
        const window_handle = window.handle orelse return;
        raw.RGFW_window_blitSurface(window_handle, surface_handle);
    }
};

pub const Monitor = struct {
    handle: *raw.RGFW_monitor,

    pub fn name(monitor: *const Monitor) [:0]const u8 {
        const name_ptr = raw.RGFW_monitor_getName(monitor.handle);
        return std.mem.span(@as([*:0]const u8, @ptrCast(name_ptr)));
    }

    pub fn setGamma(monitor: *Monitor, gamma: f32) bool {
        return raw.RGFW_monitor_setGamma(monitor.handle, gamma) != 0;
    }

    pub fn workArea(monitor: *const Monitor) Rect {
        var area: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        _ = raw.RGFW_monitor_getWorkarea(
            monitor.handle,
            &area.x,
            &area.y,
            &area.width,
            &area.height,
        );
        return area;
    }
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const OpenGL = if (features.opengl) struct {
    pub fn makeCurrent(window: ?*const Window) void {
        const handle = if (window) |value| value.handle else null;
        raw.RGFW_window_makeCurrentContext_OpenGL(handle);
    }

    pub fn swapBuffers(window: *const Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapBuffers_OpenGL(handle);
    }

    pub fn swapInterval(window: *const Window, interval: i32) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapInterval_OpenGL(handle, interval);
    }
} else struct {};

pub const EGL = if (features.egl) struct {
    pub fn makeCurrent(window: *const Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_makeCurrentContext_EGL(handle);
    }

    pub fn swapBuffers(window: *const Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapBuffers_EGL(handle);
    }

    pub fn swapInterval(window: *const Window, interval: i32) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapInterval_EGL(handle, interval);
    }
} else struct {};

pub const Event = struct {
    raw_event: raw.RGFW_event,

    pub fn kind(event: *const Event) EventKind {
        return @enumFromInt(event.raw_event.type);
    }

    pub fn key(event: *const Event) ?raw.RGFW_keyEvent {
        return switch (event.kind()) {
            .key_pressed, .key_released => event.raw_event.key,
            else => null,
        };
    }

    pub fn keyValue(event: *const Event) ?Key {
        const key_event = event.key() orelse return null;
        return @enumFromInt(key_event.value);
    }

    pub fn mouseButton(event: *const Event) ?raw.RGFW_mouseButtonEvent {
        return switch (event.kind()) {
            .mouse_button_pressed, .mouse_button_released => event.raw_event.button,
            else => null,
        };
    }
};

pub const EventKind = enum(u8) {
    none = raw.RGFW_eventNone,
    key_pressed = raw.RGFW_keyPressed,
    key_released = raw.RGFW_keyReleased,
    key_character = raw.RGFW_keyChar,
    mouse_button_pressed = raw.RGFW_mouseButtonPressed,
    mouse_button_released = raw.RGFW_mouseButtonReleased,
    mouse_scroll = raw.RGFW_mouseScroll,
    mouse_motion = raw.RGFW_mouseMotion,
    mouse_raw_motion = raw.RGFW_mouseRawMotion,
    mouse_enter = raw.RGFW_mouseEnter,
    mouse_leave = raw.RGFW_mouseLeave,
    window_moved = raw.RGFW_windowMoved,
    window_resized = raw.RGFW_windowResized,
    window_focus_in = raw.RGFW_windowFocusIn,
    window_focus_out = raw.RGFW_windowFocusOut,
    window_refresh = raw.RGFW_windowRefresh,
    window_close = raw.RGFW_windowClose,
    window_maximized = raw.RGFW_windowMaximized,
    window_minimized = raw.RGFW_windowMinimized,
    window_restored = raw.RGFW_windowRestored,
    data_drop = raw.RGFW_dataDrop,
    data_drag = raw.RGFW_dataDrag,
    scale_updated = raw.RGFW_scaleUpdated,
    monitor_connected = raw.RGFW_monitorConnected,
    monitor_disconnected = raw.RGFW_monitorDisconnected,
    _,
};

pub const Vulkan = if (features.vulkan) struct {
    pub const Instance = raw.VkInstance;
    pub const PhysicalDevice = raw.VkPhysicalDevice;
    pub const Surface = raw.VkSurfaceKHR;
    pub const Result = raw.VkResult;

    pub const SurfaceError = error{SurfaceCreationFailed};

    pub fn requiredInstanceExtensions() []const [*:0]const u8 {
        var count: usize = 0;
        const extension_ptrs = raw.RGFW_getRequiredInstanceExtensions_Vulkan(&count);
        if (extension_ptrs == null) return &.{};
        const sentinel_ptrs: [*]const [*:0]const u8 = @ptrCast(extension_ptrs);
        return sentinel_ptrs[0..count];
    }

    pub fn createSurface(
        window: *const Window,
        instance: Instance,
    ) SurfaceError!@This().Surface {
        const handle = window.handle orelse return error.SurfaceCreationFailed;
        var surface: @This().Surface = undefined;
        const result = raw.RGFW_window_createSurface_Vulkan(handle, instance, &surface);
        if (result != raw.VK_SUCCESS) return error.SurfaceCreationFailed;
        return surface;
    }

    pub fn presentationSupported(
        instance: Instance,
        physical_device: PhysicalDevice,
        queue_family_index: u32,
    ) bool {
        return raw.RGFW_getPhysicalDevicePresentationSupport_Vulkan(
            instance,
            physical_device,
            queue_family_index,
        ) != 0;
    }
} else struct {};

test "window flags map to the RGFW ABI" {
    const flags: WindowFlags = .{
        .no_resize = true,
        .centered = true,
    };
    const expected: raw.RGFW_windowFlags = @intCast(
        raw.RGFW_windowNoResize | raw.RGFW_windowCenter,
    );
    try std.testing.expectEqual(expected, flags.toRaw());
}

test "event kinds preserve unknown values" {
    const unknown: EventKind = @enumFromInt(255);
    try std.testing.expectEqual(@as(u8, 255), @intFromEnum(unknown));
}

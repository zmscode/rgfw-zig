const std = @import("std");
const build_options = @import("rgfw_build_options");

/// Complete, mechanically translated RGFW API for functionality not wrapped below.
pub const raw = @import("rgfw_raw");

pub const features: Features = .{
    .opengl = build_options.opengl,
    .egl = build_options.egl,
    .vulkan = build_options.vulkan,
    .directx = build_options.directx,
    .webgpu = build_options.webgpu,
    .custom_allocator = build_options.custom_allocator,
    .debug = build_options.rgfw_debug,
    .window_system = build_options.window_system,
};

pub const WindowSystem = @TypeOf(build_options.window_system);
pub const window_system: WindowSystem = build_options.window_system;

pub const Features = struct {
    opengl: bool,
    egl: bool,
    vulkan: bool,
    directx: bool,
    webgpu: bool,
    custom_allocator: bool,
    debug: bool,
    window_system: WindowSystem,
};

pub const AllocatorHooks = if (features.custom_allocator) struct {
    allocator: std.mem.Allocator,

    extern fn rgfw_zig_set_allocator(
        context: ?*anyopaque,
        allocate: ?*const fn (?*anyopaque, usize, usize) callconv(.c) ?*anyopaque,
        free: ?*const fn (?*anyopaque, ?*anyopaque, usize, usize) callconv(.c) void,
    ) callconv(.c) void;

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    /// Installs this bridge globally. It must outlive every RGFW Context and resource.
    pub fn install(hooks: *@This()) void {
        rgfw_zig_set_allocator(hooks, allocate, free);
    }

    /// Restores the C allocator. Call only after all RGFW resources have been deinitialized.
    pub fn uninstall() void {
        rgfw_zig_set_allocator(null, null, null);
    }

    fn allocate(
        erased: ?*anyopaque,
        size: usize,
        alignment: usize,
    ) callconv(.c) ?*anyopaque {
        const hooks: *@This() = @ptrCast(@alignCast(erased.?));
        const memory = hooks.allocator.rawAlloc(
            size,
            .fromByteUnits(alignment),
            @returnAddress(),
        ) orelse return null;
        return @ptrCast(memory);
    }

    fn free(
        erased: ?*anyopaque,
        pointer: ?*anyopaque,
        size: usize,
        alignment: usize,
    ) callconv(.c) void {
        const hooks: *@This() = @ptrCast(@alignCast(erased.?));
        const bytes: [*]u8 = @ptrCast(pointer orelse return);
        hooks.allocator.rawFree(
            bytes[0..size],
            .fromByteUnits(alignment),
            @returnAddress(),
        );
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW allocator hooks are disabled; build with -Dcustom-allocator=true");
    }
};

pub const Backend = enum {
    none,
    opengl,
    egl,
    vulkan,
};

pub const InitOptions = struct {
    backend: Backend = .none,
    diagnostic_handler: ?DiagnosticHandler = null,
};

pub const InitError = error{
    BackendNotEnabled,
    InitializationFailed,
};

pub const InitializationFailure = struct {
    status: i32,
    backend: Backend,
    window_system: WindowSystem,
};

pub const InitializationWarning = struct {
    status: i32,
    window_system: WindowSystem,
};

pub const InitResult = union(enum) {
    context: Context,
    failure: InitializationFailure,
};

pub const DiagnosticSeverity = enum(raw.RGFW_debugType) {
    err = raw.RGFW_typeError,
    warning = raw.RGFW_typeWarning,
    info = raw.RGFW_typeInfo,
    _,
};

pub const DiagnosticCode = enum(raw.RGFW_errorCode) {
    none = raw.RGFW_noError,
    out_of_memory = raw.RGFW_errOutOfMemory,
    opengl_context = raw.RGFW_errOpenGLContext,
    egl_context = raw.RGFW_errEGLContext,
    wayland = raw.RGFW_errWayland,
    x11 = raw.RGFW_errX11,
    directx_context = raw.RGFW_errDirectXContext,
    iokit = raw.RGFW_errIOKit,
    clipboard = raw.RGFW_errClipboard,
    failed_function_load = raw.RGFW_errFailedFuncLoad,
    buffer = raw.RGFW_errBuffer,
    metal = raw.RGFW_errMetal,
    platform = raw.RGFW_errPlatform,
    event_queue = raw.RGFW_errEventQueue,
    not_initialized = raw.RGFW_errNoInit,
    window_info = raw.RGFW_infoWindow,
    buffer_info = raw.RGFW_infoBuffer,
    global_info = raw.RGFW_infoGlobal,
    opengl_info = raw.RGFW_infoOpenGL,
    wayland_warning = raw.RGFW_warningWayland,
    opengl_warning = raw.RGFW_warningOpenGL,
    _,
};

pub const Diagnostic = struct {
    severity: DiagnosticSeverity,
    code: DiagnosticCode,
    message: []const u8,
};

pub const DiagnosticHandler = struct {
    context: ?*anyopaque,
    dispatch: *const fn (?*anyopaque, Diagnostic) void,

    pub fn fromHandler(comptime handler: anytype) DiagnosticHandler {
        if (@TypeOf(handler) != fn (Diagnostic) void) {
            @compileError("diagnostic handler must have type `fn (rgfw.Diagnostic) void`");
        }
        const Adapter = struct {
            fn dispatch(_: ?*anyopaque, diagnostic: Diagnostic) void {
                handler(diagnostic);
            }
        };
        return .{ .context = null, .dispatch = Adapter.dispatch };
    }

    pub fn fromHandlerWithContext(context: anytype, comptime handler: anytype) DiagnosticHandler {
        const ContextPointer = @TypeOf(context);
        comptime requireContextPointer(ContextPointer, "diagnostic handler context");
        if (@TypeOf(handler) != fn (ContextPointer, Diagnostic) void) {
            @compileError("diagnostic handler must accept its context pointer and rgfw.Diagnostic");
        }
        const Adapter = struct {
            fn dispatch(erased: ?*anyopaque, diagnostic: Diagnostic) void {
                handler(@ptrCast(@alignCast(erased.?)), diagnostic);
            }
        };
        return .{ .context = @ptrCast(context), .dispatch = Adapter.dispatch };
    }
};

var active_diagnostic_handler: ?DiagnosticHandler = null;

fn diagnosticCallback(info: [*c]const raw.RGFW_debugInfo) callconv(.c) void {
    if (info == null) return;
    const handler = active_diagnostic_handler orelse return;
    const message = if (info.*.msg == null)
        ""
    else
        std.mem.span(@as([*:0]const u8, @ptrCast(info.*.msg)));
    handler.dispatch(handler.context, .{
        .severity = @enumFromInt(info.*.type),
        .code = @enumFromInt(info.*.code),
        .message = message,
    });
}

/// The single owning RGFW process context. Do not copy a live value.
/// deinit is idempotent and invalidates every borrowed window, monitor, and native handle.
pub const Context = struct {
    active: bool = true,
    warning: ?InitializationWarning = null,
    warning_code: ?i32 = null,
    previous_debug_callback: raw.RGFW_debugFunc = null,
    previous_diagnostic_handler: ?DiagnosticHandler = null,
    owns_diagnostic_handler: bool = false,

    pub fn deinit(context: *Context) void {
        if (!context.active) return;
        if (context.owns_diagnostic_handler) {
            _ = raw.RGFW_setDebugCallback(context.previous_debug_callback);
            active_diagnostic_handler = context.previous_diagnostic_handler;
            context.owns_diagnostic_handler = false;
        }
        for (&event_handler_slots) |*slot| slot.* = null;
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

    /// Polls the platform once and queues events for every RGFW window.
    pub fn pollEvents(context: *const Context) void {
        std.debug.assert(context.active);
        raw.RGFW_pollEvents();
    }

    /// Waits until the platform reports another event.
    pub fn waitForNextEvent(context: *const Context) void {
        std.debug.assert(context.active);
        raw.RGFW_waitForEvent(@intCast(raw.RGFW_eventWaitNext));
    }

    pub fn waitForEvent(context: *const Context, timeout: EventWait) void {
        std.debug.assert(context.active);
        raw.RGFW_waitForEvent(timeout.toRaw());
    }

    pub fn setEventQueueEnabled(context: *const Context, enabled: bool) void {
        std.debug.assert(context.active);
        raw.RGFW_setQueueEvents(@intFromBool(enabled));
    }

    pub fn setDragAndDropCollectionEnabled(context: *const Context, enabled: bool) void {
        std.debug.assert(context.active);
        raw.RGFW_setBuildDND(@intFromBool(enabled));
    }

    pub fn setGlobalRawMouseMode(context: *const Context, enabled: bool) void {
        std.debug.assert(context.active);
        raw.RGFW_setRawMouseMode(@intFromBool(enabled));
    }

    pub fn stopEventCheck(context: *const Context) void {
        std.debug.assert(context.active);
        raw.RGFW_stopCheckEvents();
    }

    pub fn flushEvents(context: *const Context) void {
        std.debug.assert(context.active);
        raw.RGFW_eventQueueFlush();
    }

    pub fn nextQueuedEvent(context: *const Context) ?Event {
        std.debug.assert(context.active);
        const event = raw.RGFW_eventQueuePop() orelse return null;
        return Event.fromRaw(event.*);
    }

    /// Returns an allocator-owned slice of monitor handles borrowed from Context.
    /// Free the slice with gpa. refreshMonitors and Context.deinit invalidate its handles.
    pub fn monitors(
        context: *const Context,
        gpa: std.mem.Allocator,
    ) (Monitor.Error || std.mem.Allocator.Error)![]Monitor {
        std.debug.assert(context.active);
        var count: usize = 0;
        if (raw.RGFW_getMonitorsPtr(0, null, &count) == 0) {
            return error.QueryFailed;
        }
        if (count == 0) return gpa.alloc(Monitor, 0);

        const handles = try gpa.alloc([*c]raw.RGFW_monitor, count);
        defer gpa.free(handles);
        var written: usize = 0;
        if (raw.RGFW_getMonitorsPtr(count, handles.ptr, &written) == 0) {
            return error.QueryFailed;
        }
        if (written > count) return error.QueryFailed;

        const result = try gpa.alloc(Monitor, written);
        errdefer gpa.free(result);
        for (handles[0..written], result) |handle, *monitor_value| {
            if (handle == null) return error.QueryFailed;
            monitor_value.* = .{ .handle = @ptrCast(handle) };
        }
        return result;
    }

    /// Returns a monitor borrowed until monitor refresh or Context.deinit.
    pub fn primaryMonitor(context: *const Context) ?Monitor {
        std.debug.assert(context.active);
        const handle = raw.RGFW_getPrimaryMonitor();
        if (handle == null) return null;
        return .{ .handle = @ptrCast(handle) };
    }

    pub fn refreshMonitors(context: *const Context) void {
        std.debug.assert(context.active);
        raw.RGFW_pollMonitors();
    }

    /// Returns a display-level native handle borrowed until Context.deinit.
    pub fn nativeDisplayHandle(context: *const Context) HandleError!NativeDisplayHandle {
        if (!context.active) return error.InactiveObject;
        return switch (window_system) {
            .cocoa => .{ .cocoa = raw.RGFW_getLayer_OSX() orelse
                return error.NativeHandleUnavailable },
            .win32 => .{ .win32 = {} },
            .x11 => .{ .x11 = raw.RGFW_getDisplay_X11() orelse
                return error.NativeHandleUnavailable },
            .wayland => .{ .wayland = @ptrCast(raw.RGFW_getDisplay_Wayland() orelse
                return error.NativeHandleUnavailable) },
            .custom => .{ .custom = {} },
        };
    }

    pub fn on(
        context: *const Context,
        comptime descriptor: anytype,
        comptime handler: anytype,
    ) HandleError!EventSubscription {
        if (!context.active) return error.InactiveObject;
        return EventSubscription.install(descriptor, null, handler);
    }

    pub fn onWithContext(
        context: *const Context,
        comptime descriptor: anytype,
        handler_context: anytype,
        comptime handler: anytype,
    ) HandleError!EventSubscription {
        if (!context.active) return error.InactiveObject;
        return EventSubscription.install(descriptor, handler_context, handler);
    }
};

pub fn init(class_name: [:0]const u8, options: InitOptions) InitError!Context {
    return switch (try initResult(class_name, options)) {
        .context => |context| context,
        .failure => error.InitializationFailed,
    };
}

pub fn initResult(class_name: [:0]const u8, options: InitOptions) InitError!InitResult {
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
    if (status < 0) return .{ .failure = .{
        .status = status,
        .backend = options.backend,
        .window_system = window_system,
    } };

    var context: Context = .{
        .warning = if (status > 0) .{
            .status = status,
            .window_system = window_system,
        } else null,
        .warning_code = if (status > 0) status else null,
    };
    if (options.diagnostic_handler) |handler| {
        context.previous_diagnostic_handler = active_diagnostic_handler;
        active_diagnostic_handler = handler;
        context.previous_debug_callback = raw.RGFW_setDebugCallback(diagnosticCallback);
        context.owns_diagnostic_handler = true;
    }
    return .{ .context = context };
}

pub fn pollEvents() void {
    raw.RGFW_pollEvents();
}

pub fn waitForNextEvent() void {
    raw.RGFW_waitForEvent(@intCast(raw.RGFW_eventWaitNext));
}

pub const Platform = struct {
    /// Changes the process working directory to the macOS application resource directory.
    pub fn moveToApplicationResources() void {
        if (comptime window_system != .cocoa) {
            @compileError(
                "Platform.moveToApplicationResources is only available with Cocoa",
            );
        }
        raw.RGFW_moveToMacOSResourceDir();
    }
};

pub const EventWait = union(enum) {
    poll,
    forever,
    milliseconds: u31,

    pub fn toRaw(wait: EventWait) raw.RGFW_eventWait {
        return switch (wait) {
            .poll => @intCast(raw.RGFW_eventNoWait),
            .forever => @intCast(raw.RGFW_eventWaitNext),
            .milliseconds => |milliseconds| @intCast(milliseconds),
        };
    }
};

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

    /// Returns the cursor position in global desktop coordinates.
    pub fn globalMousePosition() ?Point {
        var x: i32 = 0;
        var y: i32 = 0;
        if (raw.RGFW_getGlobalMouse(&x, &y) == 0) return null;
        return .{ .x = x, .y = y };
    }

    /// Converts a platform key code to RGFW's physical key representation.
    pub fn keyFromAPI(key_code: u32) Key {
        return @enumFromInt(raw.RGFW_apiKeyToRGFW(key_code));
    }

    /// Converts an RGFW key to the active platform's physical key code.
    pub fn keyToAPI(key: Key) u32 {
        return raw.RGFW_rgfwToApiKey(@intFromEnum(key));
    }

    /// Applies the active keyboard layout to a physical RGFW key.
    pub fn mappedKey(key: Key) Key {
        return @enumFromInt(raw.RGFW_physicalToMappedKey(@intFromEnum(key)));
    }
};

pub const Clipboard = struct {
    pub const Error = error{
        ReadFailed,
        WriteFailed,
        BufferTooSmall,
    };

    pub const Transfer = struct {
        kind: DataTransferKind,
        bytes: []const u8,
    };

    pub const OwnedTransfer = struct {
        kind: DataTransferKind,
        bytes: []u8,

        pub fn deinit(transfer: *OwnedTransfer, gpa: std.mem.Allocator) void {
            if (transfer.bytes.len == 0) return;
            gpa.free(transfer.bytes);
            transfer.bytes = &.{};
        }
    };

    /// Returns RGFW-owned text invalidated by the next clipboard read/write or Context.deinit.
    pub fn readTextBorrowed() ?[]const u8 {
        const transfer = read(.text) orelse return null;
        return transfer.bytes;
    }

    /// Compatibility alias for readTextBorrowed. Prefer readTextAlloc for retained text.
    pub fn readText() ?[]const u8 {
        return readTextBorrowed();
    }

    /// Returns RGFW-owned data invalidated by the next clipboard read/write or Context.deinit.
    pub fn read(kind: DataTransferKind) ?Transfer {
        const transfer = raw.RGFW_readClipboard(@intFromEnum(kind)) orelse return null;
        const bytes = transfer.*.data orelse return null;
        return .{
            .kind = @enumFromInt(transfer.*.type),
            .bytes = bytes[0..transfer.*.length],
        };
    }

    pub fn readInto(buffer: []u8, kind: DataTransferKind) Error!Transfer {
        var transfer = std.mem.zeroes(raw.RGFW_dataTransfer);
        const success = raw.RGFW_readClipboardPtr(
            @intFromEnum(kind),
            buffer.ptr,
            buffer.len,
            &transfer,
        );
        if (success == 0) {
            if (transfer.length > buffer.len) return error.BufferTooSmall;
            return error.ReadFailed;
        }
        if (transfer.length > buffer.len) return error.BufferTooSmall;
        return .{
            .kind = @enumFromInt(transfer.type),
            .bytes = buffer[0..transfer.length],
        };
    }

    pub fn readAlloc(
        gpa: std.mem.Allocator,
        kind: DataTransferKind,
    ) (Error || std.mem.Allocator.Error)!OwnedTransfer {
        const borrowed = read(kind) orelse return error.ReadFailed;
        return .{
            .kind = borrowed.kind,
            .bytes = try gpa.dupe(u8, borrowed.bytes),
        };
    }

    pub fn readTextAlloc(
        gpa: std.mem.Allocator,
    ) (Error || std.mem.Allocator.Error)![]u8 {
        const transfer = try readAlloc(gpa, .text);
        return transfer.bytes;
    }

    pub fn write(kind: DataTransferKind, bytes: []const u8) Error!void {
        const transfer: raw.RGFW_dataTransfer = .{
            .data = bytes.ptr,
            .length = bytes.len,
            .type = @intFromEnum(kind),
        };
        if (raw.RGFW_writeClipboard(&transfer) == 0) return error.WriteFailed;
    }

    pub fn writeText(text: []const u8) bool {
        write(.text, text) catch return false;
        return true;
    }
};

pub const HandleError = error{
    InactiveObject,
    NativeHandleUnavailable,
};

pub const CocoaWindowHandle = struct {
    window: *anyopaque,
    view: *anyopaque,
};

pub const Win32WindowHandle = struct {
    hwnd: *anyopaque,
    hdc: *anyopaque,
};

pub const NativeWindowHandle = union(WindowSystem) {
    cocoa: CocoaWindowHandle,
    win32: Win32WindowHandle,
    x11: u64,
    wayland: *anyopaque,
    custom: *anyopaque,
};

pub const NativeDisplayHandle = union(WindowSystem) {
    cocoa: *anyopaque,
    win32: void,
    x11: *anyopaque,
    wayland: *anyopaque,
    custom: void,
};

pub fn NativeWindowHandleType(comptime kind: WindowSystem) type {
    return switch (kind) {
        .cocoa => CocoaWindowHandle,
        .win32 => Win32WindowHandle,
        .x11 => u64,
        .wayland => *anyopaque,
        .custom => *anyopaque,
    };
}

/// An owning RGFW window. Do not copy a live value; deinit is idempotent.
/// Lifecycle predicates intentionally treat an inactive value as closed. Legacy input/state
/// predicates return their neutral value after deinit, while checked operations return
/// error.InactiveObject. Use rawHandle first when inactive state must be distinguished.
pub const Window = struct {
    handle: ?*raw.RGFW_window,

    pub const Error = ImageError || error{
        InvalidSize,
        CreationFailed,
        InactiveObject,
        MonitorUnavailable,
        OperationFailed,
        IconAssignmentFailed,
        CursorAssignmentFailed,
    };

    pub const Options = struct {
        x: i32 = 0,
        y: i32 = 0,
        width: i32 = 800,
        height: i32 = 450,
        flags: WindowFlags = .{},
        /// An optional convenience key that asks RGFW to close the window.
        /// Keep this null when the application owns all input bindings.
        exit_key: ?Key = null,
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

        if (options.exit_key) |key| {
            raw.RGFW_window_setExitKey(handle, @intFromEnum(key));
        } else {
            raw.RGFW_window_setExitKey(handle, @intCast(raw.RGFW_keyNULL));
        }
        return .{ .handle = handle };
    }

    pub fn deinit(window: *Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_close(handle);
        window.handle = null;
    }

    pub fn rawHandle(window: *const Window) HandleError!*raw.RGFW_window {
        return window.handle orelse error.InactiveObject;
    }

    /// Returns a native handle borrowed until this Window is deinitialized.
    pub fn nativeHandle(window: *const Window) HandleError!NativeWindowHandle {
        return switch (window_system) {
            inline else => |kind| @unionInit(
                NativeWindowHandle,
                @tagName(kind),
                try window.nativeHandleAs(kind),
            ),
        };
    }

    pub fn nativeHandleAs(
        window: *const Window,
        comptime kind: WindowSystem,
    ) HandleError!NativeWindowHandleType(kind) {
        if (kind != window_system) {
            @compileError("native handle kind `" ++ @tagName(kind) ++
                "` does not match configured window system `" ++ @tagName(window_system) ++ "`");
        }
        const handle = try window.rawHandle();
        return switch (kind) {
            .cocoa => .{
                .window = raw.RGFW_window_getWindow_OSX(handle) orelse
                    return error.NativeHandleUnavailable,
                .view = raw.RGFW_window_getView_OSX(handle) orelse
                    return error.NativeHandleUnavailable,
            },
            .win32 => .{
                .hwnd = raw.RGFW_window_getHWND(handle) orelse
                    return error.NativeHandleUnavailable,
                .hdc = raw.RGFW_window_getHDC(handle) orelse
                    return error.NativeHandleUnavailable,
            },
            .x11 => blk: {
                const native = raw.RGFW_window_getWindow_X11(handle);
                if (native == 0) return error.NativeHandleUnavailable;
                break :blk native;
            },
            .wayland => raw.RGFW_window_getWindow_Wayland(handle) orelse
                return error.NativeHandleUnavailable,
            .custom => @ptrCast(raw.RGFW_window_getSrc(handle) orelse
                return error.NativeHandleUnavailable),
        };
    }

    pub fn setNativeLayer(window: *Window, layer: *anyopaque) HandleError!void {
        if (comptime window_system != .cocoa) {
            @compileError("Window.setNativeLayer is only available with the Cocoa window system");
        }
        const handle = try window.rawHandle();
        raw.RGFW_window_setLayer_OSX(handle, layer);
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

    pub fn exitKey(window: *const Window) HandleError!?Key {
        const handle = try window.rawHandle();
        const key: Key = @enumFromInt(raw.RGFW_window_getExitKey(handle));
        return if (key == .none) null else key;
    }

    pub fn setExitKey(window: *Window, key: ?Key) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setExitKey(handle, if (key) |value|
            @intFromEnum(value)
        else
            @intFromEnum(Key.none));
    }

    pub fn flags(window: *const Window) HandleError!WindowFlags {
        const handle = try window.rawHandle();
        return WindowFlags.fromRaw(raw.RGFW_window_getFlags(handle));
    }

    pub fn setFlags(window: *Window, value: WindowFlags) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setFlags(handle, value.toRaw());
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

    /// Queries the platform directly when RGFW's cached window size is insufficient.
    pub fn fetchSize(window: *const Window) HandleError!?Size {
        const handle = try window.rawHandle();
        var width: i32 = 0;
        var height: i32 = 0;
        if (raw.RGFW_window_fetchSize(handle, &width, &height) == 0) return null;
        return .{ .width = width, .height = height };
    }

    /// Requests a client-area resize. RGFW reports the resulting size through
    /// its queued event and callback paths after the platform applies it.
    pub fn resize(window: *Window, width: i32, height: i32) Error!void {
        if (width <= 0) return error.InvalidSize;
        if (height <= 0) return error.InvalidSize;
        const handle = window.handle orelse return error.InactiveObject;
        raw.RGFW_window_resize(handle, width, height);
    }

    pub fn position(window: *const Window) Point {
        const handle = window.handle orelse return .{ .x = 0, .y = 0 };
        var x: i32 = 0;
        var y: i32 = 0;
        _ = raw.RGFW_window_getPosition(handle, &x, &y);
        return .{ .x = x, .y = y };
    }

    pub fn move(window: *Window, point: Point) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_move(handle, point.x, point.y);
    }

    pub fn moveToMonitor(window: *Window, monitor_value: Monitor) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_moveToMonitor(handle, monitor_value.handle);
    }

    pub fn setAspectRatio(window: *Window, ratio: Size) Error!void {
        try validateSize(ratio.width, ratio.height);
        const handle = window.handle orelse return error.InactiveObject;
        raw.RGFW_window_setAspectRatio(handle, ratio.width, ratio.height);
    }

    pub fn setMinSize(window: *Window, size_value: Size) Error!void {
        try validateSize(size_value.width, size_value.height);
        const handle = window.handle orelse return error.InactiveObject;
        raw.RGFW_window_setMinSize(handle, size_value.width, size_value.height);
    }

    pub fn setMaxSize(window: *Window, size_value: Size) Error!void {
        try validateSize(size_value.width, size_value.height);
        const handle = window.handle orelse return error.InactiveObject;
        raw.RGFW_window_setMaxSize(handle, size_value.width, size_value.height);
    }

    pub fn focus(window: *Window) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_focus(handle);
    }

    pub fn raise(window: *Window) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_raise(handle);
    }

    pub fn setOpacity(window: *Window, opacity: u8) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setOpacity(handle, opacity);
    }

    pub fn setMousePassthrough(window: *Window, enabled: bool) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setMousePassthrough(handle, @intFromBool(enabled));
    }

    pub fn mousePosition(window: *const Window) Point {
        const handle = window.handle orelse return .{ .x = 0, .y = 0 };
        var x: i32 = 0;
        var y: i32 = 0;
        _ = raw.RGFW_window_getMouse(handle, &x, &y);
        return .{ .x = x, .y = y };
    }

    pub fn moveMouse(window: *Window, point: Point) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_moveMouse(handle, point.x, point.y);
    }

    pub fn mouseInside(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMouseInside(handle) != 0;
    }

    pub fn dataDragging(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isDataDragging(handle) != 0;
    }

    pub fn dataDragPosition(window: *const Window) ?Point {
        const handle = window.handle orelse return null;
        var x: i32 = 0;
        var y: i32 = 0;
        if (raw.RGFW_window_getDataDrag(handle, &x, &y) == 0) return null;
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

    pub fn setFullscreen(window: *Window, enabled: bool) Error!void {
        const handle = window.handle orelse return error.InactiveObject;
        if (raw.RGFW_window_getMonitor(handle) == null) {
            return error.MonitorUnavailable;
        }
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

    /// Captures the pointer and enables raw mouse motion in one operation.
    pub fn captureRawMouse(window: *Window, enabled: bool) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_captureRawMouse(handle, @intFromBool(enabled));
    }

    pub fn rawMouseMode(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isRawMouseMode(handle) != 0;
    }

    pub fn mouseCaptured(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isCaptured(handle) != 0;
    }

    pub fn mouseHidden(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_window_isMouseHidden(handle) != 0;
    }

    /// Applies the complete pointer visibility/capture state atomically from Zig's perspective.
    pub fn setCursorMode(window: *Window, mode: CursorMode) void {
        switch (mode) {
            .normal => {
                window.captureRawMouse(false);
                window.showMouse(true);
            },
            .hidden => {
                window.captureRawMouse(false);
                window.showMouse(false);
            },
            .captured => {
                window.captureRawMouse(true);
                window.showMouse(false);
            },
        }
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

    pub fn scaleToMonitor(window: *Window) Error!void {
        const handle = window.handle orelse return error.InactiveObject;
        if (raw.RGFW_window_getMonitor(handle) == null) {
            return error.MonitorUnavailable;
        }
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

    pub fn setCursor(window: *Window, cursor: *const CustomCursor) Error!void {
        const handle = window.handle orelse return error.InactiveObject;
        const cursor_handle = cursor.handle orelse return error.InactiveObject;
        if (raw.RGFW_window_setMouse(handle, cursor_handle) == 0) {
            return error.CursorAssignmentFailed;
        }
    }

    pub fn resetCursor(window: *Window) Error!void {
        const handle = window.handle orelse return error.InactiveObject;
        if (raw.RGFW_window_setMouseDefault(handle) == 0) {
            return error.CursorAssignmentFailed;
        }
    }

    pub fn setIcon(window: *Window, image: Image, target: IconTarget) Error!void {
        const handle = window.handle orelse return error.InactiveObject;
        _ = try image.requiredBytes();
        if (raw.RGFW_window_setIconEx(
            handle,
            image.pixels.ptr,
            image.width,
            image.height,
            @intFromEnum(image.format),
            @intFromEnum(target),
        ) == 0) return error.IconAssignmentFailed;
    }

    pub fn enabledEvents(window: *const Window) HandleError!EventMask {
        const handle = try window.rawHandle();
        return EventMask.fromRaw(raw.RGFW_window_getEnabledEvents(handle));
    }

    pub fn setEnabledEvents(window: *Window, mask: EventMask) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setEnabledEvents(handle, mask.toRaw());
    }

    pub fn disableEvents(window: *Window, mask: EventMask) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setDisabledEvents(handle, mask.toRaw());
    }

    pub fn setEventEnabled(
        window: *Window,
        kind: EventKind,
        enabled: bool,
    ) HandleError!void {
        const handle = try window.rawHandle();
        raw.RGFW_window_setEventState(
            handle,
            EventMask.single(kind).toRaw(),
            @intFromBool(enabled),
        );
    }

    pub fn monitor(window: *const Window) ?Monitor {
        const handle = window.handle orelse return null;
        const monitor_handle = raw.RGFW_window_getMonitor(handle);
        if (monitor_handle == null) return null;
        return .{ .handle = @ptrCast(monitor_handle) };
    }

    /// Pops one event already queued by `Context.pollEvents` or `rgfw.pollEvents`.
    /// This function never polls the platform itself.
    pub fn nextQueuedEvent(window: *Window) ?Event {
        const handle = window.handle orelse return null;
        var event: raw.RGFW_event = undefined;
        if (raw.RGFW_window_checkQueuedEvent(handle, &event) == 0) return null;
        return Event.fromRaw(event);
    }

    /// Concise alias for `nextQueuedEvent`.
    pub fn nextEvent(window: *Window) ?Event {
        return window.nextQueuedEvent();
    }

    /// Polls when needed and returns one event. Prefer `pollEvents` plus `nextEvent`
    /// when the application needs a stable, once-per-frame event batch.
    pub fn pollEvent(window: *Window) ?Event {
        const handle = window.handle orelse return null;
        var event: raw.RGFW_event = undefined;
        if (raw.RGFW_window_checkEvent(handle, &event) == 0) return null;
        return Event.fromRaw(event);
    }

    pub fn events(window: *Window) EventIterator {
        return .{ .window = window };
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

pub const EventIterator = struct {
    window: *Window,

    pub fn next(iterator: *EventIterator) ?Event {
        return iterator.window.nextQueuedEvent();
    }
};

pub const Size = struct {
    width: i32,
    height: i32,
};

fn validateSize(width: i32, height: i32) Window.Error!void {
    if (width <= 0) return error.InvalidSize;
    if (height <= 0) return error.InvalidSize;
}

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Vector = struct {
    x: f32,
    y: f32,
};

pub const CursorMode = enum {
    normal,
    hidden,
    captured,
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

    pub fn fromRaw(value: raw.RGFW_windowFlags) WindowFlags {
        return .{
            .no_border = hasFlag(value, raw.RGFW_windowNoBorder),
            .no_resize = hasFlag(value, raw.RGFW_windowNoResize),
            .allow_drag_and_drop = hasFlag(value, raw.RGFW_windowAllowDND),
            .hide_mouse = hasFlag(value, raw.RGFW_windowHideMouse),
            .fullscreen = hasFlag(value, raw.RGFW_windowFullscreen),
            .translucent = hasFlag(value, raw.RGFW_windowTranslucent),
            .centered = hasFlag(value, raw.RGFW_windowCenter),
            .raw_mouse = hasFlag(value, raw.RGFW_windowRawMouse),
            .scale_to_monitor = hasFlag(value, raw.RGFW_windowScaleToMonitor),
            .hidden = hasFlag(value, raw.RGFW_windowHide),
            .maximized = hasFlag(value, raw.RGFW_windowMaximize),
            .center_cursor = hasFlag(value, raw.RGFW_windowCenterCursor),
            .floating = hasFlag(value, raw.RGFW_windowFloating),
            .focus_on_show = hasFlag(value, raw.RGFW_windowFocusOnShow),
            .minimized = hasFlag(value, raw.RGFW_windowMinimize),
            .focused = hasFlag(value, raw.RGFW_windowFocus),
            .capture_mouse = hasFlag(value, raw.RGFW_windowCaptureMouse),
            .open_gl = hasFlag(value, raw.RGFW_windowOpenGL),
            .egl = hasFlag(value, raw.RGFW_windowEGL),
        };
    }

    fn addFlag(result: *raw.RGFW_windowFlags, enabled: bool, value: c_int) void {
        if (enabled) result.* |= @intCast(value);
    }

    fn hasFlag(value: raw.RGFW_windowFlags, flag: c_int) bool {
        return value & @as(raw.RGFW_windowFlags, @intCast(flag)) != 0;
    }
};

pub const EventMask = struct {
    key_pressed: bool = false,
    key_released: bool = false,
    key_character: bool = false,
    mouse_button_pressed: bool = false,
    mouse_button_released: bool = false,
    mouse_scroll: bool = false,
    mouse_motion: bool = false,
    mouse_raw_motion: bool = false,
    mouse_enter: bool = false,
    mouse_leave: bool = false,
    window_moved: bool = false,
    window_resized: bool = false,
    window_focus_in: bool = false,
    window_focus_out: bool = false,
    window_refresh: bool = false,
    window_close: bool = false,
    window_maximized: bool = false,
    window_minimized: bool = false,
    window_restored: bool = false,
    data_drop: bool = false,
    data_drag: bool = false,
    scale_updated: bool = false,
    monitor_connected: bool = false,
    monitor_disconnected: bool = false,

    pub const all: EventMask = fromRaw(raw.RGFW_allEventFlags);
    pub const keyboard: EventMask = fromRaw(raw.RGFW_keyEventsFlag);
    pub const mouse: EventMask = fromRaw(raw.RGFW_mouseEventsFlag);
    pub const window: EventMask = fromRaw(raw.RGFW_windowEventsFlag);
    pub const focus: EventMask = fromRaw(raw.RGFW_windowFocusEventsFlag);
    pub const drag_and_drop: EventMask = fromRaw(raw.RGFW_dataDragDropEventsFlag);
    pub const monitor: EventMask = fromRaw(raw.RGFW_monitorEventsFlag);

    pub fn single(kind: EventKind) EventMask {
        var result: EventMask = .{};
        switch (kind) {
            .none => {},
            inline else => |tag| @field(result, @tagName(tag)) = true,
        }
        return result;
    }

    pub fn toRaw(mask: EventMask) raw.RGFW_eventFlag {
        @setEvalBranchQuota(10_000);
        var result: raw.RGFW_eventFlag = 0;
        inline for (@typeInfo(EventMask).@"struct".fields) |field| {
            if (@field(mask, field.name)) {
                const kind: EventKind = @field(EventKind, field.name);
                result |= @as(raw.RGFW_eventFlag, 1) << @intCast(@intFromEnum(kind));
            }
        }
        return result;
    }

    pub fn fromRaw(value: raw.RGFW_eventFlag) EventMask {
        @setEvalBranchQuota(10_000);
        var result: EventMask = .{};
        inline for (@typeInfo(EventMask).@"struct".fields) |field| {
            const kind: EventKind = @field(EventKind, field.name);
            const flag = @as(raw.RGFW_eventFlag, 1) << @intCast(@intFromEnum(kind));
            @field(result, field.name) = value & flag != 0;
        }
        return result;
    }
};

pub const Key = enum(raw.RGFW_key) {
    none = raw.RGFW_keyNULL,
    escape = raw.RGFW_keyEscape,
    backtick = raw.RGFW_keyBacktick,
    zero = raw.RGFW_key0,
    one = raw.RGFW_key1,
    two = raw.RGFW_key2,
    three = raw.RGFW_key3,
    four = raw.RGFW_key4,
    five = raw.RGFW_key5,
    six = raw.RGFW_key6,
    seven = raw.RGFW_key7,
    eight = raw.RGFW_key8,
    nine = raw.RGFW_key9,
    minus = raw.RGFW_keyMinus,
    equal = raw.RGFW_keyEqual,
    backspace = raw.RGFW_keyBackSpace,
    tab = raw.RGFW_keyTab,
    space = raw.RGFW_keySpace,
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
    period = raw.RGFW_keyPeriod,
    comma = raw.RGFW_keyComma,
    slash = raw.RGFW_keySlash,
    bracket_left = raw.RGFW_keyBracket,
    bracket_right = raw.RGFW_keyCloseBracket,
    semicolon = raw.RGFW_keySemicolon,
    apostrophe = raw.RGFW_keyApostrophe,
    backslash = raw.RGFW_keyBackSlash,
    enter = raw.RGFW_keyEnter,
    delete = raw.RGFW_keyDelete,
    f1 = raw.RGFW_keyF1,
    f2 = raw.RGFW_keyF2,
    f3 = raw.RGFW_keyF3,
    f4 = raw.RGFW_keyF4,
    f5 = raw.RGFW_keyF5,
    f6 = raw.RGFW_keyF6,
    f7 = raw.RGFW_keyF7,
    f8 = raw.RGFW_keyF8,
    f9 = raw.RGFW_keyF9,
    f10 = raw.RGFW_keyF10,
    f11 = raw.RGFW_keyF11,
    f12 = raw.RGFW_keyF12,
    f13 = raw.RGFW_keyF13,
    f14 = raw.RGFW_keyF14,
    f15 = raw.RGFW_keyF15,
    f16 = raw.RGFW_keyF16,
    f17 = raw.RGFW_keyF17,
    f18 = raw.RGFW_keyF18,
    f19 = raw.RGFW_keyF19,
    f20 = raw.RGFW_keyF20,
    f21 = raw.RGFW_keyF21,
    f22 = raw.RGFW_keyF22,
    f23 = raw.RGFW_keyF23,
    f24 = raw.RGFW_keyF24,
    f25 = raw.RGFW_keyF25,
    caps_lock = raw.RGFW_keyCapsLock,
    shift_left = raw.RGFW_keyShiftL,
    control_left = raw.RGFW_keyControlL,
    alt_left = raw.RGFW_keyAltL,
    super_left = raw.RGFW_keySuperL,
    shift_right = raw.RGFW_keyShiftR,
    control_right = raw.RGFW_keyControlR,
    alt_right = raw.RGFW_keyAltR,
    super_right = raw.RGFW_keySuperR,
    up = raw.RGFW_keyUp,
    down = raw.RGFW_keyDown,
    left = raw.RGFW_keyLeft,
    right = raw.RGFW_keyRight,
    insert = raw.RGFW_keyInsert,
    menu = raw.RGFW_keyMenu,
    end = raw.RGFW_keyEnd,
    home = raw.RGFW_keyHome,
    page_up = raw.RGFW_keyPageUp,
    page_down = raw.RGFW_keyPageDown,
    num_lock = raw.RGFW_keyNumLock,
    keypad_slash = raw.RGFW_keyPadSlash,
    keypad_multiply = raw.RGFW_keyPadMultiply,
    keypad_plus = raw.RGFW_keyPadPlus,
    keypad_minus = raw.RGFW_keyPadMinus,
    keypad_equal = raw.RGFW_keyPadEqual,
    keypad_one = raw.RGFW_keyPad1,
    keypad_two = raw.RGFW_keyPad2,
    keypad_three = raw.RGFW_keyPad3,
    keypad_four = raw.RGFW_keyPad4,
    keypad_five = raw.RGFW_keyPad5,
    keypad_six = raw.RGFW_keyPad6,
    keypad_seven = raw.RGFW_keyPad7,
    keypad_eight = raw.RGFW_keyPad8,
    keypad_nine = raw.RGFW_keyPad9,
    keypad_zero = raw.RGFW_keyPad0,
    keypad_period = raw.RGFW_keyPadPeriod,
    keypad_enter = raw.RGFW_keyPadReturn,
    scroll_lock = raw.RGFW_keyScrollLock,
    print_screen = raw.RGFW_keyPrintScreen,
    pause = raw.RGFW_keyPause,
    world_one = raw.RGFW_keyWorld1,
    world_two = raw.RGFW_keyWorld2,
    _,
};

pub const MouseButton = enum(raw.RGFW_mouseButton) {
    left = raw.RGFW_mouseLeft,
    middle = raw.RGFW_mouseMiddle,
    right = raw.RGFW_mouseRight,
    auxiliary_one = raw.RGFW_mouseMisc1,
    auxiliary_two = raw.RGFW_mouseMisc2,
    auxiliary_three = raw.RGFW_mouseMisc3,
    auxiliary_four = raw.RGFW_mouseMisc4,
    auxiliary_five = raw.RGFW_mouseMisc5,
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
    resize_northwest_southeast = raw.RGFW_mouseResizeNWSE,
    resize_northeast_southwest = raw.RGFW_mouseResizeNESW,
    resize_northwest = raw.RGFW_mouseResizeNW,
    resize_north = raw.RGFW_mouseResizeN,
    resize_northeast = raw.RGFW_mouseResizeNE,
    resize_east = raw.RGFW_mouseResizeE,
    resize_southeast = raw.RGFW_mouseResizeSE,
    resize_south = raw.RGFW_mouseResizeS,
    resize_southwest = raw.RGFW_mouseResizeSW,
    resize_west = raw.RGFW_mouseResizeW,
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

    pub fn channelCount(format: ImageFormat) u3 {
        return switch (format) {
            .rgb8, .bgr8 => 3,
            .rgba8, .argb8, .bgra8, .abgr8 => 4,
        };
    }
};

pub const ImageError = error{
    InvalidDimensions,
    BufferTooSmall,
};

pub const ColorLayout = struct {
    red_index: i32,
    green_index: i32,
    blue_index: i32,
    alpha_index: i32,
    channels: u32,

    fn fromRaw(layout: raw.RGFW_colorLayout) ColorLayout {
        return .{
            .red_index = layout.r,
            .green_index = layout.g,
            .blue_index = layout.b,
            .alpha_index = layout.a,
            .channels = layout.channels,
        };
    }
};

pub const ImageConvertHandler = fn (
    destination: []u8,
    source: []const u8,
    source_layout: ColorLayout,
    destination_layout: ColorLayout,
    pixel_count: usize,
) void;

pub fn imageConvertFunction(comptime handler: anytype) raw.RGFW_convertImageDataFunc {
    if (@TypeOf(handler) != ImageConvertHandler) {
        @compileError("image conversion handler must have type `rgfw.ImageConvertHandler`");
    }
    const Adapter = struct {
        fn convert(
            destination: [*c]u8,
            source: [*c]u8,
            source_layout: [*c]const raw.RGFW_colorLayout,
            destination_layout: [*c]const raw.RGFW_colorLayout,
            pixel_count: usize,
        ) callconv(.c) void {
            if (destination == null or source == null or
                source_layout == null or destination_layout == null) return;
            const source_length = std.math.mul(
                usize,
                pixel_count,
                source_layout.*.channels,
            ) catch return;
            const destination_length = std.math.mul(
                usize,
                pixel_count,
                destination_layout.*.channels,
            ) catch return;
            handler(
                destination[0..destination_length],
                source[0..source_length],
                .fromRaw(source_layout.*),
                .fromRaw(destination_layout.*),
                pixel_count,
            );
        }
    };
    return Adapter.convert;
}

/// A caller-owned mutable pixel buffer. RGFW does not take ownership of the pixels.
pub const Image = struct {
    pixels: []u8,
    width: i32,
    height: i32,
    format: ImageFormat,

    pub fn init(
        pixels: []u8,
        width: i32,
        height: i32,
        format: ImageFormat,
    ) ImageError!Image {
        const image: Image = .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .format = format,
        };
        _ = try image.requiredBytes();
        return image;
    }

    pub fn requiredBytes(image: Image) ImageError!usize {
        if (image.width <= 0) return error.InvalidDimensions;
        if (image.height <= 0) return error.InvalidDimensions;
        const pixel_count = std.math.mul(
            usize,
            @intCast(image.width),
            @intCast(image.height),
        ) catch return error.InvalidDimensions;
        const byte_count = std.math.mul(
            usize,
            pixel_count,
            image.format.channelCount(),
        ) catch return error.InvalidDimensions;
        if (image.pixels.len < byte_count) return error.BufferTooSmall;
        return byte_count;
    }
};

pub const IconTarget = enum(raw.RGFW_icon) {
    taskbar = raw.RGFW_iconTaskbar,
    window = raw.RGFW_iconWindow,
    both = raw.RGFW_iconBoth,
};

/// An owning RGFW cursor. Do not copy a live value; call deinit exactly once per owner.
pub const CustomCursor = struct {
    handle: ?*raw.RGFW_mouse,

    pub const Error = ImageError || error{CreationFailed};

    pub fn init(
        pixels: []u8,
        width: i32,
        height: i32,
        format: ImageFormat,
    ) Error!CustomCursor {
        const image = try Image.init(pixels, width, height, format);
        const handle = raw.RGFW_createMouse(
            image.pixels.ptr,
            image.width,
            image.height,
            @intFromEnum(image.format),
        ) orelse return error.CreationFailed;
        return .{ .handle = handle };
    }

    pub fn deinit(cursor: *CustomCursor) void {
        const handle = cursor.handle orelse return;
        raw.RGFW_freeMouse(handle);
        cursor.handle = null;
    }

    pub fn rawHandle(cursor: *const CustomCursor) HandleError!*raw.RGFW_mouse {
        return cursor.handle orelse error.InactiveObject;
    }
};

/// An owning RGFW software surface borrowing its caller-owned pixel buffer.
/// Do not copy a live value; keep pixels alive until idempotent deinit completes.
pub const Surface = struct {
    handle: ?*raw.RGFW_surface,

    pub const Error = ImageError || error{CreationFailed};

    pub fn init(
        pixels: []u8,
        width: i32,
        height: i32,
        format: ImageFormat,
    ) Error!Surface {
        const image = try Image.init(pixels, width, height, format);
        const handle = raw.RGFW_createSurface(
            image.pixels.ptr,
            image.width,
            image.height,
            @intFromEnum(image.format),
        ) orelse return error.CreationFailed;
        return .{ .handle = handle };
    }

    /// Creates a surface using this window's native visual, which is required for X11 safety.
    pub fn initForWindow(
        window: *const Window,
        pixels: []u8,
        width: i32,
        height: i32,
        format: ImageFormat,
    ) (Error || HandleError)!Surface {
        const image = try Image.init(pixels, width, height, format);
        const window_handle = try window.rawHandle();
        const handle = raw.RGFW_window_createSurface(
            window_handle,
            image.pixels.ptr,
            image.width,
            image.height,
            @intFromEnum(image.format),
        ) orelse return error.CreationFailed;
        return .{ .handle = handle };
    }

    pub fn deinit(surface: *Surface) void {
        const handle = surface.handle orelse return;
        raw.RGFW_surface_free(handle);
        surface.handle = null;
    }

    pub fn rawHandle(surface: *const Surface) HandleError!*raw.RGFW_surface {
        return surface.handle orelse error.InactiveObject;
    }

    /// Returns a native image borrowed until this Surface is deinitialized.
    pub fn nativeImage(surface: *const Surface) HandleError!*raw.RGFW_nativeImage {
        const handle = try surface.rawHandle();
        return raw.RGFW_surface_getNativeImage(handle) orelse error.NativeHandleUnavailable;
    }

    pub fn setConvertFunction(surface: *Surface, comptime handler: anytype) HandleError!void {
        return surface.setRawConvertFunction(imageConvertFunction(handler));
    }

    /// Low-level escape hatch for an existing C-compatible conversion callback.
    pub fn setRawConvertFunction(
        surface: *Surface,
        function: raw.RGFW_convertImageDataFunc,
    ) HandleError!void {
        const handle = try surface.rawHandle();
        raw.RGFW_surface_setConvertFunc(handle, function);
    }

    pub fn blit(surface: *const Surface, window: *const Window) HandleError!void {
        const surface_handle = try surface.rawHandle();
        const window_handle = try window.rawHandle();
        raw.RGFW_window_blitSurface(window_handle, surface_handle);
    }
};

pub const ImageUtility = struct {
    pub fn nativeFormat() ImageFormat {
        return @enumFromInt(raw.RGFW_nativeFormat());
    }

    pub fn copy(source: Image, destination: Image) ImageError!void {
        return copyRaw(source, destination, null);
    }

    pub fn copyWith(
        source: Image,
        destination: Image,
        comptime handler: anytype,
    ) ImageError!void {
        return copyRaw(source, destination, imageConvertFunction(handler));
    }

    fn copyRaw(
        source: Image,
        destination: Image,
        converter: raw.RGFW_convertImageDataFunc,
    ) ImageError!void {
        if (source.width != destination.width) return error.InvalidDimensions;
        if (source.height != destination.height) return error.InvalidDimensions;
        _ = try source.requiredBytes();
        _ = try destination.requiredBytes();
        raw.RGFW_copyImageData(
            destination.pixels.ptr,
            destination.width,
            destination.height,
            @intFromEnum(destination.format),
            source.pixels.ptr,
            @intFromEnum(source.format),
            converter,
        );
    }
};

pub const MonitorMode = struct {
    width: i32,
    height: i32,
    refresh_rate: f32,
    red_bits: u8,
    green_bits: u8,
    blue_bits: u8,

    fn fromRaw(mode: raw.RGFW_monitorMode) MonitorMode {
        return .{
            .width = mode.w,
            .height = mode.h,
            .refresh_rate = mode.refreshRate,
            .red_bits = mode.red,
            .green_bits = mode.green,
            .blue_bits = mode.blue,
        };
    }

    fn toRaw(mode: MonitorMode) raw.RGFW_monitorMode {
        return .{
            .w = mode.width,
            .h = mode.height,
            .refreshRate = mode.refresh_rate,
            .red = mode.red_bits,
            .green = mode.green_bits,
            .blue = mode.blue_bits,
            .src = null,
        };
    }

    pub fn matches(first: MonitorMode, second: MonitorMode, request: ModeRequest) bool {
        var first_raw = first.toRaw();
        var second_raw = second.toRaw();
        return raw.RGFW_monitorModeCompare(
            &first_raw,
            &second_raw,
            request.toRaw(),
        ) != 0;
    }
};

pub const ModeRequest = struct {
    scale: bool = false,
    refresh_rate: bool = false,
    color_depth: bool = false,

    pub const all: ModeRequest = .{
        .scale = true,
        .refresh_rate = true,
        .color_depth = true,
    };

    pub fn toRaw(request: ModeRequest) raw.RGFW_modeRequest {
        var result: raw.RGFW_modeRequest = 0;
        if (request.scale) result |= @intCast(raw.RGFW_monitorScale);
        if (request.refresh_rate) result |= @intCast(raw.RGFW_monitorRefresh);
        if (request.color_depth) result |= @intCast(raw.RGFW_monitorRGB);
        return result;
    }
};

pub const PhysicalSize = struct {
    width_mm: f32,
    height_mm: f32,
};

/// Monitor data copied at the time an event was delivered. Unlike `Monitor`,
/// this value remains valid after a disconnect or a later monitor refresh.
pub const MonitorSnapshot = struct {
    name_bytes: [128]u8,
    position: Point,
    scale: Vector,
    pixel_ratio: f32,
    physical_size: PhysicalSize,
    mode: MonitorMode,

    fn fromRaw(monitor: *const raw.RGFW_monitor) MonitorSnapshot {
        return .{
            .name_bytes = monitor.name,
            .position = .{ .x = monitor.x, .y = monitor.y },
            .scale = .{ .x = monitor.scaleX, .y = monitor.scaleY },
            .pixel_ratio = monitor.pixelRatio,
            .physical_size = .{
                .width_mm = monitor.physW * 25.4,
                .height_mm = monitor.physH * 25.4,
            },
            .mode = .fromRaw(monitor.mode),
        };
    }

    pub fn name(snapshot: *const MonitorSnapshot) []const u8 {
        const end = std.mem.indexOfScalar(u8, &snapshot.name_bytes, 0) orelse
            snapshot.name_bytes.len;
        return snapshot.name_bytes[0..end];
    }
};

pub const GammaRamp = struct {
    red: []const u16,
    green: []const u16,
    blue: []const u16,

    fn validate(ramp: GammaRamp) Monitor.Error!void {
        if (ramp.red.len == 0) return error.InvalidGammaRamp;
        if (ramp.green.len != ramp.red.len) return error.InvalidGammaRamp;
        if (ramp.blue.len != ramp.red.len) return error.InvalidGammaRamp;
    }
};

pub const OwnedGammaRamp = struct {
    storage: []u16,
    count: usize,

    pub fn value(ramp: *const OwnedGammaRamp) GammaRamp {
        return .{
            .red = ramp.storage[0..ramp.count],
            .green = ramp.storage[ramp.count .. ramp.count * 2],
            .blue = ramp.storage[ramp.count * 2 .. ramp.count * 3],
        };
    }

    pub fn deinit(ramp: *OwnedGammaRamp, gpa: std.mem.Allocator) void {
        if (ramp.storage.len == 0) return;
        gpa.free(ramp.storage);
        ramp.storage = &.{};
        ramp.count = 0;
    }
};

/// A monitor borrowed from Context until monitor refresh or Context.deinit.
pub const Monitor = struct {
    handle: *raw.RGFW_monitor,

    pub const Error = error{
        QueryFailed,
        ModeUnavailable,
        ModeChangeFailed,
        InvalidGamma,
        InvalidGammaRamp,
        GammaChangeFailed,
    };

    pub fn rawHandle(monitor: *const Monitor) *raw.RGFW_monitor {
        return monitor.handle;
    }

    /// Returns a name borrowed until monitor refresh or Context.deinit.
    pub fn name(monitor: *const Monitor) ?[:0]const u8 {
        const name_ptr = raw.RGFW_monitor_getName(monitor.handle);
        if (name_ptr == null) return null;
        return std.mem.span(@as([*:0]const u8, @ptrCast(name_ptr)));
    }

    pub fn setGamma(monitor: *Monitor, gamma: f32) Error!void {
        if (!(gamma > 0.0)) return error.InvalidGamma;
        if (raw.RGFW_monitor_setGamma(monitor.handle, gamma) == 0) {
            return error.GammaChangeFailed;
        }
    }

    pub fn workArea(monitor: *const Monitor) Error!Rect {
        var area: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        if (raw.RGFW_monitor_getWorkarea(
            monitor.handle,
            &area.x,
            &area.y,
            &area.width,
            &area.height,
        ) == 0) return error.QueryFailed;
        return area;
    }

    pub fn position(monitor: *const Monitor) Error!Point {
        var point: Point = .{ .x = 0, .y = 0 };
        if (raw.RGFW_monitor_getPosition(monitor.handle, &point.x, &point.y) == 0) {
            return error.QueryFailed;
        }
        return point;
    }

    pub fn scale(monitor: *const Monitor) Error!Vector {
        var result: Vector = .{ .x = 0, .y = 0 };
        if (raw.RGFW_monitor_getScale(monitor.handle, &result.x, &result.y) == 0) {
            return error.QueryFailed;
        }
        return result;
    }

    pub fn physicalSize(monitor: *const Monitor) Error!PhysicalSize {
        var width_inches: f32 = 0;
        var height_inches: f32 = 0;
        if (raw.RGFW_monitor_getPhysicalSize(
            monitor.handle,
            &width_inches,
            &height_inches,
        ) == 0) return error.QueryFailed;
        return .{
            .width_mm = width_inches * 25.4,
            .height_mm = height_inches * 25.4,
        };
    }

    pub fn currentMode(monitor: *const Monitor) Error!MonitorMode {
        var mode: raw.RGFW_monitorMode = undefined;
        if (raw.RGFW_monitor_getMode(monitor.handle, &mode) == 0) {
            return error.ModeUnavailable;
        }
        return .fromRaw(mode);
    }

    pub fn supportedModes(
        monitor: *const Monitor,
        gpa: std.mem.Allocator,
    ) (Error || std.mem.Allocator.Error)![]MonitorMode {
        var count: usize = 0;
        const modes = raw.RGFW_monitor_getModes(monitor.handle, &count);
        if (modes == null) return error.ModeUnavailable;
        defer raw.RGFW_freeModes(modes);

        const result = try gpa.alloc(MonitorMode, count);
        for (modes[0..count], result) |mode, *destination| {
            destination.* = .fromRaw(mode);
        }
        return result;
    }

    pub fn closestMode(
        monitor: *const Monitor,
        requested: MonitorMode,
    ) Error!MonitorMode {
        var requested_raw = requested.toRaw();
        var closest_raw: raw.RGFW_monitorMode = undefined;
        if (raw.RGFW_monitor_findClosestMode(
            monitor.handle,
            &requested_raw,
            &closest_raw,
        ) == 0) return error.ModeUnavailable;
        return .fromRaw(closest_raw);
    }

    pub fn requestMode(
        monitor: *Monitor,
        requested: MonitorMode,
        request: ModeRequest,
    ) Error!void {
        var requested_raw = requested.toRaw();
        if (raw.RGFW_monitor_requestMode(
            monitor.handle,
            &requested_raw,
            request.toRaw(),
        ) == 0) return error.ModeChangeFailed;
    }

    pub fn setMode(monitor: *Monitor, mode: MonitorMode) Error!void {
        try monitor.requestMode(mode, .all);
    }

    pub fn scaleToWindow(monitor: *Monitor, window: *Window) (Error || HandleError)!void {
        const window_handle = try window.rawHandle();
        if (raw.RGFW_monitor_scaleToWindow(monitor.handle, window_handle) == 0) {
            return error.ModeChangeFailed;
        }
    }

    pub fn gammaRamp(
        monitor: *const Monitor,
        gpa: std.mem.Allocator,
    ) (Error || std.mem.Allocator.Error)!OwnedGammaRamp {
        const native = raw.RGFW_monitor_getGammaRamp(monitor.handle);
        if (native == null) return error.QueryFailed;
        defer raw.RGFW_freeGammaRamp(native);
        if (native.*.count == 0) return error.QueryFailed;

        const count = native.*.count;
        const storage = try gpa.alloc(u16, std.math.mul(usize, count, 3) catch {
            return error.QueryFailed;
        });
        @memcpy(storage[0..count], native.*.red[0..count]);
        @memcpy(storage[count .. count * 2], native.*.green[0..count]);
        @memcpy(storage[count * 2 .. count * 3], native.*.blue[0..count]);
        return .{ .storage = storage, .count = count };
    }

    pub fn setGammaRamp(monitor: *Monitor, ramp: GammaRamp) Error!void {
        try ramp.validate();
        var native: raw.RGFW_gammaRamp = .{
            .red = @ptrCast(@constCast(ramp.red.ptr)),
            .green = @ptrCast(@constCast(ramp.green.ptr)),
            .blue = @ptrCast(@constCast(ramp.blue.ptr)),
            .count = ramp.red.len,
        };
        if (raw.RGFW_monitor_setGammaRamp(monitor.handle, &native) == 0) {
            return error.GammaChangeFailed;
        }
    }
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const GraphicsProfile = enum(i32) {
    core = 0,
    forward_compatible = 1,
    compatibility = 2,
    embedded = 3,
    web = 4,
};

pub const GraphicsRenderer = enum(i32) {
    accelerated = 0,
    software = 1,
};

pub const GraphicsReleaseBehavior = enum(i32) {
    flush = 0,
    none = 1,
};

pub const GraphicsHints = struct {
    stencil_bits: i32 = 0,
    samples: i32 = 0,
    stereo: bool = false,
    auxiliary_buffers: i32 = 0,
    double_buffer: bool = true,
    red_bits: i32 = 8,
    green_bits: i32 = 8,
    blue_bits: i32 = 8,
    alpha_bits: i32 = 8,
    depth_bits: i32 = 24,
    accumulation_red_bits: i32 = 0,
    accumulation_green_bits: i32 = 0,
    accumulation_blue_bits: i32 = 0,
    accumulation_alpha_bits: i32 = 0,
    srgb: bool = false,
    robustness: bool = false,
    debug: bool = false,
    no_error: bool = false,
    release_behavior: GraphicsReleaseBehavior = .none,
    profile: GraphicsProfile = .core,
    major_version: i32 = 1,
    minor_version: i32 = 0,
    renderer: GraphicsRenderer = .accelerated,
};

pub const Graphics = if (features.opengl or features.egl) struct {
    /// Stable storage for RGFW's borrowed global-hints pointer.
    pub const GlobalHints = struct {
        raw_value: raw.RGFW_glHints,

        pub fn init(hints: GraphicsHints) GlobalHints {
            return .{ .raw_value = toRaw(hints, null, null) };
        }
    };

    /// RGFW borrows this pointer until resetGlobalHints or Context.deinit.
    pub fn setGlobalHints(hints: *GlobalHints) void {
        raw.RGFW_setGlobalHints_OpenGL(&hints.raw_value);
    }

    pub fn resetGlobalHints() void {
        raw.RGFW_resetGlobalHints_OpenGL();
    }

    /// Returns the currently installed RGFW hint values by copy.
    pub fn currentGlobalHints() ?GraphicsHints {
        const hints = raw.RGFW_getGlobalHints_OpenGL() orelse return null;
        return fromRaw(hints.*);
    }

    fn fromRaw(hints: raw.RGFW_glHints) GraphicsHints {
        return .{
            .stencil_bits = hints.stencil,
            .samples = hints.samples,
            .stereo = hints.stereo != 0,
            .auxiliary_buffers = hints.auxBuffers,
            .double_buffer = hints.doubleBuffer != 0,
            .red_bits = hints.red,
            .green_bits = hints.green,
            .blue_bits = hints.blue,
            .alpha_bits = hints.alpha,
            .depth_bits = hints.depth,
            .accumulation_red_bits = hints.accumRed,
            .accumulation_green_bits = hints.accumGreen,
            .accumulation_blue_bits = hints.accumBlue,
            .accumulation_alpha_bits = hints.accumAlpha,
            .srgb = hints.sRGB != 0,
            .robustness = hints.robustness != 0,
            .debug = hints.debug != 0,
            .no_error = hints.noError != 0,
            .release_behavior = @enumFromInt(hints.releaseBehavior),
            .profile = @enumFromInt(hints.profile),
            .major_version = hints.major,
            .minor_version = hints.minor,
            .renderer = @enumFromInt(hints.renderer),
        };
    }

    fn toRaw(
        hints: GraphicsHints,
        share_opengl: ?*raw.RGFW_glContext,
        share_egl: ?*raw.RGFW_eglContext,
    ) raw.RGFW_glHints {
        return .{
            .stencil = hints.stencil_bits,
            .samples = hints.samples,
            .stereo = @intFromBool(hints.stereo),
            .auxBuffers = hints.auxiliary_buffers,
            .doubleBuffer = @intFromBool(hints.double_buffer),
            .red = hints.red_bits,
            .green = hints.green_bits,
            .blue = hints.blue_bits,
            .alpha = hints.alpha_bits,
            .depth = hints.depth_bits,
            .accumRed = hints.accumulation_red_bits,
            .accumGreen = hints.accumulation_green_bits,
            .accumBlue = hints.accumulation_blue_bits,
            .accumAlpha = hints.accumulation_alpha_bits,
            .sRGB = @intFromBool(hints.srgb),
            .robustness = @intFromBool(hints.robustness),
            .debug = @intFromBool(hints.debug),
            .noError = @intFromBool(hints.no_error),
            .releaseBehavior = @intFromEnum(hints.release_behavior),
            .profile = @intFromEnum(hints.profile),
            .major = hints.major_version,
            .minor = hints.minor_version,
            .share = share_opengl,
            .shareEGL = share_egl,
            .renderer = @intFromEnum(hints.renderer),
        };
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW OpenGL/EGL support is disabled");
    }
};

pub const OpenGL = if (features.opengl) struct {
    const API = @This();

    pub const Error = error{ContextCreationFailed};

    /// A context owned by its Window. Never deinitialize or retain it past the Window.
    pub const Context = struct {
        handle: *raw.RGFW_glContext,

        pub fn rawHandle(graphics_context: @This()) *raw.RGFW_glContext {
            return graphics_context.handle;
        }

        pub fn nativeHandle(graphics_context: @This()) ?*anyopaque {
            return raw.RGFW_glContext_getSourceContext(graphics_context.handle);
        }
    };

    pub const ContextOptions = struct {
        hints: GraphicsHints = .{},
        share: ?API.Context = null,
    };

    pub fn createContext(
        window: *Window,
        options: ContextOptions,
    ) (Error || HandleError)!API.Context {
        const handle = try window.rawHandle();
        var hints = Graphics.toRaw(
            options.hints,
            if (options.share) |shared| shared.handle else null,
            null,
        );
        const context = raw.RGFW_window_createContext_OpenGL(handle, &hints) orelse {
            return error.ContextCreationFailed;
        };
        return .{ .handle = context };
    }

    /// Returns a context borrowed until its Window is deinitialized.
    pub fn getContext(window: *const Window) ?API.Context {
        const handle = window.handle orelse return null;
        const context_handle = raw.RGFW_window_getContext_OpenGL(handle) orelse return null;
        return .{ .handle = context_handle };
    }

    pub fn makeCurrent(window: ?*const Window) void {
        const handle = if (window) |value| value.handle else null;
        raw.RGFW_window_makeCurrentWindow_OpenGL(handle);
    }

    pub fn swapBuffers(window: *const Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapBuffers_OpenGL(handle);
    }

    pub fn swapInterval(window: *const Window, interval: i32) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapInterval_OpenGL(handle, interval);
    }

    pub fn load(comptime Function: type, name: [:0]const u8) Function {
        const function = raw.RGFW_getProcAddress_OpenGL(name.ptr) orelse return null;
        return @ptrCast(function);
    }

    pub fn extensionSupported(extension: []const u8) bool {
        return raw.RGFW_extensionSupported_OpenGL(extension.ptr, extension.len) != 0;
    }

    pub fn platformExtensionSupported(extension: []const u8) bool {
        return raw.RGFW_extensionSupportedPlatform_OpenGL(
            extension.ptr,
            extension.len,
        ) != 0;
    }

    pub fn currentNativeContext() ?*anyopaque {
        return raw.RGFW_getCurrentContext_OpenGL();
    }

    pub fn isCurrent(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_getCurrentWindow_OpenGL() == handle;
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW OpenGL support is disabled; build with -Dopengl=true");
    }
};

pub const EGL = if (features.egl) struct {
    const API = @This();

    pub const Error = error{ContextCreationFailed};

    /// A context owned by its Window. Never deinitialize or retain it past the Window.
    pub const Context = struct {
        handle: *raw.RGFW_eglContext,

        pub fn rawHandle(graphics_context: @This()) *raw.RGFW_eglContext {
            return graphics_context.handle;
        }

        pub fn nativeHandle(graphics_context: @This()) ?*anyopaque {
            return raw.RGFW_eglContext_getSourceContext(graphics_context.handle);
        }

        pub fn surfaceHandle(graphics_context: @This()) ?*anyopaque {
            return raw.RGFW_eglContext_getSurface(graphics_context.handle);
        }

        pub fn waylandWindowHandle(graphics_context: @This()) ?*anyopaque {
            const handle = raw.RGFW_eglContext_wlEGLWindow(graphics_context.handle) orelse {
                return null;
            };
            return @ptrCast(handle);
        }
    };

    pub const ContextOptions = struct {
        hints: GraphicsHints = .{},
        share: ?API.Context = null,
    };

    pub fn createContext(
        window: *Window,
        options: ContextOptions,
    ) (Error || HandleError)!API.Context {
        const handle = try window.rawHandle();
        var hints = Graphics.toRaw(
            options.hints,
            null,
            if (options.share) |shared| shared.handle else null,
        );
        const context_handle = raw.RGFW_window_createContext_EGL(handle, &hints) orelse {
            return error.ContextCreationFailed;
        };
        return .{ .handle = context_handle };
    }

    /// Returns a context borrowed until its Window is deinitialized.
    pub fn getContext(window: *const Window) ?API.Context {
        const handle = window.handle orelse return null;
        const context_handle = raw.RGFW_window_getContext_EGL(handle) orelse return null;
        return .{ .handle = context_handle };
    }

    pub fn makeCurrent(window: ?*const Window) void {
        const handle = if (window) |value| value.handle else null;
        raw.RGFW_window_makeCurrentWindow_EGL(handle);
    }

    pub fn swapBuffers(window: *const Window) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapBuffers_EGL(handle);
    }

    pub fn swapInterval(window: *const Window, interval: i32) void {
        const handle = window.handle orelse return;
        raw.RGFW_window_swapInterval_EGL(handle, interval);
    }

    pub fn load(comptime Function: type, name: [:0]const u8) Function {
        const function = raw.RGFW_getProcAddress_EGL(name.ptr) orelse return null;
        return @ptrCast(function);
    }

    pub fn extensionSupported(extension: []const u8) bool {
        return raw.RGFW_extensionSupported_EGL(extension.ptr, extension.len) != 0;
    }

    pub fn platformExtensionSupported(extension: []const u8) bool {
        return raw.RGFW_extensionSupportedPlatform_EGL(extension.ptr, extension.len) != 0;
    }

    pub fn displayHandle() ?*anyopaque {
        return raw.RGFW_getDisplay_EGL();
    }

    pub fn currentNativeContext() ?*anyopaque {
        return raw.RGFW_getCurrentContext_EGL();
    }

    pub fn isCurrent(window: *const Window) bool {
        const handle = window.handle orelse return false;
        return raw.RGFW_getCurrentWindow_EGL() == handle;
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW EGL support is disabled; build with -Degl=true");
    }
};

pub const DirectX = if (features.directx) struct {
    pub const Error = error{SwapChainCreationFailed};

    extern fn RGFW_window_createSwapChain_DirectX(
        window: *raw.RGFW_window,
        factory: *anyopaque,
        device: *anyopaque,
        swap_chain: *?*anyopaque,
    ) callconv(.c) i32;

    /// Creates an IDXGISwapChain while preserving the consumer package's COM type.
    pub fn createSwapChain(
        comptime SwapChain: type,
        window: *Window,
        factory: anytype,
        device: anytype,
    ) (Error || HandleError)!SwapChain {
        comptime requireNonOptionalPointer(SwapChain, "DirectX swap-chain type");
        const native_window = try window.rawHandle();
        var swap_chain: ?*anyopaque = null;
        const result = RGFW_window_createSwapChain_DirectX(
            native_window,
            eraseNonOptionalPointer(factory, "DirectX factory"),
            eraseNonOptionalPointer(device, "DirectX device"),
            &swap_chain,
        );
        if (result != 0) return error.SwapChainCreationFailed;
        return @ptrCast(swap_chain orelse return error.SwapChainCreationFailed);
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW DirectX support is disabled; build for Windows with -Ddirectx=true");
    }
};

pub const WebGPU = if (features.webgpu) struct {
    pub const Instance = raw.WGPUInstance;
    pub const Surface = raw.WGPUSurface;
    pub const Error = error{SurfaceCreationFailed};

    pub fn createSurface(window: *const Window, instance: Instance) Error!@This().Surface {
        const native_window = window.handle orelse return error.SurfaceCreationFailed;
        const surface = raw.RGFW_window_createSurface_WebGPU(native_window, instance);
        return surface orelse error.SurfaceCreationFailed;
    }

    /// Creates a surface while preserving ABI-compatible handles from a WebGPU package.
    pub fn createSurfaceAs(
        comptime ForeignSurface: type,
        window: *const Window,
        foreign_instance: anytype,
    ) Error!ForeignSurface {
        const ForeignInstance = @TypeOf(foreign_instance);
        comptime {
            requireNullablePointerHandle(ForeignInstance, "foreign WebGPU instance");
            requireNullablePointerHandle(ForeignSurface, "foreign WebGPU surface");
            if (@sizeOf(ForeignInstance) != @sizeOf(Instance)) {
                @compileError("foreign WebGPU instance has an incompatible ABI size");
            }
            if (@sizeOf(ForeignSurface) != @sizeOf(@This().Surface)) {
                @compileError("foreign WebGPU surface has an incompatible ABI size");
            }
        }
        const instance: Instance = @bitCast(foreign_instance);
        const surface = try createSurface(window, instance);
        return @bitCast(surface);
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW WebGPU support is disabled; build with -Dwebgpu=true");
    }
};

pub const KeyModifiers = struct {
    caps_lock: bool = false,
    num_lock: bool = false,
    control: bool = false,
    alt: bool = false,
    shift: bool = false,
    super: bool = false,
    scroll_lock: bool = false,

    fn fromRaw(value: raw.RGFW_keymod) KeyModifiers {
        return .{
            .caps_lock = value & raw.RGFW_modCapsLock != 0,
            .num_lock = value & raw.RGFW_modNumLock != 0,
            .control = value & raw.RGFW_modControl != 0,
            .alt = value & raw.RGFW_modAlt != 0,
            .shift = value & raw.RGFW_modShift != 0,
            .super = value & raw.RGFW_modSuper != 0,
            .scroll_lock = value & raw.RGFW_modScrollLock != 0,
        };
    }
};

pub const KeyEvent = struct {
    key: Key,
    repeated: bool,
    modifiers: KeyModifiers,
};

pub const MouseMotionEvent = struct {
    position: Point,
    in_window: bool,
};

pub const DataTransferKind = enum(raw.RGFW_dataTransferType) {
    none = raw.RGFW_dataNone,
    text = raw.RGFW_dataText,
    file = raw.RGFW_dataFile,
    url = raw.RGFW_dataURL,
    image = raw.RGFW_dataImage,
    unknown = raw.RGFW_dataUnknown,
    _,
};

pub const DragAction = enum(raw.RGFW_dndActionType) {
    none = raw.RGFW_dndActionNone,
    enter = raw.RGFW_dndActionEnter,
    move = raw.RGFW_dndActionMove,
    exit = raw.RGFW_dndActionExit,
    _,
};

pub const DataDrop = struct {
    first: ?*const raw.RGFW_dataDropNode,

    pub fn iterator(drop: DataDrop) DataDropIterator {
        return .{ .next_node = drop.first };
    }
};

pub const DataDropItem = struct {
    bytes: []const u8,
    kind: DataTransferKind,
};

pub const DataDropIterator = struct {
    next_node: ?*const raw.RGFW_dataDropNode,

    pub fn next(iterator: *DataDropIterator) ?DataDropItem {
        const node = iterator.next_node orelse return null;
        iterator.next_node = node.next;
        const bytes = if (node.data) |data| data[0..node.length] else &.{};
        return .{
            .bytes = bytes,
            .kind = @enumFromInt(node.type),
        };
    }
};

pub const DataDragEvent = struct {
    position: Point,
    action: DragAction,
    data_kind: DataTransferKind,
};

pub const UnknownEvent = struct {
    kind: EventKind,
    raw_value: raw.RGFW_event,
};

/// A lossless, typed view of an RGFW event. Unknown future event kinds retain
/// the complete raw value in the `.unknown` case.
pub const EventPayload = union(enum) {
    none,
    key_pressed: KeyEvent,
    key_released: KeyEvent,
    key_character: u32,
    mouse_button_pressed: MouseButton,
    mouse_button_released: MouseButton,
    mouse_scroll: Vector,
    mouse_motion: MouseMotionEvent,
    mouse_raw_motion: Vector,
    mouse_enter,
    mouse_leave,
    window_moved: Point,
    window_resized: Size,
    window_focus_in,
    window_focus_out,
    window_refresh: Rect,
    window_close,
    window_maximized,
    window_minimized,
    window_restored,
    data_drop: DataDrop,
    data_drag: DataDragEvent,
    scale_updated: Vector,
    monitor_connected: ?MonitorSnapshot,
    monitor_disconnected: ?MonitorSnapshot,
    unknown: UnknownEvent,
};

pub const Event = struct {
    raw_value: raw.RGFW_event,
    monitor_snapshot: ?MonitorSnapshot = null,

    pub fn fromRaw(raw_value: raw.RGFW_event) Event {
        var event: Event = .{ .raw_value = raw_value };
        if (raw_value.type == raw.RGFW_monitorConnected or
            raw_value.type == raw.RGFW_monitorDisconnected)
        {
            if (raw_value.monitor.monitor) |monitor| {
                event.monitor_snapshot = .fromRaw(monitor);
            }
        }
        return event;
    }

    pub fn kind(event: *const Event) EventKind {
        return @enumFromInt(event.raw_value.type);
    }

    pub fn rawEvent(event: *const Event) *const raw.RGFW_event {
        return &event.raw_value;
    }

    /// Returns key data for `.key_pressed` and `.key_released` events.
    pub fn keyEvent(event: *const Event) ?KeyEvent {
        return switch (event.payload()) {
            .key_pressed, .key_released => |value| value,
            else => null,
        };
    }

    /// Returns the button for `.mouse_button_pressed` and
    /// `.mouse_button_released` events.
    pub fn mouseButton(event: *const Event) ?MouseButton {
        return switch (event.payload()) {
            .mouse_button_pressed, .mouse_button_released => |value| value,
            else => null,
        };
    }

    /// Returns the delta for a `.mouse_scroll` event.
    pub fn scrollDelta(event: *const Event) ?Vector {
        return switch (event.payload()) {
            .mouse_scroll => |value| value,
            else => null,
        };
    }

    /// Returns the delta for a `.mouse_raw_motion` event.
    pub fn rawMouseDelta(event: *const Event) ?Vector {
        return switch (event.payload()) {
            .mouse_raw_motion => |value| value,
            else => null,
        };
    }

    /// Returns the pointer position for a `.mouse_motion` event.
    pub fn mousePosition(event: *const Event) ?Point {
        return switch (event.payload()) {
            .mouse_motion => |value| value.position,
            else => null,
        };
    }

    /// Returns whether the pointer is inside the window for a `.mouse_motion` event.
    pub fn mouseInWindow(event: *const Event) ?bool {
        return switch (event.payload()) {
            .mouse_motion => |value| value.in_window,
            else => null,
        };
    }

    /// Returns `true` for `.window_focus_in`, `false` for
    /// `.window_focus_out`, and `null` for every other event kind.
    pub fn focusState(event: *const Event) ?bool {
        return switch (event.kind()) {
            .window_focus_in => true,
            .window_focus_out => false,
            else => null,
        };
    }

    /// Returns the new position for a `.window_moved` event.
    pub fn windowPosition(event: *const Event) ?Point {
        return switch (event.payload()) {
            .window_moved => |value| value,
            else => null,
        };
    }

    /// Returns the new size for a `.window_resized` event.
    pub fn windowSize(event: *const Event) ?Size {
        return switch (event.payload()) {
            .window_resized => |value| value,
            else => null,
        };
    }

    /// Returns the damaged rectangle for a `.window_refresh` event.
    pub fn refreshRect(event: *const Event) ?Rect {
        return switch (event.payload()) {
            .window_refresh => |value| value,
            else => null,
        };
    }

    pub fn payload(event: *const Event) EventPayload {
        return switch (event.kind()) {
            .none => .none,
            .key_pressed => .{ .key_pressed = keyPayload(event.raw_value.key) },
            .key_released => .{ .key_released = keyPayload(event.raw_value.key) },
            .key_character => .{ .key_character = event.raw_value.keyChar.value },
            .mouse_button_pressed => .{
                .mouse_button_pressed = @enumFromInt(event.raw_value.button.value),
            },
            .mouse_button_released => .{
                .mouse_button_released = @enumFromInt(event.raw_value.button.value),
            },
            .mouse_scroll => .{ .mouse_scroll = .{
                .x = event.raw_value.delta.x,
                .y = event.raw_value.delta.y,
            } },
            .mouse_motion => .{ .mouse_motion = .{
                .position = .{
                    .x = event.raw_value.mouse.x,
                    .y = event.raw_value.mouse.y,
                },
                .in_window = event.raw_value.mouse.inWindow != 0,
            } },
            .mouse_raw_motion => .{ .mouse_raw_motion = .{
                .x = event.raw_value.delta.x,
                .y = event.raw_value.delta.y,
            } },
            .mouse_enter => .mouse_enter,
            .mouse_leave => .mouse_leave,
            .window_moved => .{ .window_moved = .{
                .x = event.raw_value.update.x,
                .y = event.raw_value.update.y,
            } },
            .window_resized => .{ .window_resized = .{
                .width = event.raw_value.update.w,
                .height = event.raw_value.update.h,
            } },
            .window_focus_in => .window_focus_in,
            .window_focus_out => .window_focus_out,
            .window_refresh => .{ .window_refresh = .{
                .x = event.raw_value.update.x,
                .y = event.raw_value.update.y,
                .width = event.raw_value.update.w,
                .height = event.raw_value.update.h,
            } },
            .window_close => .window_close,
            .window_maximized => .window_maximized,
            .window_minimized => .window_minimized,
            .window_restored => .window_restored,
            .data_drop => .{ .data_drop = .{ .first = event.raw_value.drop.value } },
            .data_drag => .{ .data_drag = .{
                .position = .{
                    .x = event.raw_value.drag.x,
                    .y = event.raw_value.drag.y,
                },
                .action = @enumFromInt(event.raw_value.drag.action),
                .data_kind = @enumFromInt(event.raw_value.drag.dataType),
            } },
            .scale_updated => .{ .scale_updated = .{
                .x = event.raw_value.scale.x,
                .y = event.raw_value.scale.y,
            } },
            .monitor_connected => .{
                .monitor_connected = event.monitor_snapshot,
            },
            .monitor_disconnected => .{
                .monitor_disconnected = event.monitor_snapshot,
            },
            else => .{ .unknown = .{
                .kind = event.kind(),
                .raw_value = event.raw_value,
            } },
        };
    }

    fn keyPayload(value: raw.RGFW_keyEvent) KeyEvent {
        return .{
            .key = @enumFromInt(value.value),
            .repeated = value.repeat != 0,
            .modifiers = .fromRaw(value.mod),
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

fn EventDescriptor(comptime event_kind: EventKind, comptime PayloadType: type) type {
    return struct {
        pub const kind = event_kind;
        pub const Payload = PayloadType;
    };
}

/// Typed callback descriptors accepted by `Context.on` and `Context.onWithContext`.
pub const callback = struct {
    pub const key_pressed = EventDescriptor(.key_pressed, KeyEvent){};
    pub const key_released = EventDescriptor(.key_released, KeyEvent){};
    pub const key_character = EventDescriptor(.key_character, u32){};
    pub const mouse_button_pressed = EventDescriptor(.mouse_button_pressed, MouseButton){};
    pub const mouse_button_released = EventDescriptor(.mouse_button_released, MouseButton){};
    pub const mouse_scroll = EventDescriptor(.mouse_scroll, Vector){};
    pub const mouse_motion = EventDescriptor(.mouse_motion, MouseMotionEvent){};
    pub const mouse_raw_motion = EventDescriptor(.mouse_raw_motion, Vector){};
    pub const mouse_enter = EventDescriptor(.mouse_enter, void){};
    pub const mouse_leave = EventDescriptor(.mouse_leave, void){};
    pub const window_moved = EventDescriptor(.window_moved, Point){};
    pub const window_resized = EventDescriptor(.window_resized, Size){};
    pub const window_focus_in = EventDescriptor(.window_focus_in, void){};
    pub const window_focus_out = EventDescriptor(.window_focus_out, void){};
    pub const window_refresh = EventDescriptor(.window_refresh, Rect){};
    pub const window_close = EventDescriptor(.window_close, void){};
    pub const window_maximized = EventDescriptor(.window_maximized, void){};
    pub const window_minimized = EventDescriptor(.window_minimized, void){};
    pub const window_restored = EventDescriptor(.window_restored, void){};
    pub const data_drop = EventDescriptor(.data_drop, DataDrop){};
    pub const data_drag = EventDescriptor(.data_drag, DataDragEvent){};
    pub const scale_updated = EventDescriptor(.scale_updated, Vector){};
    pub const monitor_connected = EventDescriptor(.monitor_connected, ?MonitorSnapshot){};
    pub const monitor_disconnected = EventDescriptor(.monitor_disconnected, ?MonitorSnapshot){};
};

const EventHandlerSlot = struct {
    context: ?*anyopaque,
    dispatch: *const fn (?*anyopaque, *const Event) void,
    generation: u64,
};

var event_handler_slots: [raw.RGFW_eventCount]?EventHandlerSlot =
    @splat(@as(?EventHandlerSlot, null));
var event_handler_generation: u64 = 0;

/// An owning callback installation. Do not copy; deinit once in reverse installation order.
/// deinit is idempotent and must run before Context.deinit.
pub const EventSubscription = struct {
    kind: EventKind,
    previous_callback: raw.RGFW_genericFunc,
    previous_slot: ?EventHandlerSlot,
    generation: u64,
    active: bool = true,

    fn install(
        comptime descriptor: anytype,
        handler_context: anytype,
        comptime handler: anytype,
    ) EventSubscription {
        const Descriptor = @TypeOf(descriptor);
        if (!@hasDecl(Descriptor, "kind") or !@hasDecl(Descriptor, "Payload")) {
            @compileError("expected an rgfw.callback event descriptor");
        }
        const Payload = Descriptor.Payload;
        const ContextPointer = @TypeOf(handler_context);
        const Adapter = if (ContextPointer == @TypeOf(null)) struct {
            fn dispatch(_: ?*anyopaque, incoming: *const Event) void {
                if (Payload == void) {
                    handler();
                } else {
                    handler(eventPayloadAs(Descriptor.kind, Payload, incoming));
                }
            }
        } else struct {
            fn dispatch(erased: ?*anyopaque, incoming: *const Event) void {
                const typed_context: ContextPointer = @ptrCast(@alignCast(erased.?));
                if (Payload == void) {
                    handler(typed_context);
                } else {
                    handler(typed_context, eventPayloadAs(Descriptor.kind, Payload, incoming));
                }
            }
        };

        comptime validateEventHandler(descriptor, ContextPointer, handler);
        event_handler_generation = std.math.add(
            u64,
            event_handler_generation,
            1,
        ) catch @panic("RGFW event handler generation overflow");
        const index = eventIndex(Descriptor.kind);
        const previous_slot = event_handler_slots[index];
        event_handler_slots[index] = .{
            .context = if (ContextPointer == @TypeOf(null)) null else @ptrCast(handler_context),
            .dispatch = Adapter.dispatch,
            .generation = event_handler_generation,
        };
        const previous_callback = raw.RGFW_setEventCallback(
            @intFromEnum(Descriptor.kind),
            eventCallback,
        );
        return .{
            .kind = Descriptor.kind,
            .previous_callback = previous_callback,
            .previous_slot = previous_slot,
            .generation = event_handler_generation,
        };
    }

    pub fn deinit(subscription: *EventSubscription) void {
        if (!subscription.active) return;
        const index = eventIndex(subscription.kind);
        const current = event_handler_slots[index] orelse
            @panic("RGFW event handler was removed out of order");
        if (current.generation != subscription.generation) {
            @panic("RGFW event handler was removed out of order");
        }
        _ = raw.RGFW_setEventCallback(
            @intFromEnum(subscription.kind),
            subscription.previous_callback,
        );
        event_handler_slots[index] = subscription.previous_slot;
        subscription.active = false;
    }
};

fn eventCallback(incoming: [*c]const raw.RGFW_event) callconv(.c) void {
    if (incoming == null) return;
    const raw_kind = incoming.*.type;
    if (raw_kind == raw.RGFW_eventNone or raw_kind >= raw.RGFW_eventCount) return;
    const slot = event_handler_slots[@intCast(raw_kind)] orelse return;
    const wrapped = Event.fromRaw(incoming.*);
    slot.dispatch(slot.context, &wrapped);
}

fn eventIndex(kind: EventKind) usize {
    const index: usize = @intFromEnum(kind);
    std.debug.assert(index > raw.RGFW_eventNone);
    std.debug.assert(index < raw.RGFW_eventCount);
    return index;
}

fn validateEventHandler(
    comptime descriptor: anytype,
    comptime ContextPointer: type,
    comptime handler: anytype,
) void {
    const Payload = @TypeOf(descriptor).Payload;
    const Expected = if (ContextPointer == @TypeOf(null))
        if (Payload == void) fn () void else fn (Payload) void
    else blk: {
        requireContextPointer(ContextPointer, "event handler context");
        break :blk if (Payload == void)
            fn (ContextPointer) void
        else
            fn (ContextPointer, Payload) void;
    };
    if (@TypeOf(handler) != Expected) {
        @compileError("event handler must have type `" ++ @typeName(Expected) ++ "`");
    }
}

fn requireContextPointer(comptime ContextPointer: type, comptime role: []const u8) void {
    const pointer = switch (@typeInfo(ContextPointer)) {
        .pointer => |pointer| pointer,
        else => @compileError(role ++ " must be a non-optional single-item pointer"),
    };
    if (pointer.size != .one or pointer.is_allowzero) {
        @compileError(role ++ " must be a non-optional single-item pointer");
    }
}

fn requireNonOptionalPointer(comptime Pointer: type, comptime role: []const u8) void {
    const pointer = switch (@typeInfo(Pointer)) {
        .pointer => |pointer| pointer,
        else => @compileError(role ++ " must be a non-optional pointer"),
    };
    if (pointer.size != .one and pointer.size != .c) {
        @compileError(role ++ " must be a single-item or C pointer");
    }
}

fn eraseNonOptionalPointer(value: anytype, comptime role: []const u8) *anyopaque {
    comptime requireNonOptionalPointer(@TypeOf(value), role);
    return @ptrCast(@constCast(value));
}

fn requireNullablePointerHandle(comptime Handle: type, comptime role: []const u8) void {
    const child = switch (@typeInfo(Handle)) {
        .optional => |optional| optional.child,
        else => @compileError(role ++ " must be an optional pointer handle"),
    };
    requireNonOptionalPointer(child, role);
}

fn eventPayloadAs(
    comptime kind: EventKind,
    comptime Payload: type,
    incoming: *const Event,
) Payload {
    const payload = incoming.payload();
    return switch (kind) {
        .key_pressed => payload.key_pressed,
        .key_released => payload.key_released,
        .key_character => payload.key_character,
        .mouse_button_pressed => payload.mouse_button_pressed,
        .mouse_button_released => payload.mouse_button_released,
        .mouse_scroll => payload.mouse_scroll,
        .mouse_motion => payload.mouse_motion,
        .mouse_raw_motion => payload.mouse_raw_motion,
        .window_moved => payload.window_moved,
        .window_resized => payload.window_resized,
        .window_refresh => payload.window_refresh,
        .data_drop => payload.data_drop,
        .data_drag => payload.data_drag,
        .scale_updated => payload.scale_updated,
        .monitor_connected => payload.monitor_connected,
        .monitor_disconnected => payload.monitor_disconnected,
        .mouse_enter,
        .mouse_leave,
        .window_focus_in,
        .window_focus_out,
        .window_close,
        .window_maximized,
        .window_minimized,
        .window_restored,
        => @compileError("void event payloads are dispatched without a payload argument"),
        else => @compileError("event descriptor has no typed payload mapping"),
    };
}

pub const Vulkan = if (features.vulkan) struct {
    pub const Instance = raw.VkInstance;
    pub const PhysicalDevice = raw.VkPhysicalDevice;
    pub const Surface = raw.VkSurfaceKHR;
    pub const Result = raw.VkResult;

    pub const SurfaceError = error{
        InvalidInstance,
        SurfaceCreationFailed,
        SurfaceOwnershipUnavailable,
    };

    const HandleRepresentation = enum {
        opaque_pointer,
        unsigned_integer,
    };

    pub const ExtensionIterator = struct {
        pointers: []const [*:0]const u8,
        index: usize = 0,

        pub fn next(iterator: *ExtensionIterator) ?[:0]const u8 {
            if (iterator.index == iterator.pointers.len) return null;
            const pointer = iterator.pointers[iterator.index];
            iterator.index += 1;
            return std.mem.span(pointer);
        }

        pub fn count(iterator: ExtensionIterator) usize {
            return iterator.pointers.len;
        }
    };

    /// Returns a zero-allocation iterator of Zig sentinel slices.
    pub fn requiredInstanceExtensions() ExtensionIterator {
        return .{ .pointers = requiredInstanceExtensionPointers() };
    }

    /// Exposes RGFW's original C pointer array for low-level consumers.
    pub fn requiredInstanceExtensionPointers() []const [*:0]const u8 {
        var count: usize = 0;
        const extension_ptrs = raw.RGFW_getRequiredInstanceExtensions_Vulkan(&count);
        if (extension_ptrs == null) return &.{};
        const sentinel_ptrs: [*]const [*:0]const u8 = @ptrCast(extension_ptrs);
        return sentinel_ptrs[0..count];
    }

    /// Appends RGFW's borrowed names to an extension set such as vk-zig's ExtensionSet.
    pub fn appendRequiredInstanceExtensions(extension_set: anytype) @TypeOf(
        extension_set.appendPointerNames(requiredInstanceExtensionPointers()),
    ) {
        return extension_set.appendPointerNames(requiredInstanceExtensionPointers());
    }

    pub fn createSurface(
        window: *const Window,
        instance: Instance,
    ) SurfaceError!@This().Surface {
        const handle = window.handle orelse return error.SurfaceCreationFailed;
        if (handleIsNull(instance)) return error.InvalidInstance;

        var surface: @This().Surface = undefined;
        const result = raw.RGFW_window_createSurface_Vulkan(handle, instance, &surface);
        if (result != raw.VK_SUCCESS) return error.SurfaceCreationFailed;
        if (handleIsNull(surface)) return error.SurfaceCreationFailed;
        return surface;
    }

    /// Creates a surface using ABI-compatible Vulkan handle types from another Zig package.
    /// The reinterpretation does not retain, release, or transfer ownership of either handle.
    /// The caller owns the newly created surface and must destroy it with its Vulkan instance.
    pub fn createSurfaceAs(
        comptime ForeignSurface: type,
        window: *const Window,
        foreign_instance: anytype,
    ) SurfaceError!ForeignSurface {
        const ForeignInstance = @TypeOf(foreign_instance);
        comptime {
            requireCompatibleHandle(ForeignInstance, Instance, "foreign Vulkan instance");
            requireCompatibleHandle(ForeignSurface, @This().Surface, "foreign Vulkan surface");
        }

        const instance: Instance = castCompatibleHandle(Instance, foreign_instance);
        const surface = try createSurface(window, instance);
        return castCompatibleHandle(ForeignSurface, surface);
    }

    /// Creates an RGFW surface and hands ownership directly to a foreign instance wrapper.
    /// The wrapper must provide `rawHandle` and `adoptSurface` methods, as vk-zig does.
    pub fn createOwnedSurfaceAs(
        comptime ForeignSurface: type,
        window: *const Window,
        foreign_instance_owner: anytype,
    ) OwnedSurfaceResult(@TypeOf(foreign_instance_owner)) {
        const foreign_instance = try foreign_instance_owner.rawHandle();
        const instance: Instance = castCompatibleHandle(Instance, foreign_instance);
        const destroy_surface = loadDestroySurface(instance) orelse
            return error.SurfaceOwnershipUnavailable;
        const native_surface = try createSurface(window, instance);
        const surface = castCompatibleHandle(ForeignSurface, native_surface);
        return foreign_instance_owner.adoptSurface(surface, null) catch |adopt_error| {
            destroy_surface(instance, native_surface, null);
            return adopt_error;
        };
    }

    /// Infers the foreign surface handle from the owner's adoptSurface method.
    pub fn createOwnedSurface(
        window: *const Window,
        foreign_instance_owner: anytype,
    ) OwnedSurfaceResult(@TypeOf(foreign_instance_owner)) {
        const ForeignSurface = AdoptedSurfaceHandle(@TypeOf(foreign_instance_owner));
        return createOwnedSurfaceAs(
            ForeignSurface,
            window,
            foreign_instance_owner,
        );
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

    pub fn presentationSupportedAs(
        foreign_instance: anytype,
        foreign_physical_device: anytype,
        queue_family_index: u32,
    ) bool {
        const instance = castCompatibleHandle(Instance, foreign_instance);
        const physical_device = castCompatibleHandle(
            PhysicalDevice,
            foreign_physical_device,
        );
        return presentationSupported(instance, physical_device, queue_family_index);
    }

    pub fn load(
        comptime Function: type,
        instance: Instance,
        name: [:0]const u8,
    ) Function {
        const function = raw.RGFW_getInstanceProcAddress_Vulkan(
            instance,
            name.ptr,
        ) orelse return null;
        return @ptrCast(function);
    }

    fn handleRepresentation(comptime Handle: type) ?HandleRepresentation {
        const Payload = switch (@typeInfo(Handle)) {
            .optional => |optional| optional.child,
            else => Handle,
        };

        return switch (@typeInfo(Payload)) {
            .pointer => |pointer| if (pointer.size == .one and
                @typeInfo(pointer.child) == .@"opaque")
                .opaque_pointer
            else
                null,
            .int => |integer| if (integer.signedness == .unsigned)
                .unsigned_integer
            else
                null,
            else => null,
        };
    }

    fn handlesAreCompatible(comptime Foreign: type, comptime Native: type) bool {
        const foreign_representation = handleRepresentation(Foreign) orelse return false;
        const native_representation = handleRepresentation(Native) orelse return false;
        if (foreign_representation != native_representation) return false;
        return @sizeOf(Foreign) == @sizeOf(Native) and
            @alignOf(Foreign) == @alignOf(Native);
    }

    fn requireCompatibleHandle(
        comptime Foreign: type,
        comptime Native: type,
        comptime role: []const u8,
    ) void {
        if (handleRepresentation(Foreign) == null) {
            @compileError(role ++ " type `" ++ @typeName(Foreign) ++
                "` must be an opaque single-item pointer or unsigned integer Vulkan handle");
        }
        if (!handlesAreCompatible(Foreign, Native)) {
            @compileError(role ++ " type `" ++ @typeName(Foreign) ++
                "` is not ABI-compatible with `" ++ @typeName(Native) ++ "`");
        }
    }

    fn castCompatibleHandle(comptime Target: type, source: anytype) Target {
        const Source = @TypeOf(source);
        comptime requireCompatibleHandle(Source, Target, "Vulkan handle");

        if (comptime handleRepresentation(Target).? == .opaque_pointer) {
            return switch (@typeInfo(Source)) {
                .optional => if (source) |pointer|
                    @ptrCast(pointer)
                else switch (@typeInfo(Target)) {
                    .optional => null,
                    else => unreachable,
                },
                else => @ptrCast(source),
            };
        }
        return @bitCast(source);
    }

    fn handleIsNull(handle: anytype) bool {
        return switch (@typeInfo(@TypeOf(handle))) {
            .optional => handle == null,
            .int => handle == 0,
            .pointer => false,
            else => unreachable,
        };
    }

    const DestroySurfaceFunction = @typeInfo(raw.PFN_vkDestroySurfaceKHR).optional.child;

    fn loadDestroySurface(instance: Instance) ?DestroySurfaceFunction {
        const generic = raw.RGFW_getInstanceProcAddress_Vulkan(
            instance,
            "vkDestroySurfaceKHR",
        ) orelse return null;
        return @ptrCast(generic);
    }

    fn OwnedSurfaceResult(comptime OwnerPointer: type) type {
        const Owner = switch (@typeInfo(OwnerPointer)) {
            .pointer => |pointer| if (pointer.size == .one)
                pointer.child
            else
                @compileError("foreign Vulkan instance owner must be a single-item pointer"),
            else => @compileError("foreign Vulkan instance owner must be a single-item pointer"),
        };
        if (!@hasDecl(Owner, "rawHandle") or !@hasDecl(Owner, "adoptSurface")) {
            @compileError("foreign Vulkan instance owner must provide rawHandle and adoptSurface methods");
        }
        const RawResult = @typeInfo(@TypeOf(Owner.rawHandle)).@"fn".return_type.?;
        const AdoptResult = @typeInfo(@TypeOf(Owner.adoptSurface)).@"fn".return_type.?;
        const raw_error_union = switch (@typeInfo(RawResult)) {
            .error_union => |error_union| error_union,
            else => @compileError("foreign Vulkan rawHandle method must return an error union"),
        };
        const adopt_error_union = switch (@typeInfo(AdoptResult)) {
            .error_union => |error_union| error_union,
            else => @compileError("foreign Vulkan adoptSurface method must return an error union"),
        };
        return (SurfaceError || raw_error_union.error_set || adopt_error_union.error_set)!adopt_error_union.payload;
    }

    fn AdoptedSurfaceHandle(comptime OwnerPointer: type) type {
        const Owner = switch (@typeInfo(OwnerPointer)) {
            .pointer => |pointer| if (pointer.size == .one)
                pointer.child
            else
                @compileError("foreign Vulkan instance owner must be a single-item pointer"),
            else => @compileError("foreign Vulkan instance owner must be a single-item pointer"),
        };
        if (!@hasDecl(Owner, "adoptSurface")) {
            @compileError("foreign Vulkan instance owner must provide an adoptSurface method");
        }
        const function = @typeInfo(@TypeOf(Owner.adoptSurface)).@"fn";
        if (function.params.len < 2) {
            @compileError("foreign Vulkan adoptSurface method must accept a surface handle");
        }
        return function.params[1].type orelse {
            @compileError("foreign Vulkan adoptSurface surface parameter must have a concrete type");
        };
    }
} else struct {
    pub fn requireEnabled() void {
        @compileError("RGFW Vulkan support is disabled; pass `.vulkan = true` to the dependency");
    }
};

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

test "Vulkan foreign handles preserve their ABI representation" {
    if (!features.vulkan) return;

    const ForeignInstanceOpaque = opaque {};
    const ForeignSurfaceOpaque = opaque {};
    const ForeignInstance = ?*ForeignInstanceOpaque;
    const ForeignSurface = ?*ForeignSurfaceOpaque;
    const ForeignNonNullInstance = *ForeignInstanceOpaque;

    try std.testing.expect(Vulkan.handlesAreCompatible(ForeignInstance, Vulkan.Instance));
    try std.testing.expect(Vulkan.handlesAreCompatible(ForeignSurface, Vulkan.Surface));
    try std.testing.expect(Vulkan.handlesAreCompatible(ForeignNonNullInstance, Vulkan.Instance));
    try std.testing.expect(!Vulkan.handlesAreCompatible(u32, Vulkan.Instance));
    try std.testing.expect(!Vulkan.handlesAreCompatible(?*u8, Vulkan.Instance));

    const foreign_instance: ForeignInstance = @ptrFromInt(0x1000);
    const native_instance = Vulkan.castCompatibleHandle(Vulkan.Instance, foreign_instance);
    const instance_round_trip = Vulkan.castCompatibleHandle(ForeignInstance, native_instance);
    try std.testing.expectEqual(
        @intFromPtr(foreign_instance.?),
        @intFromPtr(instance_round_trip.?),
    );

    const foreign_non_null_instance: ForeignNonNullInstance = @ptrFromInt(0x1800);
    const native_non_null_instance = Vulkan.castCompatibleHandle(
        Vulkan.Instance,
        foreign_non_null_instance,
    );
    try std.testing.expectEqual(
        @intFromPtr(foreign_non_null_instance),
        @intFromPtr(native_non_null_instance),
    );

    const native_surface: Vulkan.Surface = @ptrFromInt(0x2000);
    const foreign_surface = Vulkan.castCompatibleHandle(ForeignSurface, native_surface);
    const surface_round_trip = Vulkan.castCompatibleHandle(Vulkan.Surface, foreign_surface);
    try std.testing.expectEqual(
        @intFromPtr(native_surface.?),
        @intFromPtr(surface_round_trip.?),
    );
}

test "Vulkan owned-surface API infers a foreign surface parameter" {
    if (!features.vulkan) return;

    const ForeignSurfaceOpaque = opaque {};
    const ForeignSurface = ?*ForeignSurfaceOpaque;
    const Owner = struct {
        fn adoptSurface(_: *@This(), _: ForeignSurface, _: ?*anyopaque) error{AdoptionFailed}!u8 {
            return 1;
        }
    };
    try std.testing.expect(Vulkan.AdoptedSurfaceHandle(*Owner) == ForeignSurface);
}

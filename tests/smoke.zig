const std = @import("std");
const builtin = @import("builtin");
const foreign_vulkan = @import("foreign_vulkan_handles");
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
    try std.testing.expectEqual(raw_flags, rgfw.WindowFlags.fromRaw(raw_flags).toRaw());
}

test "image validation rejects invalid dimensions and short storage" {
    var pixels: [12]u8 = undefined;
    try std.testing.expectError(
        error.InvalidDimensions,
        rgfw.Image.init(&pixels, 0, 1, .rgba8),
    );
    try std.testing.expectError(
        error.BufferTooSmall,
        rgfw.Image.init(&pixels, 2, 2, .rgba8),
    );
    const image = try rgfw.Image.init(&pixels, 2, 2, .rgb8);
    try std.testing.expectEqual(@as(usize, 12), try image.requiredBytes());
}

test "cursor and icon enums cover RGFW constants" {
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_mouseIcon, rgfw.raw.RGFW_mouseResizeNWSE),
        @intFromEnum(rgfw.Cursor.resize_northwest_southeast),
    );
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_icon, rgfw.raw.RGFW_iconBoth),
        @intFromEnum(rgfw.IconTarget.both),
    );
}

test "owning wrappers are safe to deinitialize repeatedly" {
    var cursor: rgfw.CustomCursor = .{ .handle = null };
    cursor.deinit();
    cursor.deinit();

    var surface: rgfw.Surface = .{ .handle = null };
    surface.deinit();
    surface.deinit();
    var closed_window: rgfw.Window = .{ .handle = null };
    try std.testing.expectError(error.InactiveObject, surface.blit(&closed_window));

    var ramp: rgfw.OwnedGammaRamp = .{ .storage = &.{}, .count = 0 };
    ramp.deinit(std.testing.allocator);
    ramp.deinit(std.testing.allocator);
}

test "event masks and waits round trip without magic integers" {
    inline for (@typeInfo(rgfw.EventMask).@"struct".fields) |field| {
        var mask: rgfw.EventMask = .{};
        @field(mask, field.name) = true;
        try std.testing.expectEqual(mask.toRaw(), rgfw.EventMask.fromRaw(mask.toRaw()).toRaw());
    }
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_eventFlag, rgfw.raw.RGFW_allEventFlags),
        rgfw.EventMask.all.toRaw(),
    );
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_eventWait, 25),
        (rgfw.EventWait{ .milliseconds = 25 }).toRaw(),
    );
}

test "monitor mode request groups map to RGFW flags" {
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_modeRequest, rgfw.raw.RGFW_monitorAll),
        rgfw.ModeRequest.all.toRaw(),
    );
}

test "custom allocator hooks route RGFW allocation pairs" {
    if (!rgfw.features.custom_allocator) return;

    var storage: [1024]u8 align(64) = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    var hooks = rgfw.AllocatorHooks.init(fixed.allocator());
    hooks.install();
    defer rgfw.AllocatorHooks.uninstall();

    const pointer = rgfw.raw.RGFW_alloc(64) orelse return error.OutOfMemory;
    try std.testing.expect(fixed.end_index > 0);
    rgfw.raw.RGFW_free(pointer);
    try std.testing.expectEqual(@as(usize, 0), fixed.end_index);
}

test "idiomatic window event helpers are available" {
    try std.testing.expect(@hasDecl(rgfw.Window, "isOpen"));
    try std.testing.expect(@hasDecl(rgfw.Window, "nextQueuedEvent"));
    try std.testing.expect(@hasDecl(rgfw.Window, "nextEvent"));
    try std.testing.expect(@hasDecl(rgfw.Window, "pollEvent"));
    try std.testing.expect(@hasDecl(rgfw.Window, "events"));
    try std.testing.expect(@hasDecl(rgfw.Window, "pumpEvents"));
    try std.testing.expect(@hasDecl(rgfw.Window, "discardEvents"));
}

test "checked handles report inactive wrapper objects" {
    var window: rgfw.Window = .{ .handle = null };
    try std.testing.expectError(error.InactiveObject, window.rawHandle());
    try std.testing.expectError(error.InactiveObject, window.nativeHandle());

    var surface: rgfw.Surface = .{ .handle = null };
    try std.testing.expectError(error.InactiveObject, surface.rawHandle());
    try std.testing.expect(@hasDecl(rgfw.Window, "nativeHandle"));
    try std.testing.expect(@hasDecl(rgfw.Window, "nativeHandleAs"));
}

test "window resize validates dimensions and lifetime before calling RGFW" {
    var window: rgfw.Window = .{ .handle = null };
    try std.testing.expectError(error.InvalidSize, window.resize(0, 480));
    try std.testing.expectError(error.InvalidSize, window.resize(640, 0));
    try std.testing.expectError(error.InvalidSize, window.resize(-1, 480));
    try std.testing.expectError(error.InvalidSize, window.resize(640, -1));
    try std.testing.expectError(error.InactiveObject, window.resize(640, 480));
}

fn ignoreWindowClose() void {}

test "typed callback installation checks context lifetime" {
    var context: rgfw.Context = .{ .active = false };
    try std.testing.expectError(
        error.InactiveObject,
        context.on(rgfw.callback.window_close, ignoreWindowClose),
    );
}

test "window system selection is exposed to applications" {
    if (rgfw.window_system == .custom) return;
    const expected: rgfw.WindowSystem = switch (builtin.os.tag) {
        .macos => .cocoa,
        .windows => .win32,
        else => .x11,
    };
    try std.testing.expectEqual(expected, rgfw.window_system);
}

test "typed callback descriptors expose their payload" {
    try std.testing.expectEqual(rgfw.EventKind.window_resized, @TypeOf(
        rgfw.callback.window_resized,
    ).kind);
    try std.testing.expectEqual(rgfw.Size, @TypeOf(rgfw.callback.window_resized).Payload);
    try std.testing.expect(@hasDecl(rgfw.Context, "on"));
    try std.testing.expect(@hasDecl(rgfw.Context, "onWithContext"));
}

var last_diagnostic: ?rgfw.Diagnostic = null;

fn recordDiagnostic(diagnostic: rgfw.Diagnostic) void {
    last_diagnostic = diagnostic;
}

const DiagnosticCounter = struct {
    count: usize = 0,
};

fn countDiagnostic(counter: *DiagnosticCounter, _: rgfw.Diagnostic) void {
    counter.count += 1;
}

test "diagnostic handlers receive typed messages" {
    last_diagnostic = null;
    const handler = rgfw.DiagnosticHandler.fromHandler(recordDiagnostic);
    handler.dispatch(handler.context, .{
        .severity = .warning,
        .code = .platform,
        .message = "test diagnostic",
    });
    const diagnostic = last_diagnostic orelse return error.MissingDiagnostic;
    try std.testing.expectEqual(rgfw.DiagnosticSeverity.warning, diagnostic.severity);
    try std.testing.expectEqual(rgfw.DiagnosticCode.platform, diagnostic.code);
    try std.testing.expectEqualStrings("test diagnostic", diagnostic.message);

    var counter: DiagnosticCounter = .{};
    const contextual = rgfw.DiagnosticHandler.fromHandlerWithContext(
        &counter,
        countDiagnostic,
    );
    contextual.dispatch(contextual.context, diagnostic);
    try std.testing.expectEqual(@as(usize, 1), counter.count);
    try std.testing.expect(@hasDecl(rgfw, "initResult"));
}

test "typed events preserve key state and modifiers" {
    var raw_event: rgfw.raw.RGFW_event = undefined;
    raw_event.key = .{
        .type = @intCast(rgfw.raw.RGFW_keyPressed),
        .win = null,
        .value = @intFromEnum(rgfw.Key.one),
        .repeat = 1,
        .mod = @intCast(rgfw.raw.RGFW_modControl | rgfw.raw.RGFW_modShift),
        .state = 1,
    };
    const event: rgfw.Event = .{ .raw_value = raw_event };
    const accessed_key = event.keyEvent() orelse return error.MissingKeyEvent;
    try std.testing.expectEqual(rgfw.Key.one, accessed_key.key);
    try std.testing.expect(accessed_key.repeated);
    try std.testing.expectEqual(@as(?rgfw.MouseButton, null), event.mouseButton());
    switch (event.payload()) {
        .key_pressed => |key_event| {
            try std.testing.expectEqual(rgfw.Key.one, key_event.key);
            try std.testing.expect(key_event.repeated);
            try std.testing.expect(key_event.modifiers.control);
            try std.testing.expect(key_event.modifiers.shift);
            try std.testing.expect(!key_event.modifiers.alt);
        },
        else => return error.UnexpectedEventPayload,
    }
}

test "typed events expose mouse buttons and raw motion" {
    var raw_button: rgfw.raw.RGFW_event = undefined;
    raw_button.button = .{
        .type = @intCast(rgfw.raw.RGFW_mouseButtonPressed),
        .win = null,
        .value = @intFromEnum(rgfw.MouseButton.auxiliary_five),
        .state = 1,
    };
    const button_event: rgfw.Event = .{ .raw_value = raw_button };
    try std.testing.expectEqual(
        rgfw.MouseButton.auxiliary_five,
        button_event.mouseButton() orelse return error.MissingMouseButton,
    );
    try std.testing.expectEqual(@as(?rgfw.KeyEvent, null), button_event.keyEvent());
    switch (button_event.payload()) {
        .mouse_button_pressed => |button| try std.testing.expectEqual(
            rgfw.MouseButton.auxiliary_five,
            button,
        ),
        else => return error.UnexpectedEventPayload,
    }

    var raw_motion: rgfw.raw.RGFW_event = undefined;
    raw_motion.delta = .{
        .type = @intCast(rgfw.raw.RGFW_mouseRawMotion),
        .win = null,
        .x = 1.5,
        .y = -2.25,
    };
    const motion_event: rgfw.Event = .{ .raw_value = raw_motion };
    const raw_delta = motion_event.rawMouseDelta() orelse return error.MissingRawMouseDelta;
    try std.testing.expectEqual(@as(f32, 1.5), raw_delta.x);
    try std.testing.expectEqual(@as(?rgfw.Vector, null), motion_event.scrollDelta());
    switch (motion_event.payload()) {
        .mouse_raw_motion => |delta| {
            try std.testing.expectEqual(@as(f32, 1.5), delta.x);
            try std.testing.expectEqual(@as(f32, -2.25), delta.y);
        },
        else => return error.UnexpectedEventPayload,
    }
}

test "typed events expose resize data" {
    var raw_event: rgfw.raw.RGFW_event = undefined;
    raw_event.update = .{
        .type = @intCast(rgfw.raw.RGFW_windowResized),
        .win = null,
        .x = 40,
        .y = 30,
        .w = 1280,
        .h = 720,
    };
    const event: rgfw.Event = .{ .raw_value = raw_event };
    const accessed_size = event.windowSize() orelse return error.MissingWindowSize;
    try std.testing.expectEqual(@as(i32, 1280), accessed_size.width);
    try std.testing.expectEqual(@as(?rgfw.Rect, null), event.refreshRect());
    switch (event.payload()) {
        .window_resized => |size| {
            try std.testing.expectEqual(@as(i32, 1280), size.width);
            try std.testing.expectEqual(@as(i32, 720), size.height);
        },
        else => return error.UnexpectedEventPayload,
    }
}

test "focus accessors accept only focus event kinds" {
    var raw_event: rgfw.raw.RGFW_event = undefined;
    raw_event.focus = .{
        .type = @intCast(rgfw.raw.RGFW_windowFocusOut),
        .win = null,
        .state = 0,
    };
    const event: rgfw.Event = .{ .raw_value = raw_event };
    try std.testing.expectEqual(@as(?bool, false), event.focusState());
    try std.testing.expectEqual(@as(?rgfw.Point, null), event.windowPosition());
}

test "unknown events retain their complete raw value" {
    var raw_event: rgfw.raw.RGFW_event = undefined;
    raw_event.common = .{ .type = 255, .win = null };
    const event: rgfw.Event = .{ .raw_value = raw_event };

    try std.testing.expectEqual(@as(u8, 255), @intFromEnum(event.kind()));
    try std.testing.expectEqual(@as(u8, 255), event.rawEvent().type);
    switch (event.payload()) {
        .unknown => |unknown| {
            try std.testing.expectEqual(@as(u8, 255), @intFromEnum(unknown.kind));
            try std.testing.expectEqual(@as(u8, 255), unknown.raw_value.type);
        },
        else => return error.UnexpectedEventPayload,
    }
}

test "input enums name extended RGFW controls" {
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_key, @intCast(rgfw.raw.RGFW_keyF25)),
        @intFromEnum(rgfw.Key.f25),
    );
    try std.testing.expectEqual(
        @as(rgfw.raw.RGFW_mouseButton, @intCast(rgfw.raw.RGFW_mouseMisc5)),
        @intFromEnum(rgfw.MouseButton.auxiliary_five),
    );
}

test "automatic exit keys are opt in" {
    const options: rgfw.Window.Options = .{};
    try std.testing.expectEqual(@as(?rgfw.Key, null), options.exit_key);
}

test "cursor mode wraps RGFW's combined raw capture operation" {
    try std.testing.expect(@hasDecl(rgfw.Window, "captureRawMouse"));
    try std.testing.expect(@hasDecl(rgfw.Window, "setCursorMode"));
    try std.testing.expect(@hasDecl(rgfw.Window, "rawMouseMode"));
    try std.testing.expect(@hasDecl(rgfw.Window, "mouseCaptured"));
    try std.testing.expect(@hasDecl(rgfw.Window, "mouseHidden"));
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
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "requiredInstanceExtensionPointers"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "createSurface"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "createSurfaceAs"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "appendRequiredInstanceExtensions"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "createOwnedSurfaceAs"));
    try std.testing.expect(@hasDecl(rgfw.Vulkan, "presentationSupported"));

    var extensions = rgfw.Vulkan.requiredInstanceExtensions();
    try std.testing.expect(extensions.count() >= 1);
    var found_metal_surface = false;
    while (extensions.next()) |extension| {
        try std.testing.expect(extension.len != 0);
        if (std.mem.eql(u8, extension, "VK_EXT_metal_surface")) {
            found_metal_surface = true;
        }
        try std.testing.expect(!std.mem.eql(u8, extension, "VK_MVK_macos_surface"));
    }
    if (builtin.os.tag == .macos) try std.testing.expect(found_metal_surface);
}

test "DirectX and WebGPU declarations follow feature options" {
    if (rgfw.features.directx) {
        try std.testing.expect(@hasDecl(rgfw.DirectX, "createSwapChain"));
    } else {
        try std.testing.expect(!@hasDecl(rgfw.raw, "RGFW_window_createSwapChain_DirectX"));
    }

    if (rgfw.features.webgpu) {
        try std.testing.expect(@hasDecl(rgfw.WebGPU, "createSurface"));
        try std.testing.expect(@hasDecl(rgfw.WebGPU, "createSurfaceAs"));
    } else {
        try std.testing.expect(!@hasDecl(rgfw.raw, "WGPUInstance"));
    }
}

test "Vulkan surface interop accepts handles from an independent module" {
    if (!rgfw.features.vulkan) return;

    // A closed window reaches no platform or Vulkan runtime, but compiling this call
    // still instantiates createSurfaceAs with both independent foreign handle types.
    const foreign_instance = foreign_vulkan.instanceFromAddress(0x1000);
    var closed_window: rgfw.Window = .{ .handle = null };
    try std.testing.expectError(
        error.SurfaceCreationFailed,
        rgfw.Vulkan.createSurfaceAs(
            foreign_vulkan.Surface,
            &closed_window,
            foreign_instance,
        ),
    );
}

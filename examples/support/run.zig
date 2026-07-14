const rgfw = @import("rgfw");

pub const FrameFn = *const fn (window: *rgfw.Window) void;

pub fn window(
    title: [:0]const u8,
    options: rgfw.Window.Options,
    frame: ?FrameFn,
) !void {
    var context = try rgfw.init("rgfw-zig-example", .{});
    defer context.deinit();

    var app_window = try context.createWindow(title, options);
    defer app_window.deinit();

    while (!app_window.shouldClose()) {
        rgfw.pollEvents();
        while (app_window.nextEvent()) |event| {
            if (event.kind() == .window_close) app_window.requestClose();
        }
        if (frame) |update| update(&app_window);
    }
}

pub fn openGL(
    title: [:0]const u8,
    options: rgfw.Window.Options,
    frame: ?FrameFn,
) !void {
    var context = try rgfw.init("rgfw-zig-opengl-example", .{ .backend = .opengl });
    defer context.deinit();

    var window_options = options;
    window_options.flags.open_gl = true;
    var app_window = try context.createWindow(title, window_options);
    defer app_window.deinit();

    rgfw.OpenGL.makeCurrent(&app_window);
    rgfw.OpenGL.swapInterval(&app_window, 1);
    while (!app_window.shouldClose()) {
        rgfw.pollEvents();
        while (app_window.nextEvent()) |event| {
            if (event.kind() == .window_close) app_window.requestClose();
        }
        if (frame) |update| update(&app_window);
        rgfw.OpenGL.swapBuffers(&app_window);
    }
}

pub fn egl(
    title: [:0]const u8,
    options: rgfw.Window.Options,
    frame: ?FrameFn,
) !void {
    var context = try rgfw.init("rgfw-zig-egl-example", .{ .backend = .egl });
    defer context.deinit();

    var window_options = options;
    window_options.flags.egl = true;
    var app_window = try context.createWindow(title, window_options);
    defer app_window.deinit();

    rgfw.EGL.makeCurrent(&app_window);
    rgfw.EGL.swapInterval(&app_window, 1);
    while (!app_window.shouldClose()) {
        rgfw.pollEvents();
        while (app_window.nextEvent()) |event| {
            if (event.kind() == .window_close) app_window.requestClose();
        }
        if (frame) |update| update(&app_window);
        rgfw.EGL.swapBuffers(&app_window);
    }
}

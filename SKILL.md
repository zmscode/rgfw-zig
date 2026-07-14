---
name: rgfw-zig
description: Integrate, configure, regenerate, test, and debug the rgfw-zig Zig 0.16 bindings for RGFW. Use when an agent needs to add RGFW windows or input to a Zig project, enable OpenGL, EGL, or Vulkan, consume raw RGFW declarations, regenerate bindings from upstream, port RGFW examples, or diagnose rgfw-zig build and event-loop behavior.
---

# RGFW Zig

Use the idiomatic `rgfw` module by default. Reach for `rgfw.raw` only when the wrapper does not yet
cover an RGFW operation.

## Add the dependency

Run:

```sh
zig fetch --save=rgfw git+https://github.com/zmscode/rgfw-zig.git
```

In `build.zig`, pass the executable's target and optimization mode to the dependency, then import
its `rgfw` module:

```zig
const dependency = b.dependency("rgfw", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("rgfw", dependency.module("rgfw"));
```

Enable only required backends with `.opengl = true`, `.egl = true`, or `.vulkan = true`. Enable
RGFW diagnostics with `.@"rgfw-debug" = true`.

The dependency selects Cocoa on macOS, Win32 on Windows, and X11 on Unix. Select native Wayland
on Linux with `.@"window-system" = .wayland`. Wayland requires `wayland-scanner`,
`wayland-client`, `wayland-cursor`, and `xkbcommon` development packages.

## Create and run a window

Acquire resources next to their `defer` statements:

```zig
var context = try rgfw.init("application-name", .{});
defer context.deinit();

var window = try context.createWindow("Window title", .{
    .width = 800,
    .height = 450,
    .exit_key = .escape,
    .flags = .{ .centered = true },
});
defer window.deinit();

while (window.isOpen()) window.pumpEvents();
```

Exit keys are opt-in. Leave `.exit_key` unset when Escape belongs to the application's input map.

Use `pumpEvents()` when event payloads are not needed. To consume payloads, call
`context.pollEvents()` once per frame, create `var events = window.events()`, and drain
`events.next()`. Switch on `event.payload()` for Zig-native key, button, motion, scroll, resize,
scale, drag/drop, and monitor data. `nextQueuedEvent()` explicitly reads only the existing queue;
`nextEvent()` is its concise alias. Use `pollEvent()` only when combined poll-and-pop behavior is
intentional. RGFW already marks the window as closing before emitting `.window_close`; never call
`requestClose()` in response to that event.

For callback-oriented code, install a typed descriptor and retain its subscription:

```zig
var resized = try context.on(rgfw.callback.window_resized, onResize);
defer resized.deinit();

fn onResize(size: rgfw.Size) void {
    _ = size;
}
```

Use `onWithContext` for application state. Do not write `callconv(.c)` adapters for wrapped event
kinds. Deinitialize subscriptions in reverse installation order before the RGFW context.

For compact, non-exhaustive handlers, use the nullable `Event` accessors: `keyEvent()`,
`mouseButton()`, `scrollDelta()`, `rawMouseDelta()`, `mousePosition()`, `mouseInWindow()`,
`focusState()`, `windowPosition()`, `windowSize()`, and `refreshRect()`. Each returns `null` for an
event kind outside its documented match. Use `rawEvent()` only for data not represented above.

Use `window.setCursorMode(.captured)` and `.normal` for first-person pointer ownership rather than
coordinating raw mode, capture, and visibility separately.

Use `window.rawHandle()` and `surface.rawHandle()` for checked RGFW handles. Use
`window.nativeHandle()` for a tagged Cocoa, Win32, X11, or Wayland value. Do not read the public
optional handle fields or call platform-specific raw getters just to determine whether an object is
active.

Install typed diagnostics through `InitOptions.diagnostic_handler`:

```zig
.diagnostic_handler = rgfw.DiagnosticHandler.fromHandler(handleDiagnostic),
```

Handlers receive `rgfw.Diagnostic` with a severity, non-exhaustive code, and borrowed message. Use
`initResult` when the caller needs the initialization status, backend, and window system on failure.
RGFW installs custom debug callbacks only after successful initialization, so do not expect the
typed handler to receive an initialization failure.

## Select a graphics backend

- OpenGL: enable `.opengl = true`, initialize with `.backend = .opengl`, and create the window with
  `.flags.open_gl = true`.
- EGL: enable `.egl = true`, initialize with `.backend = .egl`, and create the window with
  `.flags.egl = true`.
- Vulkan: enable `.vulkan = true` and initialize with `.backend = .vulkan`. Iterate with
  `var extensions = rgfw.Vulkan.requiredInstanceExtensions()` or append the original borrowed
  pointers directly with `appendRequiredInstanceExtensions`. Enable each before creating the
  instance. macOS uses `VK_EXT_metal_surface` rather than the deprecated MVK surface extension.

For independently translated Vulkan handles such as `vk-zig`, centralize ABI reinterpretation:

```zig
var surface = try rgfw.Vulkan.createOwnedSurfaceAs(
    vk.raw.VkSurfaceKHR,
    &window,
    &instance,
);
defer surface.deinit();
```

Do not add local Vulkan `@ptrCast` bridges. `createSurfaceAs` validates handle representation and
size when raw ownership stays with the caller. Prefer `createOwnedSurfaceAs` with vk-zig so its
`Instance.adoptSurface` owns and destroys the surface. Populate `vk.ExtensionSet` with
`appendRequiredInstanceExtensions`; do not hand-copy the pointer array.

## Regenerate and validate

Use the vendored RGFW header for ordinary builds. Regenerate only when the task requires an
upstream refresh:

```sh
zig build bindings
zig build update
zig build update -Drgfw-ref=v1.8.1
```

After changes, run the relevant matrix:

```sh
zig fmt --check build.zig src tests tools examples
zig build test
zig build test -Doptimize=ReleaseFast
zig build test -Dvulkan=true
zig build examples -Dopengl=true -Degl=true -Dvulkan=true
zig build examples -Dvulkan=true -Dvk-zig-example=true
```

Keep compile-failure cases under `tests/compile_fail` and register them with `expect_errors` in
`build.zig`. Use these for wrong callback payloads, mismatched native handles, disabled backends,
and ABI-incompatible Vulkan handles so the intended `@compileError` text remains stable.

Keep generated `.zig-cache`, `zig-out`, and `zig-pkg` content out of commits. Preserve unrelated
user changes and preserve vendored `RGFW.h` byte-for-byte unless intentionally refreshing it.

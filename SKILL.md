---
name: rgfw-zig
description: Integrate, configure, regenerate, test, and debug the rgfw-zig Zig 0.17 development bindings for RGFW. Use when an agent needs RGFW windows, input, monitors, software surfaces, OpenGL, EGL, Vulkan, DirectX, or WebGPU; needs advanced allocator/backend configuration; or must regenerate bindings from upstream.
---

# RGFW Zig

Use the idiomatic `rgfw` module by default. Reach for `rgfw.raw` only when the wrapper does not yet
cover an RGFW operation.

## Add the dependency

Run:

```sh
zig fetch --save=rgfw git+https://github.com/zmscode/rgfw-zig.git#codex/zig-0.17-dev
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

DirectX uses `.directx = true` on Windows. WebGPU uses `.webgpu = true` and requires the
application to link a provider; name a system provider with `.@"webgpu-library"` when appropriate.

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

Use `try window.resize(width, height)` for programmatic resizing. It validates positive dimensions
and active lifetime before calling RGFW. Treat the request as asynchronous and consume the typed
`.window_resized` event or callback for the applied size.

For compact, non-exhaustive handlers, use the nullable `Event` accessors: `keyEvent()`,
`mouseButton()`, `scrollDelta()`, `rawMouseDelta()`, `mousePosition()`, `mouseInWindow()`,
`focusState()`, `windowPosition()`, `windowSize()`, and `refreshRect()`. Each returns `null` for an
event kind outside its documented match. Use `rawEvent()` only for data not represented above.

Use `window.setCursorMode(.captured)` and `.normal` for first-person pointer ownership rather than
coordinating raw mode, capture, and visibility separately.

Use `CustomCursor.init`/`deinit` and `Window.setCursor` for pixel cursors, `Window.setIcon` for
typed icons, and `Surface.initForWindow` for software rendering. The window-scoped surface path is
required for safe X11 visual selection. Construct pixel data with `Image.init` so dimensions,
format, overflow, and buffer length are checked once.

Use `Clipboard.readAlloc` for owned clipboard bytes and `Clipboard.read` only for a short-lived
borrow invalidated by the next read or context shutdown. Enumerate displays with
`Context.monitors`, free that Zig-allocated slice, and use `Monitor.supportedModes` or
`Monitor.gammaRamp` for allocator-owned copies. An empty monitor slice is a valid transient state,
and `Context.primaryMonitor()` returns `null` safely. Treat `Window.setFullscreen` and
`Window.scaleToMonitor` as fallible and handle `error.MonitorUnavailable`. Monitor event payloads
are immutable `MonitorSnapshot` values so disconnect events never expose stale handles;
re-enumerate the context when a live `Monitor` is needed. Physical monitor sizes are millimetres.

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

- OpenGL: enable `.opengl = true`, initialize with `.backend = .opengl`, then use
  `OpenGL.createContext` with explicit `GraphicsHints` when version/profile matters.
- EGL: enable `.egl = true`, initialize with `.backend = .egl`, then use `EGL.createContext` with
  `.profile = .embedded` for OpenGL ES.
- Vulkan: enable `.vulkan = true` and initialize with `.backend = .vulkan`. Iterate with
  `var extensions = rgfw.Vulkan.requiredInstanceExtensions()` or append the original borrowed
  pointers directly with `appendRequiredInstanceExtensions`. Enable each before creating the
  instance. macOS uses `VK_EXT_metal_surface` rather than the deprecated MVK surface extension.

For vk-zig, use its typed platform extensions and RGFW's structural surface adapter:

```zig
var extensions: vk.InstanceExtensionSet(4) = .{};
try extensions.appendAll(vk.SurfaceConfiguration.instanceExtensions());
try extensions.appendAll(vk.Portability.instanceExtensions());

var surface = try instance.createSurfaceWithAdapter(
    rgfw.Vulkan.surfaceAdapter(vk, &window),
);
defer surface.deinit();
```

Do not add local Vulkan `@ptrCast` bridges. `createSurfaceAs` validates handle representation and
size when raw ownership stays with the caller. `createOwnedSurface` remains available for packages
that expose `rawHandle` and `adoptSurface`; current vk-zig integrations should prefer
`Instance.createSurfaceWithAdapter`.

For DirectX and WebGPU packages with independently declared handles, use
`DirectX.createSwapChain` and `WebGPU.createSurfaceAs`; do not add application-level casts.

For allocator hooks, enable `.@"custom-allocator" = true`, retain a stable `AllocatorHooks` value
from before `rgfw.init` until after every resource is deinitialized, then call `uninstall`. Custom
backends use `.@"window-system" = .custom` plus an absolute `.@"custom-backend-header"` path; that
same header drives translation and C compilation.

## Regenerate and validate

Use the vendored RGFW header for ordinary builds. Regenerate only when the task requires an
upstream refresh:

```sh
zig build bindings
zig build update
zig build update -Drgfw-ref=v1.8.1
```

The update command applies `patches/rgfw-monitor-fixes.patch` after cloning upstream. If the patch
no longer applies, review the changed upstream monitor implementation instead of bypassing it.

After changes, run the relevant matrix:

```sh
zig fmt --check build.zig src tests tools examples
zig build test
zig build test -Doptimize=ReleaseFast
zig build test -Dvulkan=true
zig build test -Dcustom-allocator=true
zig build examples -Dopengl=true -Degl=true -Dvulkan=true
zig build examples -Dvulkan=true -Dvk-zig-example=true
zig build bindings -Dtarget=x86_64-windows-gnu -Ddirectx=true
zig build examples -Dwebgpu=true
```

Keep compile-failure cases under `tests/compile_fail` and register them with `expect_errors` in
`build.zig`. Use these for wrong callback payloads, mismatched native handles, disabled backends,
and ABI-incompatible Vulkan handles so the intended `@compileError` text remains stable.

Keep generated `.zig-cache`, `zig-out`, and `zig-pkg` content out of commits. Preserve unrelated
user changes and preserve vendored `RGFW.h` byte-for-byte unless intentionally refreshing it.

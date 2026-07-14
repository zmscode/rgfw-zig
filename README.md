# rgfw-zig

Zig 0.16 bindings for [RGFW](https://github.com/ColleagueRiley/RGFW). The package:

- translates and cleans the vendored `RGFW.h` for the selected Zig target;
- provides an idiomatic, resource-safe Zig API and the complete raw C ABI;
- compiles the RGFW implementation into any module that imports `rgfw`;
- links the required platform libraries automatically;
- can refresh the header, license, and recorded commit from the upstream repository.

Normal builds use the vendored header and do not need Git or network access.

AI coding agents can use the repository's installable [`rgfw-zig` skill](SKILL.md) for concise,
version-specific integration and validation guidance.

## Use as a dependency

Add the package to your application's `build.zig.zon` with Zig 0.16:

```sh
zig fetch --save=rgfw git+https://github.com/zmscode/rgfw-zig.git
```

The command records a content hash and resolved Git revision in `build.zig.zon`. For local
development, the equivalent path dependency is:

```zig
.dependencies = .{
    .rgfw = .{
        .path = "../rgfw-zig",
    },
},
```

Then expose the module to your executable in `build.zig`:

```zig
const rgfw_dependency = b.dependency("rgfw", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("rgfw", rgfw_dependency.module("rgfw"));
```

The main module wraps initialization, windows, flags, and events with Zig types and errors:

```zig
const rgfw = @import("rgfw");

pub fn main() !void {
    var context = try rgfw.init("rgfw-zig", .{});
    defer context.deinit();

    var window = try context.createWindow("Hello from Zig", .{
        .width = 800,
        .height = 450,
        .exit_key = .escape,
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();

    while (window.isOpen()) window.pumpEvents();
}
```

`pumpEvents()` is the concise path when an application only needs RGFW's window and input state.
Exit keys are opt-in; omit `.exit_key` when Escape or another key belongs to application input.

For typed event payloads, poll once and drain only the events from that platform snapshot:

```zig
context.pollEvents();
var events = window.events();
while (events.next()) |event| {
    switch (event.payload()) {
        .key_pressed => |key| if (key.key == .escape) window.requestClose(),
        .mouse_raw_motion => |delta| {
            _ = delta;
        },
        .window_close => {}, // RGFW has already marked the window as closing.
        else => {},
    }
}
```

`nextQueuedEvent()` never polls implicitly; `nextEvent()` is its concise alias. `pollEvent()`
retains RGFW's combined poll-and-pop behavior for applications that specifically want it.
`event.rawEvent()` provides lossless access to the C event when integrating functionality newer
than the typed wrapper.

For compact handlers, nullable accessors such as `keyEvent()`, `mouseButton()`, `scrollDelta()`,
`rawMouseDelta()`, `mousePosition()`, `focusState()`, `windowPosition()`, `windowSize()`, and
`refreshRect()` return `null` when the event kind does not match.

RGFW callbacks can also be installed without exposing a C calling convention or raw event union:

```zig
var resized = try context.on(rgfw.callback.window_resized, onResize);
defer resized.deinit();

fn onResize(size: rgfw.Size) void {
    _ = size;
}
```

Use `onWithContext` when a handler needs application state. The descriptor fixes the payload type,
so a mismatched handler is rejected at compile time. Subscriptions restore the previous RGFW
callback when deinitialized and should be released in reverse installation order.

Programmatic resizing is checked and uses the same typed event path:

```zig
try window.resize(1280, 720);
```

Non-positive dimensions return `error.InvalidSize`, while a closed window returns
`error.InactiveObject`. The platform applies the request asynchronously; consume
`.window_resized` or install `rgfw.callback.window_resized` to observe the resulting size.

Other runtime controls use the same checked value types:

```zig
try window.move(.{ .x = 40, .y = 40 });
try window.setMinSize(.{ .width = 320, .height = 180 });
try window.setAspectRatio(.{ .width = 16, .height = 9 });
try window.setOpacity(220);
try window.setEventEnabled(.mouse_raw_motion, true);
```

Captured first-person input is one state change rather than three independent calls:

```zig
window.setCursorMode(.captured);
defer window.setCursorMode(.normal);
```

The mechanically translated ABI remains available as `rgfw.raw`, or as the dependency module
`rgfw-raw` when a consumer wants to import it separately. See
[`examples/basic.zig`](examples/basic.zig) for the complete wrapper example.

## Commands

```sh
# Generate bindings for the native target in zig-out/bindings/rgfw.zig.
zig build

# The explicit equivalent of the default step.
zig build bindings

# Compile and run tests.
zig build test

# Build or run the example.
zig build example
zig build run-example

# Build all portable examples, plus enabled backend examples.
zig build examples
zig build examples -Dopengl=true -Dvulkan=true

# Every example has a named run step.
zig build run-clipboard
zig build run-vk10 -Dvulkan=true
zig build run-vk-zig -Dvulkan=true -Dvk-zig-example=true

# Pull the latest main branch and regenerate/verify the bindings.
zig build update

# Pull a specific upstream branch or tag instead.
zig build update -Drgfw-ref=v1.8.1
```

`zig build update` requires `git` and network access. It only replaces the vendored files after
the downloaded header successfully translates and contains the core RGFW declarations. The exact
upstream revision is recorded in `vendor/RGFW_COMMIT`.

Bindings are generated for the selected target, so cross-target output can be requested with, for
example, `zig build bindings -Dtarget=x86_64-windows-gnu`.

## Options

RGFW's OpenGL helpers are opt-in:

```zig
const rgfw_dependency = b.dependency("rgfw", .{
    .target = target,
    .optimize = optimize,
    .opengl = true,
});
```

RGFW diagnostics can be enabled in dependency options:

```zig
.@"rgfw-debug" = true,
```

Use `-Drgfw-debug=true` when building this package directly.

Diagnostics can be received as Zig values instead of `RGFW_debugInfo`:

```zig
var context = try rgfw.init("application", .{
    .diagnostic_handler = rgfw.DiagnosticHandler.fromHandler(logDiagnostic),
});

fn logDiagnostic(diagnostic: rgfw.Diagnostic) void {
    std.log.info("{s}: {s}", .{ @tagName(diagnostic.code), diagnostic.message });
}
```

`DiagnosticSeverity` and the non-exhaustive `DiagnosticCode` preserve unknown future RGFW values.
`initResult` additionally returns an `InitializationFailure` with the raw status, requested backend,
and selected window system when an application needs more detail than `init`'s error union. RGFW
only permits replacing its debug callback after initialization, so the typed handler receives
runtime and shutdown diagnostics; use `initResult` for initialization failures.

EGL is enabled independently with `.egl = true` or `-Degl=true`. Its official Khronos headers are
downloaded lazily, just like the Vulkan headers.

OpenGL and EGL context requirements can be stated explicitly instead of relying on driver
defaults:

```zig
const gl_context = try rgfw.OpenGL.createContext(&window, .{ .hints = .{
    .profile = .core,
    .major_version = 3,
    .minor_version = 3,
    .debug = true,
} });
_ = gl_context; // Owned by window; Window.deinit releases it.
rgfw.OpenGL.makeCurrent(&window);
```

`Graphics.GlobalHints` provides stable storage for RGFW's borrowed global-hints pointer. Explicit
contexts returned by `OpenGL.createContext` and `EGL.createContext` are borrowed, window-owned
handles and must not outlive or be deinitialized separately from their window.

### Window systems and native handles

The build chooses `.cocoa` on macOS, `.win32` on Windows, and `.x11` on Unix by default. Linux can
select native Wayland explicitly:

```zig
const rgfw_dependency = b.dependency("rgfw", .{
    .target = target,
    .optimize = optimize,
    .@"window-system" = .wayland,
});
```

The direct command is `zig build -Dtarget=x86_64-linux-gnu -Dwindow-system=wayland`. Wayland builds
require `wayland-scanner` plus the Wayland client, cursor, and xkbcommon development packages. The
protocol XML is fetched lazily from the RGFW revision vendored by this package, and generated C
protocol code stays in Zig's cache.

On Linux hosts using GCC 16, Zig 0.16's linker may reject `.sframe` relocations from the host CRT.
This is a Zig/toolchain interaction rather than an RGFW source failure. Force Zig's explicit GNU
target and system search prefix when it occurs:

```sh
zig build test -Dtarget=x86_64-linux-gnu --search-prefix /usr
zig build examples -Dtarget=x86_64-linux-gnu --search-prefix /usr
```

Use `window.rawHandle()` for checked RGFW FFI access and `window.nativeHandle()` for a tagged
`NativeWindowHandle`. Cocoa returns the window and view, Win32 returns HWND and HDC, X11 returns its
window ID, and Wayland returns `wl_surface`. Closed windows and freed software surfaces report
`error.InactiveObject` rather than requiring optional-field tricks.

`Context.nativeDisplayHandle()` returns the matching display-level tagged union. Cocoa layer,
X11 `Display`, Wayland `wl_display`, EGL context/display/surface, and Win32 window integrations are
available without direct getter calls in `rgfw.raw`.

### Ownership and borrowed data

`Context`, `Window`, `Surface`, `CustomCursor`, and `EventSubscription` are single-owner values:
do not copy a live value, and defer its idempotent `deinit`. Clipboard transfers returned by
`Clipboard.read`, monitor names/handles, native handles, Vulkan extension names, and surface native
images are borrowed. Their API documentation names the invalidating owner or operation.

Use `Clipboard.readAlloc`, `Context.monitors`, `Monitor.supportedModes`, and
`Monitor.gammaRamp` when data must outlive a borrowed view; free allocator-owned results with the
same allocator. The ordinary software-surface path is `Surface.initForWindow`, which uses the
window's visual and avoids X11 visual mismatches.

### DirectX and WebGPU

DirectX is Windows-only and opt-in with `.directx = true` or `-Ddirectx=true`.
`rgfw.DirectX.createSwapChain` accepts a consumer's typed DXGI factory/device pointers and returns
that package's requested swap-chain pointer type. Windows COM headers are intentionally not passed
through translate-c, avoiding unusable SDK macro declarations.

WebGPU is opt-in with `.webgpu = true`. The canonical `webgpu-headers` package is fetched lazily;
the application must also link a compatible provider such as Dawn or wgpu-native. A system library
can be named with `.@"webgpu-library" = "wgpu_native"` (or
`-Dwebgpu-library=wgpu_native`). `WebGPU.createSurfaceAs` preserves ABI-compatible opaque handle
types from the consumer's WebGPU package.

### Custom allocation and backends

Build with `.@"custom-allocator" = true`, keep an `AllocatorHooks` value alive for the complete
RGFW lifetime, and install it before initialization:

```zig
var hooks = rgfw.AllocatorHooks.init(gpa);
hooks.install();
defer rgfw.AllocatorHooks.uninstall(); // after all RGFW resources are gone
```

The bridge stores allocation sizes so RGFW's pointer-only `RGFW_FREE` contract can safely call a
Zig `std.mem.Allocator`. Installation is process-global and must not race RGFW allocation.

A custom RGFW backend is selected with `.@"window-system" = .custom` and an absolute
`.@"custom-backend-header"` path. The header follows RGFW's custom-backend contract: define
`RGFW_CUSTOM_BACKEND`, define `RGFW_window_src`, include `RGFW.h`, and provide the required
platform functions under `RGFW_IMPLEMENTATION`. The same header is used for translation and C
compilation, preventing ABI drift. Adapter backends that select the target's normal platform can
also set `.@"custom-backend-link-platform-libraries" = true`; true custom backends link their own
dependencies from the application build.

The repository validates this contract with a dependency-free headless backend:

```sh
zig build test -Dwindow-system=custom \
  -Dcustom-backend-header="$PWD/tests/minimal_custom_backend.h"
```

### Vulkan

Vulkan integration is also opt-in:

```zig
const rgfw_dependency = b.dependency("rgfw", .{
    .target = target,
    .optimize = optimize,
    .vulkan = true,
});
```

The option lazily fetches the official Vulkan-Headers package. Normal builds do not download it.
RGFW loads the Vulkan loader at runtime, so applications still need a working Vulkan runtime (and
MoltenVK on macOS), but this package does not require a loader library at link time.

Initialize RGFW with the Vulkan backend, then use the conditional `rgfw.Vulkan` helpers:

```zig
var context = try rgfw.init("rgfw-zig", .{ .backend = .vulkan });
defer context.deinit();

var window = try context.createWindow("Vulkan", .{});
defer window.deinit();

var extensions = rgfw.Vulkan.requiredInstanceExtensions();
while (extensions.next()) |extension| {
    // Enable this sentinel-terminated Zig slice while creating your VkInstance.
    _ = extension;
}
// Then:
const surface = try rgfw.Vulkan.createSurface(&window, instance);
```

The iterator does not allocate. Low-level consumers can use
`requiredInstanceExtensionPointers()` to obtain RGFW's original C pointer array. On macOS the
package uses the standard `VK_EXT_metal_surface` path and creates the surface from a
`CAMetalLayer`.

When another Zig package owns independently translated Vulkan handle types, use the checked
interop boundary instead of scattering `@ptrCast` calls through application code. The advanced
non-owning form is `createSurfaceAs`; it verifies handle representation and leaves destruction to
the caller.

`createSurfaceAs` accepts only opaque pointer handles (or the target platform's unsigned integer
Vulkan handle representation) with the same size and representation as RGFW's handle. The ABI
reinterpretation does not transfer ownership: the application must destroy the returned surface
through the Vulkan instance that created it. `rgfw-zig` does not import `vk-zig`, so neither package
introduces a dependency cycle.

With [vk-zig](https://github.com/zmscode/vk-zig), its fixed-capacity extension set accepts RGFW's
borrowed C names directly and RGFW can transfer the new surface into vk-zig ownership in one call:

```sh
zig fetch --save=vulkan git+https://github.com/zmscode/vk-zig.git
```

```zig
var extensions: vk.ExtensionSet(4) = .{};
try rgfw.Vulkan.appendRequiredInstanceExtensions(&extensions);
try extensions.appendAll(vk.Portability.instanceExtensions());

var surface = try rgfw.Vulkan.createOwnedSurface(&window, &instance);
defer surface.deinit();
```

The optional repository example pins vk-zig only for its own build. Normal rgfw-zig consumers do
not download or import it. Build that example with
`zig build run-vk-zig -Dvulkan=true -Dvk-zig-example=true`.

Use `zig build -Dvulkan=true` when building this repository directly. Vulkan declarations are
also available through `rgfw.raw` when the option is enabled.

## Examples

The package includes an idiomatic Zig counterpart for every upstream RGFW example directory at
the vendored revision. They cover callbacks, clipboard access, event queues, window flags,
multiple windows, monitor state, software surfaces, cursors/icons, OpenGL, EGL, Metal handles,
DirectX/WebGPU interop, and Vulkan instance/surface creation. See
[`examples/README.md`](examples/README.md) for the full feature-gated index.

### Translation errors

Directly translating RGFW on macOS currently produces more than a thousand lazy
`@compileError` declarations. Almost all are implementation-only SDK and libc preprocessor
macros. RGFW's own three failures (`RGFW_STATIC_ASSERT`, `RGFWDEF`, and `RGFW_ENUM`) are C
declaration helpers rather than callable API.

The build translates through [`src/rgfw_translate.h`](src/rgfw_translate.h), which exposes only
the ABI declarations, then [`tools/clean_bindings.zig`](tools/clean_bindings.zig) removes the
remaining macro appendix and fails generation if an error appears among actual declarations.
This leaves the raw module free of `@compileError` placeholders. Useful RGFW constants and enum
values remain available; `RGFW_TRUE` and `RGFW_FALSE` are restored explicitly.

The test step also compiles intentional failures for wrong callback payloads, mismatched native
handles, disabled Vulkan/DirectX/WebGPU use, and ABI-incompatible foreign Vulkan handles. This
keeps the wrapper's own `@compileError` messages actionable as Zig evolves.

The package configures RGFW for Cocoa, Win32, X11, or Wayland explicitly. Linux and BSD X11 users
need the X11 and XRandR development packages installed. Linux Wayland users need the tools and
libraries listed above.

## Licenses

The Zig package is MIT licensed. The vendored RGFW source retains its upstream zlib license in
[`vendor/LICENSE`](vendor/LICENSE).

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
        .flags = .{ .centered = true, .no_resize = true },
    });
    defer window.deinit();

    while (window.isOpen()) window.pumpEvents();
}
```

`pumpEvents()` is the concise path when an application only needs RGFW's window and input state.
To inspect individual events, use `rgfw.pollEvents()` followed by `window.nextEvent()`. RGFW marks
the window as closing before it emits `.window_close`, so that event does not need to call
`requestClose()`. Use `requestClose()` when application logic wants to initiate shutdown.

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

EGL is enabled independently with `.egl = true` or `-Degl=true`. Its official Khronos headers are
downloaded lazily, just like the Vulkan headers.

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

const extensions = rgfw.Vulkan.requiredInstanceExtensions();
// Enable `extensions` while creating your VkInstance, then:
const surface = try rgfw.Vulkan.createSurface(&window, instance);
```

When another Zig package owns independently translated Vulkan handle types, use the checked
interop boundary instead of scattering `@ptrCast` calls through application code. For example,
with `vk-zig`'s explicit raw-handle accessor:

```zig
const surface: vk.raw.VkSurfaceKHR = try rgfw.Vulkan.createSurfaceAs(
    vk.raw.VkSurfaceKHR,
    &window,
    instance.rawHandle(),
);
```

`createSurfaceAs` accepts only opaque pointer handles (or the target platform's unsigned integer
Vulkan handle representation) with the same size and representation as RGFW's handle. The ABI
reinterpretation does not transfer ownership: the application must destroy the returned surface
through the Vulkan instance that created it. `rgfw-zig` does not import `vk-zig`, so neither package
introduces a dependency cycle.

Use `zig build -Dvulkan=true` when building this repository directly. Vulkan declarations are
also available through `rgfw.raw` when the option is enabled.

## Examples

The package includes an idiomatic Zig counterpart for every upstream RGFW example directory at
the vendored revision. They cover callbacks, clipboard access, event queues, window flags,
multiple windows, monitor state, software surfaces, cursors/icons, OpenGL, EGL, Metal handles,
DirectX handles, and Vulkan instance/surface creation. See
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

The package currently configures RGFW for macOS, Windows, and X11-based Unix targets. Linux and
BSD users need the X11 and XRandR development packages installed. Wayland support requires RGFW's
generated protocol sources and is not enabled by this first version.

## Licenses

The Zig package is MIT licensed. The vendored RGFW source retains its upstream zlib license in
[`vendor/LICENSE`](vendor/LICENSE).

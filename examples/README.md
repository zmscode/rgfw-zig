# Zig examples

This directory contains an idiomatic Zig counterpart for every example directory in RGFW at the
vendored revision recorded in `vendor/RGFW_COMMIT`. The ports preserve the RGFW concept being
demonstrated, but intentionally replace bundled C utilities and assets with Zig-owned memory,
procedural data, and small shared helpers under `support/`.

Build every example supported by the enabled feature set:

```sh
zig build examples
zig build examples -Dopengl=true
zig build examples -Degl=true
zig build examples -Dvulkan=true
zig build examples -Dcustom-allocator=true
```

Each enabled example also gets a run step. For example:

```sh
zig build run-clipboard
zig build run-gl33 -Dopengl=true
zig build run-egl -Degl=true
zig build run-vk10 -Dvulkan=true
zig build run-vk-zig -Dvulkan=true -Dvk-zig-example=true
```

## Upstream coverage

| Upstream directory | Zig port | Requirement |
| --- | --- | --- |
| `callbacks` | `callbacks.zig` | Base |
| `clipboard` | `clipboard.zig` | Base |
| `custom-backend` | `custom_backend.zig` | `-Dwindow-system=custom -Dcustom-backend-header=/absolute/path` |
| `custom_alloc` | `custom_alloc.zig` | `-Dcustom-allocator=true` |
| `dx11` | `dx11.zig` | Windows and `-Ddirectx=true` |
| `egl` | `egl.zig` | `-Degl=true` |
| `event_queue` | `event_queue.zig` | Base |
| `first-person-camera` | `first_person_camera.zig` | `-Dopengl=true` |
| `flags` | `flags.zig` | Base |
| `flash` | `flash.zig` | Base |
| `gamma` | `gamma.zig` | `-Dopengl=true` |
| `gears` | `gears.zig` | `-Dopengl=true` |
| `gl11` | `gl11.zig` | `-Dopengl=true` |
| `gl33` | `gl33.zig` | `-Dopengl=true` |
| `gl33_ctx` | `gl33_ctx.zig` | `-Dopengl=true` |
| `gles2` | `gles2.zig` | `-Degl=true` |
| `metal` | `metal.zig` | macOS |
| `microui_demo` | `microui_demo.zig` | Base/software surface |
| `minimal_links` | `minimal_links.zig` | Base |
| `monitor` | `monitor.zig` | Base |
| `mouse_icons` | `mouse_icons.zig` | Base |
| `multi-window` | `multi_window.zig` | Base |
| `nostl` | `nostl.zig` | Base |
| `osmesa_demo` | `osmesa_demo.zig` | Base/software surface |
| `portableGL` | `portable_gl.zig` | Base/software surface |
| `smooth-resize` | `smooth_resize.zig` | `-Dopengl=true` |
| `srgb` | `srgb.zig` | `-Dopengl=true` |
| `standard-mouse-icons` | `standard_mouse_icons.zig` | Base |
| `state-checking` | `state_checking.zig` | Base |
| `surface` | `surface.zig` | Base |
| `vk10` | `vk10.zig` | `-Dvulkan=true` |
| `window_icons` | `window_icons.zig` | Base |
| WebGPU integration | `webgpu.zig` | `-Dwebgpu=true -Dwebgpu-library=<provider>` |

`basic.zig` is an additional compact introduction for this package.
`vk_zig.zig` is an additional optional ownership-integration example enabled with
`-Dvulkan=true -Dvk-zig-example=true`.

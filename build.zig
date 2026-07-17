const std = @import("std");

const upstream_url = "https://github.com/ColleagueRiley/RGFW.git";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const window_system = b.option(
        WindowSystem,
        "window-system",
        "Native window system (cocoa, win32, x11, wayland, custom)",
    ) orelse WindowSystem.default(target.result.os.tag);
    const custom_backend_header = b.option(
        []const u8,
        "custom-backend-header",
        "Absolute path to an RGFW custom-backend header",
    );
    const custom_backend_link_platform_libraries = b.option(
        bool,
        "custom-backend-link-platform-libraries",
        "Link the target's default platform libraries for an adapter backend",
    ) orelse false;
    window_system.validate(target.result.os.tag, custom_backend_header != null);
    const opengl = b.option(bool, "opengl", "Enable RGFW's OpenGL helpers") orelse false;
    const egl = b.option(bool, "egl", "Enable RGFW's EGL helpers") orelse false;
    const egl_enabled = egl or (window_system == .wayland and opengl);
    const vulkan = b.option(bool, "vulkan", "Enable RGFW's Vulkan helpers") orelse false;
    const directx = b.option(bool, "directx", "Enable RGFW's DirectX helper") orelse false;
    if (directx and target.result.os.tag != .windows) {
        @panic("RGFW DirectX support requires a Windows target");
    }
    const webgpu = b.option(bool, "webgpu", "Enable RGFW's WebGPU surface helper") orelse false;
    const webgpu_library = b.option(
        []const u8,
        "webgpu-library",
        "System WebGPU library to link when WebGPU support is enabled",
    );
    const custom_allocator = b.option(
        bool,
        "custom-allocator",
        "Route RGFW allocations through rgfw.AllocatorHooks",
    ) orelse false;
    const rgfw_debug = b.option(bool, "rgfw-debug", "Enable RGFW debug messages") orelse false;
    const vk_zig_example = b.option(
        bool,
        "vk-zig-example",
        "Build the optional vk-zig ownership integration example",
    ) orelse false;
    const vulkan_headers = if (vulkan) b.dependency("vulkan_headers", .{}) else null;
    const vulkan_include = if (vulkan_headers) |dependency| dependency.path("include") else null;
    const egl_headers = if (egl_enabled) b.dependency("egl_headers", .{}) else null;
    const egl_include = if (egl_headers) |dependency| dependency.path("api") else null;
    const webgpu_headers = if (webgpu) b.dependency("webgpu_headers", .{}) else null;
    const webgpu_include = if (webgpu_headers) |dependency| dependency.path("") else null;

    const features: Features = .{
        .opengl = opengl,
        .egl = egl_enabled,
        .vulkan = vulkan,
        .directx = directx,
        .webgpu = webgpu,
        .webgpu_library = webgpu_library,
        .custom_allocator = custom_allocator,
        .custom_backend_header = custom_backend_header,
        .custom_backend_link_platform_libraries = custom_backend_link_platform_libraries,
        .rgfw_debug = rgfw_debug,
        .window_system = window_system,
    };
    const wayland = if (window_system == .wayland) generateWaylandProtocols(b) else null;
    const cleaner = addBindingCleaner(b);

    const translate_c = addTranslateC(
        b,
        target,
        optimize,
        b.path("src/rgfw_translate.h"),
        b.path("vendor"),
        vulkan_include,
        egl_include,
        webgpu_include,
        features,
    );
    const clean_bindings = cleanBindings(b, cleaner, translate_c.getOutput(), "rgfw_raw.zig");

    const rgfw_raw = b.addModule("rgfw-raw", .{
        .root_source_file = clean_bindings,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureModule(
        b,
        rgfw_raw,
        target,
        vulkan_include,
        egl_include,
        webgpu_include,
        wayland,
        features,
    );

    const build_options = b.addOptions();
    build_options.addOption(bool, "opengl", features.opengl);
    build_options.addOption(bool, "egl", features.egl);
    build_options.addOption(bool, "vulkan", features.vulkan);
    build_options.addOption(bool, "directx", features.directx);
    build_options.addOption(bool, "webgpu", features.webgpu);
    build_options.addOption(bool, "custom_allocator", features.custom_allocator);
    build_options.addOption(bool, "rgfw_debug", features.rgfw_debug);
    build_options.addOption(WindowSystem, "window_system", features.window_system);

    const rgfw = b.addModule("rgfw", .{
        .root_source_file = b.path("src/rgfw.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "rgfw_raw", .module = rgfw_raw },
            .{ .name = "rgfw_build_options", .module = build_options.createModule() },
        },
    });

    addBindingsStep(b, clean_bindings);
    addTestStep(b, target, optimize, rgfw, features);
    addExampleSteps(b, target, optimize, rgfw, features, vk_zig_example);
    addUpdateStep(
        b,
        cleaner,
        target,
        optimize,
        vulkan_include,
        egl_include,
        webgpu_include,
        features,
    );
}

const Features = struct {
    opengl: bool,
    egl: bool,
    vulkan: bool,
    directx: bool,
    webgpu: bool,
    webgpu_library: ?[]const u8,
    custom_allocator: bool,
    custom_backend_header: ?[]const u8,
    custom_backend_link_platform_libraries: bool,
    rgfw_debug: bool,
    window_system: WindowSystem,
};

const WindowSystem = enum {
    cocoa,
    win32,
    x11,
    wayland,
    custom,

    fn default(os_tag: std.Target.Os.Tag) WindowSystem {
        return switch (os_tag) {
            .macos => .cocoa,
            .windows => .win32,
            .linux, .freebsd, .netbsd, .openbsd, .dragonfly => .x11,
            else => @panic("RGFW does not support this target operating system"),
        };
    }

    fn validate(
        window_system: WindowSystem,
        os_tag: std.Target.Os.Tag,
        has_custom_backend_header: bool,
    ) void {
        if (window_system == .custom and !has_custom_backend_header) {
            @panic("the custom window system requires -Dcustom-backend-header=/absolute/path");
        }
        if (window_system != .custom and has_custom_backend_header) {
            @panic("-Dcustom-backend-header requires -Dwindow-system=custom");
        }
        switch (window_system) {
            .cocoa => if (os_tag != .macos) {
                @panic("the cocoa window system requires a macOS target");
            },
            .win32 => if (os_tag != .windows) {
                @panic("the win32 window system requires a Windows target");
            },
            .x11 => switch (os_tag) {
                .linux, .freebsd, .netbsd, .openbsd, .dragonfly => {},
                else => @panic("the x11 window system requires a Unix target"),
            },
            .wayland => if (os_tag != .linux) {
                @panic("the wayland window system currently requires a Linux target");
            },
            .custom => {},
        }
    }
};

const WaylandProtocols = struct {
    directory: std.Build.LazyPath,
    sources: []const []const u8,
};

fn addTranslateC(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    header: std.Build.LazyPath,
    rgfw_include: std.Build.LazyPath,
    vulkan_include: ?std.Build.LazyPath,
    egl_include: ?std.Build.LazyPath,
    webgpu_include: ?std.Build.LazyPath,
    features: Features,
) *std.Build.Step.TranslateC {
    const translate_c = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(rgfw_include);
    if (vulkan_include) |include| translate_c.addIncludePath(include);
    if (egl_include) |include| translate_c.addIncludePath(include);
    if (webgpu_include) |include| translate_c.addIncludePath(include);
    addTranslatePlatformMacros(translate_c, features.window_system);
    addTranslateMacros(translate_c, features);
    return translate_c;
}

fn addTranslatePlatformMacros(
    translate_c: *std.Build.Step.TranslateC,
    window_system: WindowSystem,
) void {
    // translate-c currently evaluates host platform macros while parsing some
    // headers, so make RGFW's platform selection unambiguous for cross builds.
    translate_c.defineCMacro("RGFW_CUSTOM_BACKEND", null);
    switch (window_system) {
        .cocoa => translate_c.defineCMacro("RGFW_MACOS", null),
        .win32 => translate_c.defineCMacro("RGFW_WINDOWS", null),
        .x11 => {
            translate_c.defineCMacro("RGFW_X11", null);
            translate_c.defineCMacro("RGFW_UNIX", null);
        },
        .wayland => {
            translate_c.defineCMacro("RGFW_WAYLAND", null);
            translate_c.defineCMacro("RGFW_NO_X11", null);
        },
        .custom => {},
    }
}

fn addTranslateMacros(translate_c: *std.Build.Step.TranslateC, features: Features) void {
    if (features.opengl) translate_c.defineCMacro("RGFW_OPENGL", null);
    if (features.egl) translate_c.defineCMacro("RGFW_EGL", null);
    if (features.vulkan) translate_c.defineCMacro("RGFW_VULKAN", null);
    // Windows SDK COM headers currently produce unsupported translate-c
    // declarations. The idiomatic DirectX wrapper uses the stable pointer ABI
    // directly, while RGFW's C implementation still receives RGFW_DIRECTX.
    if (features.webgpu) translate_c.defineCMacro("RGFW_WEBGPU", null);
    if (features.rgfw_debug) translate_c.defineCMacro("RGFW_DEBUG", null);
    if (features.custom_backend_header) |header| {
        translate_c.defineCMacro(
            "RGFW_ZIG_CUSTOM_BACKEND_HEADER",
            translate_c.step.owner.fmt("\"{s}\"", .{header}),
        );
    }
}

fn addBindingCleaner(b: *std.Build) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "clean-rgfw-bindings",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/clean_bindings.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
}

fn cleanBindings(
    b: *std.Build,
    cleaner: *std.Build.Step.Compile,
    input: std.Build.LazyPath,
    output_name: []const u8,
) std.Build.LazyPath {
    const run_cleaner = b.addRunArtifact(cleaner);
    run_cleaner.addFileArg(input);
    return run_cleaner.addOutputFileArg(output_name);
}

fn configureModule(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    vulkan_include: ?std.Build.LazyPath,
    egl_include: ?std.Build.LazyPath,
    webgpu_include: ?std.Build.LazyPath,
    wayland: ?WaylandProtocols,
    features: Features,
) void {
    module.addIncludePath(b.path("vendor"));
    if (vulkan_include) |include| module.addIncludePath(include);
    if (egl_include) |include| module.addIncludePath(include);
    if (webgpu_include) |include| module.addIncludePath(include);
    if (wayland) |generated| module.addIncludePath(generated.directory);
    module.addCSourceFile(.{
        .file = b.path("src/rgfw.c"),
        .flags = &.{"-std=c99"},
    });
    if (features.custom_allocator) {
        module.addCSourceFile(.{
            .file = b.path("src/allocator_shim.c"),
            .flags = &.{"-std=c99"},
        });
        module.addCMacro("RGFW_ZIG_CUSTOM_ALLOCATOR", "1");
    }
    if (features.custom_backend_header) |header| {
        module.addCMacro(
            "RGFW_ZIG_CUSTOM_BACKEND_HEADER",
            b.fmt("\"{s}\"", .{header}),
        );
    }
    module.addCMacro("RGFW_IMPLEMENTATION", "1");
    module.addCMacro("RGFW_EXPORT", "1");
    addModulePlatformMacros(module, features.window_system);
    if (features.opengl) module.addCMacro("RGFW_OPENGL", "1");
    if (features.egl) module.addCMacro("RGFW_EGL", "1");
    if (features.vulkan) module.addCMacro("RGFW_VULKAN", "1");
    if (features.directx) module.addCMacro("RGFW_DIRECTX", "1");
    if (features.webgpu) {
        module.addCMacro("RGFW_WEBGPU", "1");
        if (features.webgpu_library) |library| {
            module.linkSystemLibrary(library, .{});
        }
    }
    if (features.rgfw_debug) module.addCMacro("RGFW_DEBUG", "1");

    if (wayland) |generated| {
        for (generated.sources) |source| {
            module.addCSourceFile(.{
                .file = generated.directory.path(b, source),
                .flags = &.{"-std=c99"},
            });
        }
    }

    linkPlatformLibraries(module, target.result.os.tag, features);
}

fn addModulePlatformMacros(module: *std.Build.Module, window_system: WindowSystem) void {
    switch (window_system) {
        .cocoa => module.addCMacro("RGFW_MACOS", "1"),
        .win32 => module.addCMacro("RGFW_WINDOWS", "1"),
        .x11 => {
            module.addCMacro("RGFW_X11", "1");
            module.addCMacro("RGFW_UNIX", "1");
        },
        .wayland => {
            module.addCMacro("RGFW_WAYLAND", "1");
            module.addCMacro("RGFW_NO_X11", "1");
        },
        .custom => {},
    }
}

fn linkPlatformLibraries(
    module: *std.Build.Module,
    os_tag: std.Target.Os.Tag,
    features: Features,
) void {
    if (features.window_system == .custom and
        !features.custom_backend_link_platform_libraries) return;
    switch (os_tag) {
        .macos => {
            module.linkFramework("Cocoa", .{});
            module.linkFramework("CoreVideo", .{});
            module.linkFramework("IOKit", .{});
            if (features.opengl) module.linkFramework("OpenGL", .{});
        },
        .windows => {
            module.linkSystemLibrary("gdi32", .{});
            module.linkSystemLibrary("shell32", .{});
            module.linkSystemLibrary("user32", .{});
            module.linkSystemLibrary("advapi32", .{});
            if (features.opengl) module.linkSystemLibrary("opengl32", .{});
        },
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly => {
            switch (features.window_system) {
                .x11 => {
                    module.linkSystemLibrary("X11", .{});
                    module.linkSystemLibrary("Xrandr", .{});
                },
                .wayland => {
                    module.linkSystemLibrary("wayland-client", .{});
                    module.linkSystemLibrary("wayland-cursor", .{});
                    module.linkSystemLibrary("xkbcommon", .{});
                },
                .custom => return,
                else => unreachable,
            }
            module.linkSystemLibrary("dl", .{});
            module.linkSystemLibrary("pthread", .{});
            module.linkSystemLibrary("m", .{});
            if (features.opengl) module.linkSystemLibrary("GL", .{});
        },
        else => if (features.window_system != .custom) {
            @panic("RGFW currently supports macOS, Windows, Unix, and custom backends");
        },
    }
}

fn generateWaylandProtocols(b: *std.Build) WaylandProtocols {
    const upstream = b.dependency("rgfw_upstream", .{});
    const protocols = [_][]const u8{
        "xdg-shell",
        "xdg-toplevel-icon-v1",
        "xdg-decoration-unstable-v1",
        "relative-pointer-unstable-v1",
        "pointer-constraints-unstable-v1",
        "xdg-output-unstable-v1",
        "pointer-warp-v1",
    };

    const generate = b.addSystemCommand(&.{
        "sh",
        "-eu",
        "-c",
        \\input="$1"
        \\output="$2"
        \\mkdir -p "$output"
        \\shift 2
        \\for protocol in "$@"; do
        \\  wayland-scanner client-header "$input/$protocol.xml" "$output/$protocol.h"
        \\  wayland-scanner public-code "$input/$protocol.xml" "$output/$protocol.c"
        \\done
        ,
        "generate-rgfw-wayland",
    });
    generate.addDirectoryArg(upstream.path("wayland"));
    const output = generate.addOutputDirectoryArg("rgfw-wayland");
    generate.addArgs(&protocols);

    const sources = b.allocator.alloc([]const u8, protocols.len) catch @panic("out of memory");
    for (protocols, 0..) |protocol, index| {
        sources[index] = b.fmt("{s}.c", .{protocol});
    }
    return .{ .directory = output, .sources = sources };
}

fn addBindingsStep(b: *std.Build, bindings: std.Build.LazyPath) void {
    const install_bindings = b.addInstallFile(bindings, "bindings/rgfw.zig");
    const bindings_step = b.step(
        "bindings",
        "Generate target-specific Zig bindings in zig-out/bindings",
    );
    bindings_step.dependOn(&install_bindings.step);
    b.getInstallStep().dependOn(&install_bindings.step);
}

fn addTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    rgfw: *std.Build.Module,
    features: Features,
) void {
    const foreign_vulkan_handles = b.createModule(.{
        .root_source_file = b.path("tests/foreign_vulkan_handles.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/smoke.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rgfw", .module = rgfw },
                .{ .name = "foreign_vulkan_handles", .module = foreign_vulkan_handles },
            },
        }),
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Build and run the binding tests");
    test_step.dependOn(&run_tests.step);

    const cleaner_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/clean_bindings.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const run_cleaner_tests = b.addRunArtifact(cleaner_tests);
    test_step.dependOn(&run_cleaner_tests.step);

    addCompileFailureTest(
        b,
        test_step,
        target,
        optimize,
        rgfw,
        "tests/compile_fail/wrong_event_handler.zig",
        "event handler must have type `fn (rgfw.Size) void`",
    );
    addCompileFailureTest(
        b,
        test_step,
        target,
        optimize,
        rgfw,
        "tests/compile_fail/wrong_native_handle.zig",
        b.fmt("native handle kind `{s}` does not match configured window system `{s}`", .{
            switch (features.window_system) {
                .cocoa => "win32",
                else => "cocoa",
            },
            @tagName(features.window_system),
        }),
    );
    if (features.vulkan) {
        addCompileFailureTest(
            b,
            test_step,
            target,
            optimize,
            rgfw,
            "tests/compile_fail/incompatible_vulkan_handle.zig",
            "foreign Vulkan instance type `u8` is not ABI-compatible with `?*rgfw_raw.struct_VkInstance_T`",
        );
    } else {
        addCompileFailureTest(
            b,
            test_step,
            target,
            optimize,
            rgfw,
            "tests/compile_fail/vulkan_backend_disabled.zig",
            "RGFW Vulkan support is disabled; pass `.vulkan = true` to the dependency",
        );
    }
    if (!features.directx) {
        addCompileFailureTest(
            b,
            test_step,
            target,
            optimize,
            rgfw,
            "tests/compile_fail/directx_disabled.zig",
            "RGFW DirectX support is disabled; build for Windows with -Ddirectx=true",
        );
    }
    if (!features.webgpu) {
        addCompileFailureTest(
            b,
            test_step,
            target,
            optimize,
            rgfw,
            "tests/compile_fail/webgpu_disabled.zig",
            "RGFW WebGPU support is disabled; build with -Dwebgpu=true",
        );
    }
}

fn addCompileFailureTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    rgfw: *std.Build.Module,
    source_path: []const u8,
    expected_error: []const u8,
) void {
    const compile = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(source_path),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "rgfw", .module = rgfw }},
        }),
    });
    compile.expect_errors = .{ .contains = expected_error };
    test_step.dependOn(&compile.step);
}

fn addExampleSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    rgfw: *std.Build.Module,
    features: Features,
    vk_zig_example: bool,
) void {
    const examples_step = b.step("examples", "Build every enabled RGFW example");
    if (features.webgpu) {
        const webgpu_check = b.addObject(.{
            .name = "rgfw-webgpu-interop-check",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/webgpu.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "rgfw", .module = rgfw }},
            }),
        });
        examples_step.dependOn(&webgpu_check.step);
    }
    for (examples) |example| {
        // RGFW's C object references the provider whenever WebGPU is enabled.
        // Without a provider, the compile-only interop check above is the
        // complete examples step; linked examples would correctly be unresolved.
        if (features.webgpu and features.webgpu_library == null) continue;
        if (!example.enabled(target.result.os.tag, features)) continue;
        if (example.requirement == .vk_zig and !vk_zig_example) continue;

        const vk_zig = if (example.requirement == .vk_zig)
            b.dependency("vulkan", .{
                .target = target,
                .optimize = optimize,
                .platform = switch (features.window_system) {
                    .cocoa => "metal",
                    .win32 => "win32",
                    .x11 => "xlib",
                    .wayland => "wayland",
                    .custom => @panic("the vk-zig example does not define a custom platform"),
                },
            })
        else
            null;

        const executable = b.addExecutable(.{
            .name = b.fmt("rgfw-{s}", .{example.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .imports = if (vk_zig) |dependency|
                    &.{
                        .{ .name = "rgfw", .module = rgfw },
                        .{ .name = "vulkan", .module = dependency.module("vulkan") },
                    }
                else
                    &.{.{ .name = "rgfw", .module = rgfw }},
            }),
        });
        const install = b.addInstallArtifact(executable, .{});
        examples_step.dependOn(&install.step);

        const run = b.addRunArtifact(executable);
        const run_step = b.step(
            b.fmt("run-{s}", .{example.name}),
            b.fmt("Run the {s} RGFW example", .{example.name}),
        );
        run_step.dependOn(&run.step);

        if (std.mem.eql(u8, example.name, "basic")) {
            const basic_step = b.step("example", "Build the basic RGFW example");
            basic_step.dependOn(&install.step);
            const run_basic_step = b.step("run-example", "Run the basic RGFW example");
            run_basic_step.dependOn(&run.step);
        }
    }
}

const Example = struct {
    name: []const u8,
    path: []const u8,
    requirement: Requirement = .base,

    const Requirement = enum {
        base,
        opengl,
        egl,
        vulkan,
        vk_zig,
        custom_allocator,
        custom_backend,
        directx,
        webgpu,
        macos,
        windows,
    };

    fn enabled(example: Example, os_tag: std.Target.Os.Tag, features: Features) bool {
        return switch (example.requirement) {
            .base => true,
            .opengl => features.opengl,
            .egl => features.egl,
            .vulkan => features.vulkan,
            .vk_zig => features.vulkan,
            .custom_allocator => features.custom_allocator,
            .custom_backend => features.custom_backend_header != null,
            .directx => features.directx,
            .webgpu => features.webgpu and features.webgpu_library != null,
            .macos => os_tag == .macos and features.window_system == .cocoa,
            .windows => os_tag == .windows and features.window_system == .win32,
        };
    }
};

const examples = [_]Example{
    .{
        .name = "basic",
        .path = "examples/basic.zig",
    },
    .{
        .name = "callbacks",
        .path = "examples/callbacks.zig",
    },
    .{
        .name = "clipboard",
        .path = "examples/clipboard.zig",
    },
    .{
        .name = "custom-alloc",
        .path = "examples/custom_alloc.zig",
        .requirement = .custom_allocator,
    },
    .{
        .name = "custom-backend",
        .path = "examples/custom_backend.zig",
        .requirement = .custom_backend,
    },
    .{
        .name = "event-queue",
        .path = "examples/event_queue.zig",
    },
    .{
        .name = "flags",
        .path = "examples/flags.zig",
    },
    .{
        .name = "flash",
        .path = "examples/flash.zig",
    },
    .{
        .name = "minimal-links",
        .path = "examples/minimal_links.zig",
    },
    .{
        .name = "monitor",
        .path = "examples/monitor.zig",
    },
    .{
        .name = "mouse-icons",
        .path = "examples/mouse_icons.zig",
    },
    .{
        .name = "multi-window",
        .path = "examples/multi_window.zig",
    },
    .{
        .name = "nostl",
        .path = "examples/nostl.zig",
    },
    .{
        .name = "osmesa-demo",
        .path = "examples/osmesa_demo.zig",
    },
    .{
        .name = "portable-gl",
        .path = "examples/portable_gl.zig",
    },
    .{
        .name = "microui-demo",
        .path = "examples/microui_demo.zig",
    },
    .{
        .name = "standard-mouse-icons",
        .path = "examples/standard_mouse_icons.zig",
    },
    .{
        .name = "state-checking",
        .path = "examples/state_checking.zig",
    },
    .{
        .name = "surface",
        .path = "examples/surface.zig",
    },
    .{
        .name = "window-icons",
        .path = "examples/window_icons.zig",
    },
    .{
        .name = "metal",
        .path = "examples/metal.zig",
        .requirement = .macos,
    },
    .{
        .name = "dx11",
        .path = "examples/dx11.zig",
        .requirement = .directx,
    },
    .{
        .name = "webgpu",
        .path = "examples/webgpu.zig",
        .requirement = .webgpu,
    },
    .{
        .name = "first-person-camera",
        .path = "examples/first_person_camera.zig",
        .requirement = .opengl,
    },
    .{
        .name = "gamma",
        .path = "examples/gamma.zig",
        .requirement = .opengl,
    },
    .{
        .name = "gears",
        .path = "examples/gears.zig",
        .requirement = .opengl,
    },
    .{
        .name = "gl11",
        .path = "examples/gl11.zig",
        .requirement = .opengl,
    },
    .{
        .name = "gl33",
        .path = "examples/gl33.zig",
        .requirement = .opengl,
    },
    .{
        .name = "gl33-ctx",
        .path = "examples/gl33_ctx.zig",
        .requirement = .opengl,
    },
    .{
        .name = "smooth-resize",
        .path = "examples/smooth_resize.zig",
        .requirement = .opengl,
    },
    .{
        .name = "srgb",
        .path = "examples/srgb.zig",
        .requirement = .opengl,
    },
    .{
        .name = "egl",
        .path = "examples/egl.zig",
        .requirement = .egl,
    },
    .{
        .name = "gles2",
        .path = "examples/gles2.zig",
        .requirement = .egl,
    },
    .{
        .name = "vk10",
        .path = "examples/vk10.zig",
        .requirement = .vulkan,
    },
    .{
        .name = "vk-zig",
        .path = "examples/vk_zig.zig",
        .requirement = .vk_zig,
    },
};

fn addUpdateStep(
    b: *std.Build,
    cleaner: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_include: ?std.Build.LazyPath,
    egl_include: ?std.Build.LazyPath,
    webgpu_include: ?std.Build.LazyPath,
    features: Features,
) void {
    const upstream_ref = b.option(
        []const u8,
        "rgfw-ref",
        "Git branch or tag to vendor (default: main)",
    ) orelse "main";

    const clone = b.addSystemCommand(&.{
        "git",
        "clone",
        "--quiet",
        "--depth",
        "1",
        "--branch",
        upstream_ref,
        upstream_url,
    });
    const checkout = clone.addOutputDirectoryArg("rgfw-upstream");

    const apply_local_patches = b.addSystemCommand(&.{ "git", "-C" });
    apply_local_patches.addDirectoryArg(checkout);
    apply_local_patches.addArgs(&.{ "apply", "-" });
    apply_local_patches.setStdIn(.{
        .lazy_path = b.path("patches/rgfw-monitor-fixes.patch"),
    });

    const revision = b.addSystemCommand(&.{ "git", "-C" });
    revision.addDirectoryArg(checkout);
    revision.addArgs(&.{ "rev-parse", "HEAD" });
    const revision_file = revision.captureStdOut(.{});

    const verify_translate = addTranslateC(
        b,
        target,
        optimize,
        b.path("src/rgfw_translate.h"),
        checkout,
        vulkan_include,
        egl_include,
        webgpu_include,
        features,
    );
    const clean_bindings = cleanBindings(
        b,
        cleaner,
        verify_translate.getOutput(),
        "rgfw_updated_raw.zig",
    );
    const verify = b.addCheckFile(clean_bindings, .{
        .expected_matches = &.{
            "pub extern fn RGFW_init",
            "pub extern fn RGFW_createWindow",
        },
    });
    verify.step.dependOn(&apply_local_patches.step);

    const update_files = b.addUpdateSourceFiles();
    update_files.addCopyFileToSource(checkout.path(b, "RGFW.h"), "vendor/RGFW.h");
    update_files.addCopyFileToSource(checkout.path(b, "LICENSE"), "vendor/LICENSE");
    update_files.addCopyFileToSource(revision_file, "vendor/RGFW_COMMIT");
    update_files.step.dependOn(&verify.step);
    update_files.step.dependOn(&apply_local_patches.step);

    const update_step = b.step(
        "update",
        "Pull RGFW, verify translation, and refresh vendored sources",
    );
    update_step.dependOn(&update_files.step);
}

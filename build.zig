const std = @import("std");

const upstream_url = "https://github.com/ColleagueRiley/RGFW.git";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opengl = b.option(bool, "opengl", "Enable RGFW's OpenGL helpers") orelse false;
    const egl = b.option(bool, "egl", "Enable RGFW's EGL helpers") orelse false;
    const vulkan = b.option(bool, "vulkan", "Enable RGFW's Vulkan helpers") orelse false;
    const rgfw_debug = b.option(bool, "rgfw-debug", "Enable RGFW debug messages") orelse false;
    const vulkan_headers = if (vulkan) b.lazyDependency("vulkan_headers", .{}) else null;
    const vulkan_include = if (vulkan_headers) |dependency| dependency.path("include") else null;
    const egl_headers = if (egl) b.lazyDependency("egl_headers", .{}) else null;
    const egl_include = if (egl_headers) |dependency| dependency.path("api") else null;

    const features: Features = .{
        .opengl = opengl,
        .egl = egl,
        .vulkan = vulkan,
        .rgfw_debug = rgfw_debug,
    };
    const cleaner = addBindingCleaner(b);

    const translate_c = addTranslateC(
        b,
        target,
        optimize,
        b.path("src/rgfw_translate.h"),
        b.path("vendor"),
        vulkan_include,
        egl_include,
        features,
    );
    const clean_bindings = cleanBindings(b, cleaner, translate_c.getOutput(), "rgfw_raw.zig");

    const rgfw_raw = b.addModule("rgfw-raw", .{
        .root_source_file = clean_bindings,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureModule(b, rgfw_raw, target, vulkan_include, egl_include, features);

    const build_options = b.addOptions();
    build_options.addOption(bool, "opengl", features.opengl);
    build_options.addOption(bool, "egl", features.egl);
    build_options.addOption(bool, "vulkan", features.vulkan);
    build_options.addOption(bool, "rgfw_debug", features.rgfw_debug);

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
    addTestStep(b, target, optimize, rgfw);
    addExampleSteps(b, target, optimize, rgfw, features);
    addUpdateStep(b, cleaner, target, optimize, vulkan_include, egl_include, features);
}

const Features = struct {
    opengl: bool,
    egl: bool,
    vulkan: bool,
    rgfw_debug: bool,
};

fn addTranslateC(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    header: std.Build.LazyPath,
    rgfw_include: std.Build.LazyPath,
    vulkan_include: ?std.Build.LazyPath,
    egl_include: ?std.Build.LazyPath,
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
    addTranslatePlatformMacros(translate_c, target.result.os.tag);
    addTranslateMacros(translate_c, features);
    return translate_c;
}

fn addTranslatePlatformMacros(
    translate_c: *std.Build.Step.TranslateC,
    os_tag: std.Target.Os.Tag,
) void {
    // translate-c currently evaluates host platform macros while parsing some
    // headers, so make RGFW's platform selection unambiguous for cross builds.
    translate_c.defineCMacro("RGFW_CUSTOM_BACKEND", null);
    switch (os_tag) {
        .macos => translate_c.defineCMacro("RGFW_MACOS", null),
        .windows => translate_c.defineCMacro("RGFW_WINDOWS", null),
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly => {
            translate_c.defineCMacro("RGFW_X11", null);
            translate_c.defineCMacro("RGFW_UNIX", null);
        },
        else => @panic("RGFW currently supports macOS, Windows, and X11 targets"),
    }
}

fn addTranslateMacros(translate_c: *std.Build.Step.TranslateC, features: Features) void {
    if (features.opengl) translate_c.defineCMacro("RGFW_OPENGL", null);
    if (features.egl) translate_c.defineCMacro("RGFW_EGL", null);
    if (features.vulkan) translate_c.defineCMacro("RGFW_VULKAN", null);
    if (features.rgfw_debug) translate_c.defineCMacro("RGFW_DEBUG", null);
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
    features: Features,
) void {
    module.addIncludePath(b.path("vendor"));
    if (vulkan_include) |include| module.addIncludePath(include);
    if (egl_include) |include| module.addIncludePath(include);
    module.addCSourceFile(.{
        .file = b.path("src/rgfw.c"),
        .flags = &.{"-std=c99"},
    });
    module.addCMacro("RGFW_IMPLEMENTATION", "1");
    module.addCMacro("RGFW_EXPORT", "1");
    if (features.opengl) module.addCMacro("RGFW_OPENGL", "1");
    if (features.egl) module.addCMacro("RGFW_EGL", "1");
    if (features.vulkan) module.addCMacro("RGFW_VULKAN", "1");
    if (features.rgfw_debug) module.addCMacro("RGFW_DEBUG", "1");

    linkPlatformLibraries(module, target.result.os.tag, features);
}

fn linkPlatformLibraries(
    module: *std.Build.Module,
    os_tag: std.Target.Os.Tag,
    features: Features,
) void {
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
            module.linkSystemLibrary("X11", .{});
            module.linkSystemLibrary("Xrandr", .{});
            module.linkSystemLibrary("dl", .{});
            module.linkSystemLibrary("pthread", .{});
            module.linkSystemLibrary("m", .{});
            if (features.opengl) module.linkSystemLibrary("GL", .{});
        },
        else => @panic("RGFW currently supports macOS, Windows, and X11 targets"),
    }
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
}

fn addExampleSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    rgfw: *std.Build.Module,
    features: Features,
) void {
    const examples_step = b.step("examples", "Build every enabled RGFW example");
    for (examples) |example| {
        if (!example.enabled(target.result.os.tag, features)) continue;

        const executable = b.addExecutable(.{
            .name = b.fmt("rgfw-{s}", .{example.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "rgfw", .module = rgfw }},
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
        macos,
        windows,
    };

    fn enabled(example: Example, os_tag: std.Target.Os.Tag, features: Features) bool {
        return switch (example.requirement) {
            .base => true,
            .opengl => features.opengl,
            .egl => features.egl,
            .vulkan => features.vulkan,
            .macos => os_tag == .macos,
            .windows => os_tag == .windows,
        };
    }
};

const examples = [_]Example{
    .{ .name = "basic", .path = "examples/basic.zig" },
    .{ .name = "callbacks", .path = "examples/callbacks.zig" },
    .{ .name = "clipboard", .path = "examples/clipboard.zig" },
    .{ .name = "custom-alloc", .path = "examples/custom_alloc.zig" },
    .{ .name = "custom-backend", .path = "examples/custom_backend.zig" },
    .{ .name = "event-queue", .path = "examples/event_queue.zig" },
    .{ .name = "flags", .path = "examples/flags.zig" },
    .{ .name = "flash", .path = "examples/flash.zig" },
    .{ .name = "minimal-links", .path = "examples/minimal_links.zig" },
    .{ .name = "monitor", .path = "examples/monitor.zig" },
    .{ .name = "mouse-icons", .path = "examples/mouse_icons.zig" },
    .{ .name = "multi-window", .path = "examples/multi_window.zig" },
    .{ .name = "nostl", .path = "examples/nostl.zig" },
    .{ .name = "osmesa-demo", .path = "examples/osmesa_demo.zig" },
    .{ .name = "portable-gl", .path = "examples/portable_gl.zig" },
    .{ .name = "microui-demo", .path = "examples/microui_demo.zig" },
    .{ .name = "standard-mouse-icons", .path = "examples/standard_mouse_icons.zig" },
    .{ .name = "state-checking", .path = "examples/state_checking.zig" },
    .{ .name = "surface", .path = "examples/surface.zig" },
    .{ .name = "window-icons", .path = "examples/window_icons.zig" },
    .{ .name = "metal", .path = "examples/metal.zig", .requirement = .macos },
    .{ .name = "dx11", .path = "examples/dx11.zig", .requirement = .windows },
    .{
        .name = "first-person-camera",
        .path = "examples/first_person_camera.zig",
        .requirement = .opengl,
    },
    .{ .name = "gamma", .path = "examples/gamma.zig", .requirement = .opengl },
    .{ .name = "gears", .path = "examples/gears.zig", .requirement = .opengl },
    .{ .name = "gl11", .path = "examples/gl11.zig", .requirement = .opengl },
    .{ .name = "gl33", .path = "examples/gl33.zig", .requirement = .opengl },
    .{ .name = "gl33-ctx", .path = "examples/gl33_ctx.zig", .requirement = .opengl },
    .{ .name = "smooth-resize", .path = "examples/smooth_resize.zig", .requirement = .opengl },
    .{ .name = "srgb", .path = "examples/srgb.zig", .requirement = .opengl },
    .{ .name = "egl", .path = "examples/egl.zig", .requirement = .egl },
    .{ .name = "gles2", .path = "examples/gles2.zig", .requirement = .egl },
    .{ .name = "vk10", .path = "examples/vk10.zig", .requirement = .vulkan },
};

fn addUpdateStep(
    b: *std.Build,
    cleaner: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_include: ?std.Build.LazyPath,
    egl_include: ?std.Build.LazyPath,
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

    const update_files = b.addUpdateSourceFiles();
    update_files.addCopyFileToSource(checkout.path(b, "RGFW.h"), "vendor/RGFW.h");
    update_files.addCopyFileToSource(checkout.path(b, "LICENSE"), "vendor/LICENSE");
    update_files.addCopyFileToSource(revision_file, "vendor/RGFW_COMMIT");
    update_files.step.dependOn(&verify.step);

    const update_step = b.step(
        "update",
        "Pull RGFW, verify translation, and refresh vendored sources",
    );
    update_step.dependOn(&update_files.step);
}

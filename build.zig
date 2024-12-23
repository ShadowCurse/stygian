const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    const software_render = b.option(bool, "software_render", "Use software renderer") orelse false;
    options.addOption(
        bool,
        "software_render",
        software_render,
    );
    options.addOption(
        bool,
        "vulkan_render",
        b.option(bool, "vulkan_render", "Use Vulkan renderer") orelse
            if (software_render) false else true,
    );
    const options_module = options.createModule();

    if (b.option(bool, "compile_shaders", "Compile shaders")) |_| {
        const shader_step = compile_shaders(b);
        b.default_step.dependOn(shader_step);
    }

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();

    const platform = b.addExecutable(.{
        .name = "stygian_platform",
        .root_source_file = b.path("src/platform_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform.root_module.addImport("build_options", options_module);
    platform.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
    platform.linkSystemLibrary("SDL2");
    platform.linkLibC();
    b.installArtifact(platform);

    const runtime = b.addSharedLibrary(.{
        .name = "stygian_runtime",
        .root_source_file = b.path("src/runtime_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime.root_module.addImport("build_options", options_module);
    runtime.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
    runtime.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });

    runtime.addIncludePath(b.path("thirdparty/vma"));
    runtime.addIncludePath(b.path("thirdparty/stb"));
    runtime.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp") });
    runtime.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb_image.c") });

    runtime.linkSystemLibrary("SDL2");
    runtime.linkSystemLibrary("vulkan");
    runtime.linkLibCpp();
    b.installArtifact(runtime);

    const run_cmd = b.addRunArtifact(platform);

    if (b.option(bool, "X11", "Use X11 backend") == null) {
        run_cmd.setEnvironmentVariable("SDL_VIDEODRIVER", "wayland");
    }

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn compile_shaders(b: *std.Build) *std.Build.Step {
    const shader_step = b.step("shaders", "Shader compilation");

    const shaders_dir = b.build_root.handle.openDir("shaders", .{ .iterate = true }) catch @panic("cannot open shader dir");

    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("cannot iterate shader dir")) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, ext, ".glsl")) {
                const basename = std.fs.path.basename(entry.name);
                const name = basename[0 .. basename.len - ext.len];

                std.debug.print("build: compiling shader: {s}\n", .{name});

                const shader_type = if (std.mem.endsWith(u8, name, "frag"))
                    "-fshader-stage=fragment"
                else if (std.mem.endsWith(u8, name, "vert"))
                    "-fshader-stage=vertex"
                else
                    unreachable;

                const source_file_path = std.fmt.allocPrint(b.allocator, "shaders/{s}.glsl", .{name}) catch unreachable;
                const output_file_path = std.fmt.allocPrint(b.allocator, "{s}.spv", .{name}) catch unreachable;

                const command = b.addSystemCommand(&.{
                    "glslc",
                    shader_type,
                    source_file_path,
                    "-o",
                    output_file_path,
                });
                shader_step.dependOn(&command.step);
            }
        }
    }
    return shader_step;
}

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
    options.addOption(bool, "software_render", software_render);
    const vulkan_render = b.option(bool, "vulkan_render", "Use Vulkan renderer") orelse
        if (software_render) false else true;
    options.addOption(bool, "vulkan_render", vulkan_render);
    const unibuild = b.option(bool, "unibuild", "Compile as a single binary") orelse
        false;
    options.addOption(bool, "unibuild", unibuild);
    const options_module = options.createModule();

    if (b.option(bool, "compile_shaders", "Compile shaders")) |_| {
        const shader_step = compile_shaders(b);
        b.default_step.dependOn(shader_step);
    }

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();

    const exe = if (unibuild) blk: {
        if (target.result.os.tag == .emscripten and !software_render)
            @panic("Only software_render is supported for emscripten");

        const name = if (target.result.os.tag == .emscripten)
            "stygian_unibuild_software_emscripten"
        else if (software_render)
            "stygian_unibuild_software"
        else
            "stygian_unibuild_vulkan";

        const runtime = if (target.result.os.tag == .emscripten)
            b.addStaticLibrary(.{
                .name = name,
                .root_source_file = b.path("src/platform_main.zig"),
                .target = target,
                .optimize = optimize,
            })
        else
            b.addExecutable(.{
                .name = name,
                .root_source_file = b.path("src/platform_main.zig"),
                .target = target,
                .optimize = optimize,
            });
        runtime.root_module.addImport("build_options", options_module);
        runtime.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
        runtime.addIncludePath(b.path("thirdparty/stb"));
        runtime.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb_image.c") });
        runtime.linkSystemLibrary("SDL2");

        if (target.result.os.tag == .emscripten) {
            const cache_include = std.fs.path.join(
                b.allocator,
                &.{
                    b.sysroot.?,
                    "cache",
                    "sysroot",
                    "include",
                },
            ) catch @panic("Out of memory");
            defer b.allocator.free(cache_include);
            const cache_path = std.Build.LazyPath{ .cwd_relative = cache_include };
            runtime.addIncludePath(cache_path);
        }

        if (vulkan_render) {
            runtime.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });
            runtime.addIncludePath(b.path("thirdparty/vma"));
            runtime.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp") });
            runtime.linkSystemLibrary("vulkan");
            runtime.linkLibCpp();
        } else {
            runtime.linkLibC();
        }

        b.installArtifact(runtime);

        break :blk runtime;
    } else blk: {
        if (target.result.os.tag == .emscripten) {
            @panic("Cannot build platform + runtime bundle for emscripten");
        }

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
        // if (vulkan_render) {
        //     platform.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });
        //     platform.linkSystemLibrary("vulkan");
        // }
        b.installArtifact(platform);

        const runtime_name = if (software_render)
            "stygian_runtime_software"
        else
            "stygian_runtime_vulkan";
        const runtime = b.addSharedLibrary(.{
            .name = runtime_name,
            .root_source_file = b.path("src/runtime_main.zig"),
            .target = target,
            .optimize = optimize,
        });
        runtime.root_module.addImport("build_options", options_module);
        runtime.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
        runtime.addIncludePath(b.path("thirdparty/stb"));
        runtime.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb_image.c") });
        runtime.linkSystemLibrary("SDL2");

        if (vulkan_render) {
            runtime.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });
            runtime.addIncludePath(b.path("thirdparty/vma"));
            runtime.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp") });
            runtime.linkSystemLibrary("vulkan");
            runtime.linkLibCpp();
        } else {
            runtime.linkLibC();
        }

        b.installArtifact(runtime);

        break :blk platform;
    };

    const run_cmd = b.addRunArtifact(exe);
    if (b.option(bool, "X11", "Use X11 backend") == null) {
        run_cmd.setEnvironmentVariable("SDL_VIDEODRIVER", "wayland");
    }
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
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

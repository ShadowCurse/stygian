const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const software_render = b.option(bool, "software_render", "Use software renderer") orelse false;
    const vulkan_render = b.option(bool, "vulkan_render", "Use Vulkan renderer") orelse false;
    const unibuild = b.option(bool, "unibuild", "Compile as a single binary") orelse false;
    const lib_path = b.option([]const u8, "lib_path", "Compile as a single binary") orelse
        "./zig-out/lib/libruntime.so";

    const platform_src_path =
        b.option([]const u8, "platform_src_path", "Path to the platform.zig file") orelse
        "examples/platform.zig";
    const runtime_src_path =
        b.option([]const u8, "runtime_src_path", "Path to the runtime.zig file") orelse
        if (software_render)
        "examples/runtime_software.zig"
    else
        "examples/runtime_vulkan.zig";

    if (software_render and vulkan_render) {
        @panic("Only one of renderer backeds can be selected.");
    }
    if (target.result.os.tag == .emscripten and !unibuild) {
        @panic("Cannot build platform + runtime bundle for emscripten");
    }
    if (target.result.os.tag == .emscripten and !software_render) {
        @panic("Only software_render is supported for emscripten");
    }

    const options = b.addOptions();
    options.addOption(bool, "software_render", software_render);
    options.addOption(bool, "vulkan_render", vulkan_render);
    options.addOption(bool, "unibuild", unibuild);
    options.addOption([]const u8, "lib_path", lib_path);

    if (b.option(bool, "compile_shaders", "Compile shaders")) |_| {
        const shader_step = compile_shaders(b);
        b.default_step.dependOn(shader_step);
    }

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();

    const stygian_platform = b.addModule("stygian_platform", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stygian_platform.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
    stygian_platform.linkSystemLibrary("SDL2", .{});
    stygian_platform.addOptions("build_options", options);
    stygian_platform.link_libc = true;

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
        stygian_platform.addIncludePath(cache_path);
    }

    const stygian_runtime = b.addModule("stygian_runtime", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stygian_runtime.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
    stygian_runtime.addIncludePath(b.path("thirdparty/stb"));
    stygian_runtime.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb_image.c") });
    stygian_runtime.linkSystemLibrary("SDL2", .{});
    stygian_runtime.addOptions("build_options", options);

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
        stygian_runtime.addIncludePath(cache_path);
        stygian_runtime.link_libc = true;
    } else {
        if (vulkan_render) {
            stygian_runtime.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });
            stygian_runtime.addIncludePath(b.path("thirdparty/vma"));
            stygian_runtime.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp") });
            stygian_runtime.linkSystemLibrary("vulkan", .{});
            stygian_runtime.link_libcpp = true;
        } else {
            stygian_runtime.link_libc = true;
        }
    }

    const exe = if (unibuild) blk: {
        const platform = if (target.result.os.tag == .emscripten)
            b.addStaticLibrary(.{
                .name = "unibuild_emscripten",
                .root_source_file = b.path(platform_src_path),
                .target = target,
                .optimize = optimize,
            })
        else
            b.addExecutable(.{
                .name = "unibuild_platform",
                .root_source_file = b.path(platform_src_path),
                .target = target,
                .optimize = optimize,
            });
        platform.root_module.addImport("stygian_platform", stygian_platform);

        const runtime = b.addStaticLibrary(.{
            .name = "unibuild_runtime",
            .root_source_file = b.path(runtime_src_path),
            .target = target,
            .optimize = optimize,
        });
        runtime.root_module.addImport("stygian_runtime", stygian_runtime);

        if (target.result.os.tag != .emscripten) {
            platform.linkLibrary(runtime);
            b.installArtifact(platform);
        } else {
            b.installArtifact(platform);
            b.installArtifact(runtime);
        }

        break :blk platform;
    } else blk: {
        const platform = b.addExecutable(.{
            .name = "platform",
            .root_source_file = b.path(platform_src_path),
            .target = target,
            .optimize = optimize,
        });
        platform.root_module.addImport("stygian_platform", stygian_platform);
        b.installArtifact(platform);

        const runtime = b.addSharedLibrary(.{
            .name = "runtime",
            .root_source_file = b.path(runtime_src_path),
            .target = target,
            .optimize = optimize,
        });
        runtime.root_module.addImport("stygian_runtime", stygian_runtime);
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
}

fn compile_shaders(b: *std.Build) *std.Build.Step {
    const shader_step = b.step("shaders", "Shader compilation");

    const shaders_dir = b.build_root.handle.openDir("shaders", .{ .iterate = true }) catch
        @panic("cannot open shader dir");

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

                const source_file_path =
                    std.fmt.allocPrint(b.allocator, "shaders/{s}.glsl", .{name}) catch unreachable;
                const output_file_path =
                    std.fmt.allocPrint(b.allocator, "{s}.spv", .{name}) catch unreachable;

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

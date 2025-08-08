const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unibuild = b.option(bool, "unibuild", "Compile as a single binary") orelse false;
    const fossilize = b.option(bool, "fossilize", "Add a fossilize layer") orelse false;

    const limit_fps = b.option(u32, "limit_fps", "Upper limit of FPS") orelse 60;
    const window_width = b.option(u32, "window_width", "Default window width") orelse 1280;
    const window_height = b.option(u32, "window_height", "Default window height") orelse 720;

    const game_memory_mb = b.option(u32, "game_memory_mb", "Game memory size limit") orelse 32;
    const frame_memory_mb = b.option(u32, "frame_memory_mb", "Frame memory size limit") orelse 1;
    const scratch_memory_pages =
        b.option(u32, "scratch_memory_pages", "Scratch memory pages limit") orelse 4096;
    const max_textures =
        b.option(u32, "max_textures", "Maximum number of loaded textures.") orelse 32;
    const max_audio_tracks =
        b.option(u32, "max_audio_tracks", "Maximum number of loaded audio tracks.") orelse 32;

    const lib_path = b.option([]const u8, "lib_path", "Compile as a single binary") orelse
        "./zig-out/lib/libruntime.so";

    const platform_src_path =
        b.option([]const u8, "platform_src_path", "Path to the platform.zig file") orelse
        "examples/platform.zig";
    const runtime_src_path =
        b.option([]const u8, "runtime_src_path", "Path to the runtime.zig file") orelse
        "examples/runtime.zig";

    const options = b.addOptions();
    options.addOption(bool, "unibuild", unibuild);
    options.addOption(bool, "fossilize", fossilize);
    options.addOption(u32, "limit_fps", limit_fps);
    options.addOption(u32, "window_width", window_width);
    options.addOption(u32, "window_height", window_height);
    options.addOption(u32, "game_memory_mb", game_memory_mb);
    options.addOption(u32, "frame_memory_mb", frame_memory_mb);
    options.addOption(u32, "scratch_memory_pages", scratch_memory_pages);
    options.addOption(u32, "max_textures", max_textures);
    options.addOption(u32, "max_audio_tracks", max_audio_tracks);
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
    stygian_platform.addIncludePath(.{ .cwd_relative = env_map.get("SDL3_INCLUDE_PATH").? });
    stygian_platform.linkSystemLibrary("SDL3", .{});
    stygian_platform.addOptions("build_options", options);
    stygian_platform.link_libc = true;

    const stygian_runtime = b.addModule("stygian_runtime", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    stygian_runtime.addIncludePath(.{ .cwd_relative = env_map.get("SDL3_INCLUDE_PATH").? });
    stygian_runtime.addIncludePath(b.path("thirdparty/stb"));
    stygian_runtime.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb_image.c") });
    stygian_runtime.linkSystemLibrary("SDL3", .{});
    stygian_runtime.addOptions("build_options", options);

    stygian_runtime.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });
    stygian_runtime.addIncludePath(b.path("thirdparty/vma"));
    stygian_runtime.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp") });
    stygian_runtime.linkSystemLibrary("vulkan", .{});
    stygian_runtime.link_libc = true;
    stygian_runtime.link_libcpp = true;

    const exe = if (unibuild) blk: {
        const platform = b.addExecutable(.{
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

        platform.linkLibrary(runtime);
        b.installArtifact(platform);

        break :blk platform;
    } else blk: {
        const platform = b.addExecutable(.{
            .name = "platform",
            .root_source_file = b.path(platform_src_path),
            .target = target,
            .optimize = optimize,
        });
        platform.root_module.addImport("stygian_platform", stygian_platform);

        const runtime = b.addSharedLibrary(.{
            .name = "runtime",
            .root_source_file = b.path(runtime_src_path),
            .target = target,
            .optimize = optimize,
        });
        runtime.root_module.addImport("stygian_runtime", stygian_runtime);

        b.installArtifact(platform);
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
                    continue;

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

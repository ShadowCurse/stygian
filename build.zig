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

    if (b.option(bool, "compile_shaders", "Compile shaders")) |_| {
        const shader_step = compile_shaders(b);
        b.default_step.dependOn(shader_step);
    }

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();

    const exe = b.addExecutable(.{
        .name = "stygian",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
    exe.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });

    exe.addIncludePath(b.path("thirdparty/vma"));
    exe.addIncludePath(b.path("thirdparty/stb"));
    exe.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp") });
    exe.addCSourceFile(.{ .file = b.path("thirdparty/stb/stb_image.c") });

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("vulkan");
    exe.linkLibCpp();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

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

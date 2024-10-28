const std = @import("std");
const log = @import("log.zig");
const vk = @import("vulkan.zig");
const sdl = @import("sdl.zig");

const Memory = @import("memory.zig");

const RenderContext = @import("render/context.zig");

const _math = @import("math.zig");
const Mat4 = _math.Mat4;

const _mesh = @import("mesh.zig");
const CubeMesh = _mesh.CubeMesh;

const CameraController = @import("camera.zig").CameraController;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;

pub fn main() !void {
    var memory = try Memory.init();
    defer memory.deinit();

    {
        const game_alloc = memory.game_alloc();
        const buf = try game_alloc.alloc(u8, 1024);
        defer game_alloc.free(buf);
        log.info(@src(), "game: alloc {} bytes. game requested bytes: {}", .{ buf.len, memory.game_allocator.total_requested_bytes });
    }
    log.info(@src(), "game: game requested bytes after: {}", .{memory.game_allocator.total_requested_bytes});

    {
        const frame_alloc = memory.frame_alloc();
        defer memory.reset_frame();
        const buf = try frame_alloc.alloc(u8, 1024);
        defer frame_alloc.free(buf);
        log.info(@src(), "frame: alloc {} bytes. frame alloc end index: {}", .{ buf.len, memory.frame_allocator.end_index });
    }
    log.info(@src(), "frame alloc end index after: {}", .{memory.frame_allocator.end_index});

    log.info(@src(), "info log", .{});
    log.debug(@src(), "debug log", .{});
    log.warn(@src(), "warn log", .{});
    log.err(@src(), "err log", .{});

    var context = try RenderContext.init(&memory, WINDOW_WIDTH, WINDOW_HEIGHT);
    defer context.deinit();

    var cube_mesh = try context.create_mesh(&CubeMesh.indices, &CubeMesh.vertices);
    defer context.delete_mesh(&cube_mesh);

    const screen_quad = try context.create_ui_quad(
        .{
            .x = 200.0,
            .y = 200.0,
        },
        .{
            .x = -WINDOW_WIDTH / 2.0 + 100.0,
            .y = -WINDOW_HEIGHT / 2.0 + 100.0,
        },
    );
    defer context.delete_ui_quad(&screen_quad);

    const screen_quad_2 = try context.create_ui_quad(
        .{
            .x = 100.0,
            .y = 100.0,
        },
        .{
            .x = -WINDOW_WIDTH / 2.0 + 300.0,
            .y = -WINDOW_HEIGHT / 2.0 + 300.0,
        },
    );
    defer context.delete_ui_quad(&screen_quad_2);

    var camera_controller = CameraController{};
    camera_controller.position.z = -5.0;

    var stop = false;
    var t = std.time.nanoTimestamp();
    while (!stop) {
        const new_t = std.time.nanoTimestamp();
        const dt = @as(f32, @floatFromInt(new_t - t)) / 1000_000_000.0;
        t = new_t;

        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event) != 0) {
            if (sdl_event.type == sdl.SDL_QUIT) {
                stop = true;
                break;
            }
            camera_controller.process_input(&sdl_event, dt);
        }
        camera_controller.update(dt);

        const view = camera_controller.view_matrix();
        var projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, @floatFromInt(context.renderer.draw_image.extent.width)) /
                @as(f32, @floatFromInt(context.renderer.draw_image.extent.height)),
            10000.0,
            0.1,
        );
        projection.j.y *= -1.0;
        cube_mesh.push_constants.view_proj = view.mul(projection);

        const frame_context = try context.start_rendering();
        try context.render_mesh(frame_context, &cube_mesh);
        try context.render_ui_quad(frame_context, &screen_quad);
        try context.render_ui_quad(frame_context, &screen_quad_2);
        try context.end_rendering(frame_context);
    }

    context.renderer.wait_idle();
    log.info(@src(), "Exiting", .{});
}

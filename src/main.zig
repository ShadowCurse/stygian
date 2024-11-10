const std = @import("std");
const log = @import("log.zig");
const vk = @import("vulkan.zig");
const sdl = @import("sdl.zig");

const Image = @import("image.zig");
const Font = @import("font.zig").Font;
const FontInfo = @import("font.zig").FontInfo;
const UiText = @import("font.zig").UiText;

const MEMORY = &@import("memory.zig").MEMORY;
const VkRenderer = @import("render/vk_renderer.zig");

const _ui_quad = @import("render/ui_quad.zig");
const UiQuadPipeline = _ui_quad.UiQuadPipeline;
const RenderUiQuadInfo = _ui_quad.RenderUiQuadInfo;

const _render_mesh = @import("render/mesh.zig");
const MeshPipeline = _render_mesh.MeshPipeline;
const RenderMeshInfo = _render_mesh.RenderMeshInfo;

const _color = @import("color.zig");
const Color = _color.Color;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

const _mesh = @import("mesh.zig");
const CubeMesh = _mesh.CubeMesh;

const CameraController = @import("camera.zig").CameraController;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;
const FPS = 60.0;
const FRAME_TIME = 1.0 / FPS;

pub fn main() !void {
    try MEMORY.init();

    log.info(@src(), "info log", .{});
    log.debug(@src(), "debug log", .{});
    log.warn(@src(), "warn log", .{});
    log.err(@src(), "err log", .{});

    var renderer = try VkRenderer.init(WINDOW_WIDTH, WINDOW_HEIGHT);
    defer renderer.deinit();

    const ui_quad_pipeline = try UiQuadPipeline.init(&renderer);
    defer ui_quad_pipeline.deinit(&renderer);

    const mesh_pipeline = try MeshPipeline.init(&renderer);
    defer mesh_pipeline.deinit(&renderer);

    var cube_mesh = try RenderMeshInfo.init(&renderer, &CubeMesh.indices, &CubeMesh.vertices, 2);
    defer cube_mesh.deinit(&renderer);

    const screen_quad = try RenderUiQuadInfo.init(&renderer, 3);
    defer screen_quad.deinit(&renderer);

    const image = try Image.init("assets/a.png");
    defer image.deinit();

    const texture = try renderer.create_texture(image.width, image.height);
    defer renderer.delete_texture(&texture);

    try renderer.upload_texture_image(&texture, &image);

    ui_quad_pipeline.set_color_texture(&renderer, texture.view, renderer.debug_sampler);

    const font = try Font.init(&renderer, "assets/font.png");
    defer font.deinit(&renderer);
    ui_quad_pipeline.set_font_texture(&renderer, font.texture.view, renderer.debug_sampler);

    const font_info = try FontInfo.init("assets/font.json");
    defer font_info.deinit();

    var frame_time_text = try UiText.init(&renderer, 32);
    defer frame_time_text.deinit(&renderer);

    var frame_alloc_text = try UiText.init(&renderer, 32);
    defer frame_alloc_text.deinit(&renderer);

    var camera_controller = CameraController{};
    camera_controller.position.z = -5.0;

    log.info(@src(), "game alloc usage: {}", .{MEMORY.game_allocator.total_requested_bytes});
    log.info(@src(), "frame alloc usage: {}", .{MEMORY.frame_allocator.end_index});
    log.info(@src(), "scratch alloc usage: {}", .{MEMORY.scratch_allocator.end_index});

    var stop = false;
    var t = std.time.nanoTimestamp();
    while (!stop) {
        defer MEMORY.reset_frame();

        const new_t = std.time.nanoTimestamp();

        var dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
        t = new_t;

        if (dt < FRAME_TIME) {
            std.time.sleep(@intFromFloat((FRAME_TIME - dt) * std.time.ns_per_s));
            dt = FRAME_TIME;
        }

        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event) != 0) {
            if (sdl_event.type == sdl.SDL_QUIT) {
                stop = true;
                break;
            }
            camera_controller.process_input(&sdl_event, dt);
        }
        camera_controller.update(dt);

        frame_time_text.set_text(
            &font_info,
            try std.fmt.allocPrint(MEMORY.frame_alloc(), "FPS: {d:.1} FT: {d:.3}s", .{ 1.0 / dt, dt }),
            .{
                .x = @floatFromInt(WINDOW_WIDTH),
                .y = @floatFromInt(WINDOW_HEIGHT),
            },
            .{
                .x = -100.0,
                .y = 300.0,
            },
            .{
                .x = 30.0,
                .y = 30.0,
            },
        );

        frame_alloc_text.set_text(
            &font_info,
            try std.fmt.allocPrint(MEMORY.frame_alloc(), "FM: {} bytes", .{MEMORY.frame_allocator.end_index}),
            .{
                .x = @floatFromInt(WINDOW_WIDTH),
                .y = @floatFromInt(WINDOW_HEIGHT),
            },
            .{
                .x = -100.0,
                .y = 250.0,
            },
            .{
                .x = 30.0,
                .y = 30.0,
            },
        );

        const view = camera_controller.view_matrix();
        var projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, WINDOW_WIDTH) / @as(f32, WINDOW_HEIGHT),
            10000.0,
            0.1,
        );
        projection.j.y *= -1.0;
        cube_mesh.push_constants.view_proj = view.mul(projection);

        const A = struct {
            var a: f32 = 0.0;
        };
        A.a += dt;
        cube_mesh.set_instance_info(0, .{
            .transform = Mat4.rotation(
                Vec3.Y,
                A.a,
            ),
        });
        cube_mesh.set_instance_info(1, .{
            .transform = Mat4.IDENDITY.translate(.{ .y = 2.0 }),
        });

        {
            const size = Vec2{
                .x = 200.0,
                .y = 200.0,
            };
            const pos = Vec2{
                .x = -WINDOW_WIDTH / 2.0 + 100.0,
                .y = -WINDOW_HEIGHT / 2.0 + 100.0,
            };
            screen_quad.set_instance_info(0, .{
                .color = .{},
                .type = .VertColor,
                .pos = .{
                    .x = pos.x / (@as(f32, @floatFromInt(renderer.window_width)) / 2.0),
                    .y = pos.y / (@as(f32, @floatFromInt(renderer.window_height)) / 2.0),
                },
                .scale = .{
                    .x = size.x / @as(f32, @floatFromInt(renderer.window_width)),
                    .y = size.y / @as(f32, @floatFromInt(renderer.window_height)),
                },
            });
        }
        {
            const size = Vec2{
                .x = 200.0,
                .y = 200.0,
            };
            const pos = Vec2{
                .x = -WINDOW_WIDTH / 2.0 + 100.0,
                .y = -WINDOW_HEIGHT / 2.0 + 300.0,
            };
            screen_quad.set_instance_info(1, .{
                .color = Color.MAGENTA.to_vec3(),
                .type = .SolidColor,
                .pos = .{
                    .x = pos.x / (@as(f32, @floatFromInt(renderer.window_width)) / 2.0),
                    .y = pos.y / (@as(f32, @floatFromInt(renderer.window_height)) / 2.0),
                },
                .scale = .{
                    .x = size.x / @as(f32, @floatFromInt(renderer.window_width)),
                    .y = size.y / @as(f32, @floatFromInt(renderer.window_height)),
                },
            });
        }
        {
            const size = Vec2{
                .x = 200.0,
                .y = 200.0,
            };
            const pos = Vec2{
                .x = -WINDOW_WIDTH / 2.0 + 100.0,
                .y = -WINDOW_HEIGHT / 2.0 + 500.0,
            };
            screen_quad.set_instance_info(2, .{
                .color = .{},
                .type = .Texture,
                .pos = .{
                    .x = pos.x / (@as(f32, @floatFromInt(renderer.window_width)) / 2.0),
                    .y = pos.y / (@as(f32, @floatFromInt(renderer.window_height)) / 2.0),
                },
                .scale = .{
                    .x = size.x / @as(f32, @floatFromInt(renderer.window_width)),
                    .y = size.y / @as(f32, @floatFromInt(renderer.window_height)),
                },
            });
        }

        const frame_context = try renderer.start_rendering();
        mesh_pipeline.render(&frame_context, &.{.{ &cube_mesh, 2 }});
        ui_quad_pipeline.render(
            &frame_context,
            &.{
                .{ &screen_quad, 3 },
                .{ &frame_time_text.screen_quads, frame_time_text.current_text_len },
                .{ &frame_alloc_text.screen_quads, frame_alloc_text.current_text_len },
            },
        );
        try renderer.end_rendering(frame_context);
    }

    renderer.vk_context.wait_idle();
    log.info(@src(), "Exiting", .{});
}

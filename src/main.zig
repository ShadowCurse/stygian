const std = @import("std");
const log = @import("log.zig");
const vk = @import("vulkan.zig");
const sdl = @import("sdl.zig");

const Image = @import("image.zig");
const Font = @import("font.zig").Font;
const FontInfo = @import("font.zig").FontInfo;
const UiText = @import("font.zig").UiText;

const Memory = @import("memory.zig");
const VkRenderer = @import("render/vk_renderer.zig");

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
const SAMPLE_TEXT = "SAMPLE text";

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

    var renderer = try VkRenderer.init(&memory, WINDOW_WIDTH, WINDOW_HEIGHT);
    defer renderer.deinit();

    var cube_mesh = try renderer.create_mesh(&CubeMesh.indices, &CubeMesh.vertices, 2);
    defer renderer.delete_mesh(&cube_mesh);

    const screen_quad = try renderer.create_ui_quad(3);
    defer renderer.delete_ui_quad(&screen_quad);

    const image = try Image.init("assets/a.png");
    defer image.deinit();

    const texture = try renderer.create_texture(image.width, image.height);
    defer renderer.delete_texture(&texture);

    try renderer.upload_texture_image(&texture, &image);
    renderer.set_ui_quad_pipeline_color_texture(texture.view, renderer.debug_sampler);

    const font = try Font.init(&renderer, "assets/font.png");
    defer font.deinit(&renderer);
    renderer.set_ui_quad_pipeline_font_texture(font.texture.view, renderer.debug_sampler);

    const font_info = try FontInfo.init(memory.game_alloc(), memory.frame_alloc(), "assets/font.json");
    memory.reset_frame();
    defer font_info.deinit(memory.game_alloc());

    var sample_text = try UiText.init(&renderer, 32);
    defer sample_text.deinit(&renderer);

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

        sample_text.set_text(
            &font_info,
            SAMPLE_TEXT,
            .{
                .x = @floatFromInt(WINDOW_WIDTH),
                .y = @floatFromInt(WINDOW_HEIGHT),
            },
            .{
                .x = 300.0,
                .y = -300.0,
            },
            .{
                .x = 50.0,
                .y = 50.0,
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
        try renderer.render_mesh(&frame_context, &cube_mesh, 2);
        try renderer.render_ui_quad(&frame_context, &screen_quad, 3);
        try renderer.render_ui_quad(&frame_context, &sample_text.screen_quads, SAMPLE_TEXT.len);
        try renderer.end_rendering(frame_context);
    }

    renderer.vk_context.wait_idle();
    log.info(@src(), "Exiting", .{});
}

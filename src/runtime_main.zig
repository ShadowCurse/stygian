const std = @import("std");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Image = @import("image.zig");
const GpuImage = @import("vk_renderer/gpu_image.zig");

const Font = @import("font.zig").Font;
const FontInfo = @import("font.zig").FontInfo;
const UiText = @import("font.zig").UiText;

const Memory = @import("memory.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const CameraController = @import("camera.zig").CameraController;

const _ui_quad = @import("vk_renderer/ui_quad.zig");
const UiQuadPipeline = _ui_quad.UiQuadPipeline;
const RenderUiQuadInfo = _ui_quad.RenderUiQuadInfo;

const _render_mesh = @import("vk_renderer/mesh.zig");
const MeshPipeline = _render_mesh.MeshPipeline;
const RenderMeshInfo = _render_mesh.RenderMeshInfo;

const TileMap = @import("tile_map.zig");

const _color = @import("color.zig");
const Color = _color.Color;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

const _mesh = @import("mesh.zig");
const CubeMesh = _mesh.CubeMesh;

const Runtime = struct {
    renderer: VkRenderer,

    ui_quad_pipeline: UiQuadPipeline,
    screen_quad: RenderUiQuadInfo,

    mesh_pipeline: MeshPipeline,
    cube_mesh: RenderMeshInfo,

    font: Font,
    font_image: GpuImage,

    frame_time_text: UiText,
    frame_alloc_text: UiText,

    tile_map: TileMap,

    camera_controller: CameraController = .{},

    const Self = @This();

    fn init(self: *Self, window: *sdl.SDL_Window, memory: *Memory, width: u32, height: u32) !void {
        self.renderer = try VkRenderer.init(memory, window, width, height);
        self.ui_quad_pipeline = try UiQuadPipeline.init(memory, &self.renderer);
        self.mesh_pipeline = try MeshPipeline.init(memory, &self.renderer);
        self.cube_mesh = try RenderMeshInfo.init(&self.renderer, &CubeMesh.indices, &CubeMesh.vertices, 2);
        self.screen_quad = try RenderUiQuadInfo.init(&self.renderer, 3);

        const image = try Image.init("assets/a.png");
        const texture = try self.renderer.create_texture(image.width, image.height, image.channels);
        try self.renderer.upload_texture_image(&texture, &image);

        self.ui_quad_pipeline.set_color_texture(&self.renderer, texture.view, self.renderer.debug_sampler);

        self.font = try Font.init(memory, "assets/font.ttf", 32);
        self.font_image = try self.renderer.create_texture(
            self.font.image.width,
            self.font.image.height,
            self.font.image.channels,
        );
        try self.renderer.upload_texture_image(&self.font_image, &self.font.image);

        self.ui_quad_pipeline.set_font_texture(&self.renderer, self.font_image.view, self.renderer.debug_sampler);

        self.frame_time_text = try UiText.init(&self.renderer, 32);
        self.frame_alloc_text = try UiText.init(&self.renderer, 32);
        self.tile_map = try TileMap.init(memory, &self.renderer);
    }
};

export fn runtime_main(
    window: *sdl.SDL_Window,
    sdl_events: [*]sdl.SDL_Event,
    sdl_events_num: usize,
    memory: *Memory,
    dt: f32,
    data: ?*anyopaque,
) *anyopaque {
    memory.reset_frame();

    var events: []sdl.SDL_Event = undefined;
    events.ptr = sdl_events;
    events.len = sdl_events_num;
    var runtime_ptr: ?*Runtime = @alignCast(@ptrCast(data));

    var width: i32 = undefined;
    var height: i32 = undefined;
    sdl.SDL_GetWindowSize(window, &width, &height);

    if (runtime_ptr == null) {
        log.info(@src(), "First time runtime init", .{});
        const game_alloc = memory.game_alloc();
        runtime_ptr = &(game_alloc.alloc(Runtime, 1) catch unreachable)[0];
        runtime_ptr.?.init(window, memory, @intCast(width), @intCast(height)) catch unreachable;
    } else {
        var runtime = runtime_ptr.?;

        for (events) |*event| {
            runtime.camera_controller.process_input(event, dt);
        }
        runtime.camera_controller.update(dt);

        runtime.frame_time_text.set_text(
            &runtime.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            .{
                .x = @floatFromInt(width),
                .y = @floatFromInt(height),
            },
            .{
                .x = -100.0,
                .y = 300.0,
            },
        );

        runtime.frame_alloc_text.set_text(
            &runtime.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FM: {} bytes",
                .{memory.frame_allocator.end_index},
            ) catch unreachable,
            .{
                .x = @floatFromInt(width),
                .y = @floatFromInt(height),
            },
            .{
                .x = -100.0,
                .y = 250.0,
            },
        );

        const view = runtime.camera_controller.view_matrix();
        var projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)),
            10000.0,
            0.1,
        );
        projection.j.y *= -1.0;

        runtime.cube_mesh.push_constants.view_proj = view.mul(projection);
        runtime.tile_map.update(runtime.cube_mesh.push_constants.view_proj);

        const A = struct {
            var a: f32 = 0.0;
        };
        A.a += dt;
        var ct = Mat4.rotation(
            Vec3.Y,
            A.a,
        );
        ct = ct.translate(.{ .y = 2.0 });
        runtime.cube_mesh.set_instance_info(0, .{
            .transform = ct,
        });
        runtime.cube_mesh.set_instance_info(1, .{
            .transform = Mat4.IDENDITY.translate(.{ .y = 4.0 }),
        });

        {
            const size = Vec2{
                .x = 200.0,
                .y = 200.0,
            };
            const pos = Vec2{
                .x = -@as(f32, @floatFromInt(width)) / 2.0 + 100.0,
                .y = -@as(f32, @floatFromInt(height)) / 2.0 + 100.0,
            };
            runtime.screen_quad.set_instance_info(0, .{
                .color = .{},
                .type = .VertColor,
                .pos = .{
                    .x = pos.x / (@as(f32, @floatFromInt(width)) / 2.0),
                    .y = pos.y / (@as(f32, @floatFromInt(height)) / 2.0),
                },
                .scale = .{
                    .x = size.x / @as(f32, @floatFromInt(width)),
                    .y = size.y / @as(f32, @floatFromInt(height)),
                },
            });
        }
        {
            const size = Vec2{
                .x = 200.0,
                .y = 200.0,
            };
            const pos = Vec2{
                .x = -@as(f32, @floatFromInt(width)) / 2.0 + 100.0,
                .y = -@as(f32, @floatFromInt(height)) / 2.0 + 300.0,
            };
            runtime.screen_quad.set_instance_info(1, .{
                .color = Color.MAGENTA.to_vec3(),
                .type = .SolidColor,
                .pos = .{
                    .x = pos.x / (@as(f32, @floatFromInt(width)) / 2.0),
                    .y = pos.y / (@as(f32, @floatFromInt(height)) / 2.0),
                },
                .scale = .{
                    .x = size.x / @as(f32, @floatFromInt(width)),
                    .y = size.y / @as(f32, @floatFromInt(height)),
                },
            });
        }
        {
            const size = Vec2{
                .x = 200.0,
                .y = 200.0,
            };
            const pos = Vec2{
                .x = -@as(f32, @floatFromInt(width)) / 2.0 + 100.0,
                .y = -@as(f32, @floatFromInt(height)) / 2.0 + 500.0,
            };
            runtime.screen_quad.set_instance_info(2, .{
                .color = .{},
                .type = .Texture,
                .pos = .{
                    .x = pos.x / (@as(f32, @floatFromInt(width)) / 2.0),
                    .y = pos.y / (@as(f32, @floatFromInt(height)) / 2.0),
                },
                .scale = .{
                    .x = size.x / @as(f32, @floatFromInt(width)),
                    .y = size.y / @as(f32, @floatFromInt(height)),
                },
            });
        }

        const frame_context = runtime.renderer.start_rendering() catch unreachable;
        runtime.mesh_pipeline.render(&frame_context, &.{.{ &runtime.cube_mesh, 2 }});
        runtime.ui_quad_pipeline.render(
            &frame_context,
            &.{
                .{ &runtime.screen_quad, 3 },
                .{ &runtime.frame_time_text.screen_quads, runtime.frame_time_text.current_text_len },
                .{ &runtime.frame_alloc_text.screen_quads, runtime.frame_alloc_text.current_text_len },
            },
        );
        runtime.tile_map.render(&frame_context);
        runtime.renderer.end_rendering(frame_context) catch unreachable;
    }
    return @ptrCast(runtime_ptr);
}

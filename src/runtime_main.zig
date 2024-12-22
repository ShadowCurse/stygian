const std = @import("std");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Image = @import("image.zig");
const GpuImage = @import("vk_renderer/gpu_image.zig");

const Font = @import("font.zig").Font;
const ScreenQuads = @import("screen_quads.zig");

const Memory = @import("memory.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const CameraController = @import("camera.zig").CameraController;

const _screen_quads = @import("vk_renderer/screen_quads.zig");
const ScreenQuadsPipeline = _screen_quads.ScreenQuadsPipeline;
const ScreenQuadsGpuInfo = _screen_quads.ScreenQuadsGpuInfo;

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
    image: Image,
    font: Font,
    screen_quads: ScreenQuads,

    renderer: VkRenderer,

    texture_image: GpuImage,
    font_image: GpuImage,

    screen_quads_pipeline: ScreenQuadsPipeline,
    screen_quads_gpu_info: ScreenQuadsGpuInfo,
    mesh_pipeline: MeshPipeline,
    cube_mesh: RenderMeshInfo,

    tile_map: TileMap,

    camera_controller: CameraController,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        self.image = try Image.init(memory, "assets/a.png");
        self.font = try Font.init(memory, "assets/font.ttf", 32);
        self.screen_quads = try ScreenQuads.init(memory, 64);

        self.renderer = try VkRenderer.init(memory, window, width, height);

        self.texture_image = try self.renderer.create_texture(
            self.image.width,
            self.image.height,
            self.image.channels,
        );
        self.font_image = try self.renderer.create_texture(
            self.font.image.width,
            self.font.image.height,
            self.font.image.channels,
        );

        self.screen_quads_pipeline = try ScreenQuadsPipeline.init(memory, &self.renderer);
        self.screen_quads_gpu_info = try ScreenQuadsGpuInfo.init(&self.renderer, 64);

        try self.renderer.upload_texture_image(&self.texture_image, &self.image);

        self.screen_quads_pipeline.set_color_texture(
            &self.renderer,
            self.texture_image.view,
            self.renderer.debug_sampler,
        );
        try self.renderer.upload_texture_image(&self.font_image, &self.font.image);

        self.screen_quads_pipeline.set_font_texture(
            &self.renderer,
            self.font_image.view,
            self.renderer.debug_sampler,
        );

        self.mesh_pipeline = try MeshPipeline.init(memory, &self.renderer);
        self.cube_mesh = try RenderMeshInfo.init(
            &self.renderer,
            &CubeMesh.indices,
            &CubeMesh.vertices,
            2,
        );

        self.tile_map = try TileMap.init(memory, &self.renderer);

        self.camera_controller = CameraController.init();
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

        runtime.screen_quads.reset();

        for (events) |*event| {
            runtime.camera_controller.process_input(event, dt);
        }
        runtime.camera_controller.update(dt);

        runtime.screen_quads.add_text(
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

        runtime.screen_quads.add_text(
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

        const camera_transform = runtime.camera_controller.transform();
        const projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)),
            0.1,
            10000.0,
        );
        runtime.cube_mesh.push_constants.view_proj = projection.mul(camera_transform.inverse());
        runtime.tile_map.update(runtime.cube_mesh.push_constants.view_proj);

        const A = struct {
            var a: f32 = 0.0;
        };
        A.a += dt;
        const ct = Mat4.rotation_z(A.a);
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
            runtime.screen_quads.add_quad(&.{
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
            runtime.screen_quads.add_quad(&.{
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
            runtime.screen_quads.add_quad(&.{
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

        runtime.screen_quads_gpu_info.set_instance_infos(runtime.screen_quads.slice());

        const frame_context = runtime.renderer.start_rendering() catch unreachable;
        runtime.mesh_pipeline.render(&frame_context, &.{.{ &runtime.cube_mesh, 2 }});
        runtime.tile_map.render(&frame_context);
        runtime.screen_quads_pipeline.render(
            &frame_context,
            &.{
                .{ &runtime.screen_quads_gpu_info, runtime.screen_quads.used_quads },
            },
        );
        runtime.renderer.end_rendering(frame_context) catch unreachable;
    }
    return @ptrCast(runtime_ptr);
}

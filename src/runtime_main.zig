const std = @import("std");
const build_options = @import("build_options");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Image = @import("image.zig");
const GpuImage = @import("vk_renderer/gpu_image.zig");

const Font = @import("font.zig").Font;
const ScreenQuads = @import("screen_quads.zig");

const Memory = @import("memory.zig");
const SoftRenderer = @import("soft_renderer/renderer.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const CameraController = @import("camera.zig").CameraController;

const _screen_quads = @import("vk_renderer/screen_quads.zig");
const ScreenQuadsPipeline = _screen_quads.ScreenQuadsPipeline;
const ScreenQuadsGpuInfo = _screen_quads.ScreenQuadsGpuInfo;

const _render_mesh = @import("vk_renderer/mesh.zig");
const MeshPipeline = _render_mesh.MeshPipeline;
const RenderMeshInfo = _render_mesh.RenderMeshInfo;
const MeshInfo = _render_mesh.MeshInfo;

const TileMap = @import("tile_map.zig");

const _color = @import("color.zig");
const Color = _color.Color;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

const _mesh = @import("mesh.zig");
const CubeMesh = _mesh.CubeMesh;

const SoftwareRuntime = struct {
    image: Image,
    font: Font,
    screen_quads: ScreenQuads,
    tile_map: TileMap,

    soft_renderer: SoftRenderer,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        _ = width;
        _ = height;

        self.image = try Image.init(memory, "assets/a.png");
        self.font = try Font.init(memory, "assets/font.ttf", 32);
        self.screen_quads = try ScreenQuads.init(memory, 64);
        self.tile_map = try TileMap.init(memory, 5, 5, 0.2, 0.2);
        var y: u32 = 0;
        while (y < 5) : (y += 1) {
            var x: u32 = 0;
            while (x < 5) : (x += 1) {
                if (!(0 < y and y < 4 and 0 < x and x < 4)) {
                    self.tile_map.set_tile(x, y, .Wall);
                }
            }
        }
        self.soft_renderer = SoftRenderer.init(window);
    }

    fn run(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []sdl.SDL_Event,
        width: i32,
        height: i32,
    ) void {
        _ = events;
        self.screen_quads.reset();

        self.screen_quads.add_text(
            &self.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0 - 100.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 300.0,
            },
        );
        self.screen_quads.add_text(
            &self.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FM: {} bytes",
                .{memory.frame_allocator.end_index},
            ) catch unreachable,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0 - 100.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 250.0,
            },
        );
        self.screen_quads.add_quad(&.{
            .color = .{},
            .type = .VertColor,
            .pos = .{
                .x = 100.0,
                .y = 100.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });
        self.screen_quads.add_quad(&.{
            .color = Color.MAGENTA.to_vec3(),
            .type = .SolidColor,
            .pos = .{
                .x = 100.0,
                .y = 300.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });
        self.screen_quads.add_quad(&.{
            .color = .{},
            .type = .Texture,
            .pos = .{
                .x = 100.0,
                .y = 500.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });

        {
            self.soft_renderer.start_rendering();
            for (self.screen_quads.slice()) |sq| {
                switch (sq.type) {
                    .Font => {
                        self.soft_renderer.draw_image(
                            sq.pos,
                            .{
                                .image = &self.font.image,
                                .position = sq.uv_pos,
                                .size = sq.uv_scale,
                            },
                        );
                    },
                    .Texture => {
                        self.soft_renderer.draw_image(
                            sq.pos,
                            .{
                                .image = &self.image,
                                .position = .{
                                    .x = 0.0,
                                    .y = 0.0,
                                },
                                .size = .{
                                    .x = @as(f32, @floatFromInt(self.image.width)),
                                    .y = @as(f32, @floatFromInt(self.image.height)),
                                },
                            },
                        );
                    },
                    else => {},
                }
            }

            const A = struct {
                var a: f32 = 0;
            };
            A.a += dt;
            // 1, 0
            const x_axis = Vec2{
                .x = @cos(A.a),
                .y = @sin(A.a),
            };
            // 0, -1
            const y_axis = Vec2{
                .x = @sin(A.a),
                .y = -@cos(A.a),
            };
            self.soft_renderer.draw_image_axis(
                .{
                    .x = 300.0,
                    .y = 300.0,
                },
                .{
                    .image = &self.image,
                    .position = .{
                        .x = 0.0,
                        .y = 0.0,
                    },
                    .size = .{
                        .x = @as(f32, @floatFromInt(self.image.width)),
                        .y = @as(f32, @floatFromInt(self.image.height)),
                    },
                },
                x_axis.normalize().mul_f32(2.0),
                y_axis.normalize().mul_f32(2.0),
            );
            self.soft_renderer.end_rendering();
        }
    }
};

const VulkanRuntime = struct {
    camera_controller: CameraController,

    image: Image,
    font: Font,
    screen_quads: ScreenQuads,
    tile_map: TileMap,

    vk_renderer: VkRenderer,
    texture_image: GpuImage,
    font_image: GpuImage,
    screen_quads_pipeline: ScreenQuadsPipeline,
    screen_quads_gpu_info: ScreenQuadsGpuInfo,
    mesh_pipeline: MeshPipeline,
    cube_meshes: RenderMeshInfo,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        self.camera_controller = CameraController.init();

        self.image = try Image.init(memory, "assets/a.png");
        self.font = try Font.init(memory, "assets/font.ttf", 32);
        self.screen_quads = try ScreenQuads.init(memory, 64);
        self.tile_map = try TileMap.init(memory, 5, 5, 0.2, 0.2);
        var y: u32 = 0;
        while (y < 5) : (y += 1) {
            var x: u32 = 0;
            while (x < 5) : (x += 1) {
                if (!(0 < y and y < 4 and 0 < x and x < 4)) {
                    self.tile_map.set_tile(x, y, .Wall);
                }
            }
        }

        self.vk_renderer = try VkRenderer.init(memory, window, width, height);

        self.texture_image = try self.vk_renderer.create_texture(
            self.image.width,
            self.image.height,
            self.image.channels,
        );
        self.font_image = try self.vk_renderer.create_texture(
            self.font.image.width,
            self.font.image.height,
            self.font.image.channels,
        );

        self.screen_quads_pipeline = try ScreenQuadsPipeline.init(memory, &self.vk_renderer);
        self.screen_quads_gpu_info = try ScreenQuadsGpuInfo.init(&self.vk_renderer, 64);

        try self.vk_renderer.upload_texture_image(&self.texture_image, &self.image);

        self.screen_quads_pipeline.set_color_texture(
            &self.vk_renderer,
            self.texture_image.view,
            self.vk_renderer.debug_sampler,
        );
        try self.vk_renderer.upload_texture_image(&self.font_image, &self.font.image);

        self.screen_quads_pipeline.set_font_texture(
            &self.vk_renderer,
            self.font_image.view,
            self.vk_renderer.debug_sampler,
        );

        self.mesh_pipeline = try MeshPipeline.init(memory, &self.vk_renderer);
        self.cube_meshes = try RenderMeshInfo.init(
            &self.vk_renderer,
            &CubeMesh.indices,
            &CubeMesh.vertices,
            32,
        );
    }

    fn run(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []sdl.SDL_Event,
        width: i32,
        height: i32,
    ) void {
        const frame_alloc = memory.frame_alloc();
        self.screen_quads.reset();
        self.cube_meshes.reset();

        for (events) |*event| {
            self.camera_controller.process_input(event, dt);
        }
        self.camera_controller.update(dt);

        const camera_transform = self.camera_controller.transform();
        const projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)),
            0.1,
            10000.0,
        );
        self.cube_meshes.push_constants.view_proj = projection.mul(camera_transform.inverse());
        self.screen_quads_gpu_info.set_screen_size(
            .{ .x = @floatFromInt(width), .y = @floatFromInt(height) },
        );

        const A = struct {
            var a: f32 = 0.0;
        };
        A.a += dt;
        const ct = Mat4.rotation_z(A.a);
        self.cube_meshes.add_instance_infos(&.{.{
            .transform = ct,
        }});
        self.cube_meshes.add_instance_infos(&.{.{
            .transform = Mat4.IDENDITY.translate(.{ .z = 4.0 }),
        }});

        const tile_positions = self.tile_map.get_positions(frame_alloc) catch unreachable;
        const mesh_position = frame_alloc.alloc(MeshInfo, tile_positions.len) catch unreachable;
        for (tile_positions, mesh_position) |*t, *m| {
            m.transform = Mat4.IDENDITY.translate(t.extend(0.0));
        }
        self.cube_meshes.add_instance_infos(mesh_position);

        self.screen_quads.add_text(
            &self.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0 - 100.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 300.0,
            },
        );
        self.screen_quads.add_text(
            &self.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FM: {} bytes",
                .{memory.frame_allocator.end_index},
            ) catch unreachable,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0 - 100.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 250.0,
            },
        );
        self.screen_quads.add_quad(&.{
            .color = .{},
            .type = .VertColor,
            .pos = .{
                .x = 100.0,
                .y = 100.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });
        self.screen_quads.add_quad(&.{
            .color = Color.MAGENTA.to_vec3(),
            .type = .SolidColor,
            .pos = .{
                .x = 100.0,
                .y = 300.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });
        self.screen_quads.add_quad(&.{
            .color = .{},
            .type = .Texture,
            .pos = .{
                .x = 100.0,
                .y = 500.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });

        self.screen_quads_gpu_info.set_instance_infos(self.screen_quads.slice());

        const frame_context = self.vk_renderer.start_rendering() catch unreachable;
        self.mesh_pipeline.render(
            &frame_context,
            &.{.{ &self.cube_meshes, self.cube_meshes.num_instances_used }},
        );
        self.screen_quads_pipeline.render(
            &frame_context,
            &.{
                .{ &self.screen_quads_gpu_info, self.screen_quads.used_quads },
            },
        );
        self.vk_renderer.end_rendering(frame_context) catch unreachable;
    }
};

const Runtime = if (build_options.software_render)
    SoftwareRuntime
else if (build_options.vulkan_render)
    VulkanRuntime
else
    @panic("No renderer type selected");

pub export fn runtime_main(
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
        runtime.run(memory, dt, events, width, height);
    }
    return @ptrCast(runtime_ptr);
}

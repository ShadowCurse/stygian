const std = @import("std");
const build_options = @import("build_options");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const _audio = @import("audio.zig");
const Audio = _audio.Audio;
const SoundtrackId = _audio.SoundtrackId;

const Image = @import("image.zig");
const GpuImage = @import("vk_renderer/gpu_image.zig");

const Font = @import("font.zig").Font;
const ScreenQuads = @import("screen_quads.zig");

const Memory = @import("memory.zig");
const SoftRenderer = @import("soft_renderer/renderer.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const CameraController2d = @import("camera.zig").CameraController2d;
const CameraController3d = @import("camera.zig").CameraController3d;

const _vk_screen_quads = @import("vk_renderer/screen_quads.zig");
const ScreenQuadsPipeline = _vk_screen_quads.ScreenQuadsPipeline;
const ScreenQuadsGpuInfo = _vk_screen_quads.ScreenQuadsGpuInfo;

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

const _objects = @import("objects.zig");
const Object2d = _objects.Object2d;
const Transform2d = _objects.Transform2d;

const SoftwareRuntime = struct {
    camera_controller: CameraController2d,

    font: Font,
    images: [4]Image,

    screen_quads: ScreenQuads,
    tile_map: TileMap,

    audio: Audio,
    soundtrack_id: SoundtrackId,

    soft_renderer: SoftRenderer,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        self.camera_controller = CameraController2d.init(width, height);

        self.font = try Font.init(memory, "assets/font.ttf", 32);
        self.font.image_id = 0;
        self.images[0] = self.font.image;
        self.images[1] = try Image.init(memory, "assets/a.png");
        self.images[2] = try Image.init(memory, "assets/item_pot.png");
        self.images[3] = try Image.init(memory, "assets/item_coffecup.png");

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
        self.audio.init(0.5) catch unreachable;
        self.soundtrack_id = self.audio.load_wav(memory, "assets/background.wav") catch
            unreachable;
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
        self.screen_quads.reset();

        for (events) |*event| {
            self.camera_controller.process_input(event, dt);
            if (event.type == sdl.SDL_KEYDOWN) {
                switch (event.key.keysym.sym) {
                    sdl.SDLK_g => self.audio.play(self.soundtrack_id),
                    sdl.SDLK_p => self.audio.stop(),
                    sdl.SDLK_4 => self.audio.volume += 0.1,
                    sdl.SDLK_5 => self.audio.volume -= 0.1,
                    else => {},
                }
            }
        }
        self.camera_controller.update(dt);

        const A = struct {
            var a: f32 = 0;
        };
        A.a += dt;

        const objects = [_]Object2d{
            .{
                .type = .{ .TextureId = 2 },
                .transform = .{
                    .position = .{
                        .x = 0.0,
                        .y = 0.0,
                    },
                    .rotation = A.a,
                },
                .size = .{
                    .x = 64.0,
                    .y = 64.0,
                },
            },
            .{
                .type = .{ .TextureId = 3 },
                .transform = .{
                    .position = .{
                        .x = 0.0,
                        .y = -100.0,
                    },
                    .rotation = -A.a,
                },
                .size = .{
                    .x = 64.0,
                    .y = 64.0,
                },
            },
            .{
                .type = .{ .Color = Color.ORAGE },
                .transform = .{
                    .position = .{
                        .x = 100.0,
                        .y = 0.0,
                    },
                    .rotation = 0.0,
                },
                .size = .{
                    .x = 50.0,
                    .y = 50.0,
                },
            },
            .{
                .type = .{ .Color = Color.ORAGE },
                .transform = .{
                    .position = .{
                        .x = -100.0,
                        .y = 0.0,
                    },
                    .rotation = A.a,
                },
                .size = .{
                    .x = 50.0,
                    .y = 50.0,
                },
            },
        };

        for (&objects) |*object| {
            object.to_screen_quad(
                &self.camera_controller,
                &self.images,
                &self.screen_quads,
            );
        }

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
        self.screen_quads.add_quad(.{
            .color = Color.MAGENTA,
            .texture_id = ScreenQuads.TextureIdSolidColor,
            .pos = .{
                .x = 100.0,
                .y = 300.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
            .rotation = A.a,
        });
        self.screen_quads.add_quad(.{
            .texture_id = 1,
            .pos = .{
                .x = 100.0,
                .y = 500.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
            .rotation = A.a,
            .rotation_offset = .{
                .x = 100.0,
                .y = -100.0,
            },
            .uv_offset = .{},
            .uv_size = .{
                .x = @as(f32, @floatFromInt(self.images[1].width)),
                .y = @as(f32, @floatFromInt(self.images[1].height)),
            },
        });

        {
            self.soft_renderer.start_rendering();
            for (self.screen_quads.slice()) |sq| {
                switch (sq.texture_id) {
                    ScreenQuads.TextureIdVertColor => {},
                    ScreenQuads.TextureIdSolidColor => {
                        if (sq.rotation == 0.0) {
                            self.soft_renderer.draw_color_rect(
                                sq.pos,
                                sq.size,
                                sq.color,
                            );
                        } else {
                            self.soft_renderer.draw_color_rect_with_rotation(
                                sq.pos,
                                sq.size,
                                sq.rotation,
                                sq.rotation_offset,
                                sq.color,
                            );
                        }
                    },
                    else => |texture_id| {
                        const image = &self.images[texture_id];
                        if (sq.rotation == 0.0) {
                            self.soft_renderer.draw_image(
                                sq.pos,
                                .{
                                    .image = image,
                                    .position = sq.uv_offset,
                                    .size = sq.uv_size,
                                },
                            );
                        } else {
                            self.soft_renderer.draw_image_with_scale_and_rotation(
                                sq.pos,
                                sq.size,
                                sq.rotation,
                                sq.rotation_offset,
                                .{
                                    .image = image,
                                    .position = sq.uv_offset,
                                    .size = sq.uv_size,
                                },
                            );
                        }
                    },
                }
            }
            self.soft_renderer.end_rendering();
        }
    }
};

const VulkanRuntime = struct {
    camera_controller: CameraController3d,

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
        self.camera_controller = CameraController3d.init();

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
        try self.vk_renderer.upload_texture_image(&self.font_image, &self.font.image);
        self.screen_quads_pipeline.set_textures(
            &self.vk_renderer,
            self.font_image.view,
            self.vk_renderer.debug_sampler,
            self.texture_image.view,
            self.vk_renderer.debug_sampler_2,
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
        self.screen_quads.add_quad(.{
            .texture_id = ScreenQuads.TextureIdVertColor,
            .pos = .{
                .x = 100.0,
                .y = 100.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });
        self.screen_quads.add_quad(.{
            .color = Color.MAGENTA,
            .texture_id = ScreenQuads.TextureIdSolidColor,
            .pos = .{
                .x = 100.0,
                .y = 300.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });
        self.screen_quads.add_quad(.{
            .texture_id = 1,
            .pos = .{
                .x = 100.0,
                .y = 500.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
            .rotation = A.a,
            .rotation_offset = .{
                .x = 100.0,
                .y = -100.0,
            },
            .uv_offset = .{},
            .uv_size = .{
                .x = @as(f32, @floatFromInt(self.image.width)),
                .y = @as(f32, @floatFromInt(self.image.height)),
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

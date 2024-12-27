const std = @import("std");
const build_options = @import("build_options");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const _audio = @import("audio.zig");
const Audio = _audio.Audio;
const SoundtrackId = _audio.SoundtrackId;

const Texture = @import("texture.zig");
const GpuTexture = @import("vk_renderer/gpu_texture.zig");

const Font = @import("font.zig").Font;
const ScreenQuads = @import("screen_quads.zig");

const Memory = @import("memory.zig");
const Events = @import("platform/event.zig");
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

    texture_store: Texture.Store,
    texture_letter_a: Texture.Id,
    texture_item_pot: Texture.Id,
    texture_item_coffecup: Texture.Id,

    font: Font,

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

        try self.texture_store.init(memory);
        self.texture_letter_a = self.texture_store.load(memory, "assets/a.png");
        self.texture_item_pot = self.texture_store.load(memory, "assets/item_pot.png");
        self.texture_item_coffecup = self.texture_store.load(memory, "assets/item_coffecup.png");
        self.font = Font.init(memory, &self.texture_store, "assets/font.ttf", 32);

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
        try self.audio.init(0.5);
        self.soundtrack_id = self.audio.load_wav(memory, "assets/background.wav");
        self.soft_renderer = SoftRenderer.init(window);
    }

    fn run(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        width: i32,
        height: i32,
    ) void {
        self.screen_quads.reset();

        for (events) |event| {
            self.camera_controller.process_input(event, dt);
            switch (event) {
                .Keyboard => |key| {
                    switch (key.key) {
                        .G => self.audio.play(self.soundtrack_id),
                        .P => self.audio.stop(),
                        .@"4" => self.audio.volume += 0.1,
                        .@"5" => self.audio.volume -= 0.1,
                        else => {},
                    }
                },
                else => {},
            }
        }
        self.camera_controller.update(dt);

        const A = struct {
            var a: f32 = 0;
        };
        A.a += dt;

        const objects = [_]Object2d{
            .{
                .type = .{ .TextureId = self.texture_item_pot },
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
                .type = .{ .TextureId = self.texture_item_coffecup },
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
                &self.texture_store,
                &self.screen_quads,
            );
        }

        const frame_alloc = memory.frame_alloc();
        const tile_positions = self.tile_map.get_positions(frame_alloc);
        for (tile_positions) |tile_pos| {
            const object = Object2d{
                .type = .{ .Color = Color.ORAGE },
                .transform = .{
                    .position = tile_pos.mul_f32(40.0).extend(0.0),
                },
                .size = .{
                    .x = 80.0,
                    .y = 80.0,
                },
            };
            object.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
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
                .z = 2.0,
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
                .z = 2.0,
            },
        );
        self.screen_quads.add_quad(.{
            .color = Color.MAGENTA,
            .texture_id = Texture.ID_SOLID_COLOR,
            .position = .{
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
            .texture_id = self.texture_letter_a,
            .position = .{
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
                .x = @as(f32, @floatFromInt(self.texture_store.get(self.texture_letter_a).width)),
                .y = @as(f32, @floatFromInt(self.texture_store.get(self.texture_letter_a).height)),
            },
        });

        self.soft_renderer.start_rendering();
        self.screen_quads.render(&self.soft_renderer, &self.texture_store);
        self.soft_renderer.end_rendering();
    }
};

const VulkanRuntime = struct {
    camera_controller: CameraController3d,

    texture_store: Texture.Store,
    texture_letter_a: Texture.Id,

    font: Font,
    screen_quads: ScreenQuads,
    tile_map: TileMap,

    vk_renderer: VkRenderer,
    gpu_debug_texture: GpuTexture,
    gpu_letter_a_texture: GpuTexture,
    gpu_font_texture: GpuTexture,
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

        try self.texture_store.init(memory);
        self.font = Font.init(memory, &self.texture_store, "assets/font.ttf", 32);
        self.texture_letter_a = self.texture_store.load(memory, "assets/a.png");

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

        const debug_texture = self.texture_store.get(Texture.ID_DEBUG);
        self.gpu_debug_texture = try self.vk_renderer.create_texture(
            debug_texture.width,
            debug_texture.height,
            debug_texture.channels,
        );
        try self.vk_renderer.upload_texture_to_gpu(
            &self.gpu_debug_texture,
            debug_texture,
        );

        const letter_a_texture = self.texture_store.get(self.texture_letter_a);
        self.gpu_letter_a_texture = try self.vk_renderer.create_texture(
            letter_a_texture.width,
            letter_a_texture.height,
            letter_a_texture.channels,
        );
        try self.vk_renderer.upload_texture_to_gpu(
            &self.gpu_letter_a_texture,
            letter_a_texture,
        );

        const font_texture = self.texture_store.get(self.font.texture_id);
        self.gpu_font_texture = try self.vk_renderer.create_texture(
            font_texture.width,
            font_texture.height,
            font_texture.channels,
        );
        try self.vk_renderer.upload_texture_to_gpu(
            &self.gpu_font_texture,
            font_texture,
        );

        self.screen_quads_pipeline = try ScreenQuadsPipeline.init(memory, &self.vk_renderer);
        self.screen_quads_pipeline.set_textures(
            &self.vk_renderer,
            self.gpu_debug_texture.view,
            self.vk_renderer.debug_sampler,
            self.gpu_font_texture.view,
            self.vk_renderer.debug_sampler,
            self.gpu_letter_a_texture.view,
            self.vk_renderer.debug_sampler,
        );
        self.screen_quads_gpu_info = try ScreenQuadsGpuInfo.init(&self.vk_renderer, 64);

        self.mesh_pipeline = try MeshPipeline.init(memory, &self.vk_renderer);
        self.mesh_pipeline.set_texture(
            &self.vk_renderer,
            self.gpu_debug_texture.view,
            self.vk_renderer.debug_sampler,
        );
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
        events: []const Events.Event,
        width: i32,
        height: i32,
    ) void {
        const frame_alloc = memory.frame_alloc();
        self.screen_quads.reset();
        self.cube_meshes.reset();

        for (events) |event| {
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

        const tile_positions = self.tile_map.get_positions(frame_alloc);
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
            .texture_id = Texture.ID_VERT_COLOR,
            .position = .{
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
            .texture_id = Texture.ID_SOLID_COLOR,
            .position = .{
                .x = 100.0,
                .y = 300.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });

        const letter_a = self.texture_store.get(self.texture_letter_a);
        self.screen_quads.add_quad(.{
            .texture_id = self.texture_letter_a,
            .position = .{
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
                .x = @as(f32, @floatFromInt(letter_a.width)),
                .y = @as(f32, @floatFromInt(letter_a.height)),
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
    events_ptr: [*]const Events.Event,
    events_len: usize,
    memory: *Memory,
    dt: f32,
    data: ?*anyopaque,
) *anyopaque {
    memory.reset_frame();

    var events: []const Events.Event = undefined;
    events.ptr = events_ptr;
    events.len = events_len;
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

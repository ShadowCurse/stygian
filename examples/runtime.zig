const std = @import("std");
const stygian = @import("stygian_runtime");
const build_options = stygian.build_options;

const log = stygian.log;
// This configures log level for the runtime
pub const log_options = log.Options{
    .level = .Info,
};

const Tracing = stygian.tracing;
pub const tracing_options = Tracing.Options{
    .max_measurements = 256,
    .enabled = true,
};

const platform = stygian.platform;
const Window = platform.Window;

const vk = stygian.bindings.vulkan;

const Textures = stygian.textures;
const GpuTexture = stygian.vk_renderer.gpu_texture;

const Text = stygian.text;
const Font = stygian.font;
const ScreenQuads = stygian.screen_quads;

const Memory = stygian.memory;
const Events = stygian.platform.event;
const VkRenderer = stygian.vk_renderer.renderer;
const CameraController3d = stygian.camera.CameraController3d;

const _vk_screen_quads = stygian.vk_renderer.screen_quads;
const ScreenQuadsPipeline = _vk_screen_quads.ScreenQuadsPipeline;
const ScreenQuadsGpuInfo = _vk_screen_quads.ScreenQuadsGpuInfo;

const _render_mesh = stygian.vk_renderer.mesh;
const MeshPipeline = _render_mesh.MeshPipeline;
const RenderMeshInfo = _render_mesh.RenderMeshInfo;
const MeshInfo = _render_mesh.MeshInfo;

const _render_grid = stygian.vk_renderer.grid;
const GridPipeline = _render_grid.GridPipeline;
const GridPushConstant = _render_grid.GridPushConstant;

const _scene = stygian.vk_renderer.scene;
const SceneInfo = _scene.SceneInfo;

const _math = stygian.math;
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

const _mesh = stygian.mesh;
const CubeMesh = _mesh.CubeMesh;

const Runtime = struct {
    camera_controller: CameraController3d,

    texture_store: Textures.Store,
    texture_letter_a: Textures.Texture.Id,

    font: Font,
    screen_quads: ScreenQuads,

    vk_renderer: VkRenderer,
    gpu_debug_texture: GpuTexture,
    gpu_letter_a_texture: GpuTexture,
    gpu_font_texture: GpuTexture,
    screen_quads_pipeline: ScreenQuadsPipeline,
    screen_quads_gpu_info: ScreenQuadsGpuInfo,
    mesh_pipeline: MeshPipeline,
    cube_meshes: RenderMeshInfo,
    scene_info: SceneInfo,
    grid_pipeline: GridPipeline,

    const Self = @This();

    fn init(
        self: *Self,
        window: *Window,
        memory: *Memory,
    ) !void {
        self.camera_controller = CameraController3d.init();

        try self.texture_store.init(memory);
        self.font = Font.init(memory, &self.texture_store, "assets/Hack-Regular.ttf", 64);
        self.texture_letter_a = self.texture_store.load(memory, "assets/a.png");

        self.screen_quads = try ScreenQuads.init(memory, 128);
        self.vk_renderer = try VkRenderer.init(memory, window);

        const debug_texture = self.texture_store.get_texture(Textures.Texture.ID_DEBUG);
        self.gpu_debug_texture = try self.vk_renderer.create_texture(
            debug_texture.width,
            debug_texture.height,
            vk.VK_FORMAT_R8G8B8A8_SRGB,
        );
        try self.vk_renderer.upload_texture_to_gpu(
            &self.gpu_debug_texture,
            debug_texture,
        );

        const letter_a_texture = self.texture_store.get_texture(self.texture_letter_a);
        self.gpu_letter_a_texture = try self.vk_renderer.create_texture(
            letter_a_texture.width,
            letter_a_texture.height,
            vk.VK_FORMAT_R8G8B8A8_SRGB,
        );
        try self.vk_renderer.upload_texture_to_gpu(
            &self.gpu_letter_a_texture,
            letter_a_texture,
        );

        const font_texture = self.texture_store.get_texture(self.font.texture_id);
        self.gpu_font_texture = try self.vk_renderer.create_texture(
            font_texture.width,
            font_texture.height,
            vk.VK_FORMAT_R8_SRGB,
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
        self.scene_info = try SceneInfo.init(&self.vk_renderer, 10);

        self.grid_pipeline = try GridPipeline.init(memory, &self.vk_renderer);
    }

    fn run(
        self: *Self,
        window: *Window,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
    ) void {
        self.screen_quads.reset();
        self.cube_meshes.reset();
        self.scene_info.reset();
        const frame_alloc = memory.frame_alloc();

        const TracingTypes =
            struct { ScreenQuads };
        Tracing.prepare_next_frame(TracingTypes);
        Tracing.to_screen_quads(
            TracingTypes,
            frame_alloc,
            &self.screen_quads,
            &self.font,
            32.0,
        );
        Tracing.zero_current(TracingTypes);

        for (events) |event| {
            self.camera_controller.process_input(event, dt);
        }
        self.camera_controller.update(dt);

        const camera_view = self.camera_controller.transform().inverse();
        const camera_projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, @floatFromInt(window.width)) / @as(f32, @floatFromInt(window.height)),
            0.1,
            10000.0,
        );
        self.scene_info.set_camera_info(&.{
            .view = camera_view,
            .projection = camera_projection,
            .position = self.camera_controller.position,
        });
        self.scene_info.add_lights(&.{
            .{
                .position = .{ .x = 1.0, .z = 4.0 },
                .color = .RED,
                .constant = 1.0,
                .linear = 0.1,
                .quadratic = 0.032,
            },
            .{
                .position = .{ .x = -1.0, .z = 4.0 },
                .color = .GREEN,
                .constant = 1.0,
                .linear = 0.1,
                .quadratic = 0.032,
            },
            .{
                .position = .{ .y = 1.0, .z = 4.0 },
                .color = .BLUE,
                .constant = 1.0,
                .linear = 0.1,
                .quadratic = 0.032,
            },
            .{
                .position = .{ .y = -1.0, .z = 4.0 },
                .color = .WHITE,
                .constant = 1.0,
                .linear = 0.1,
                .quadratic = 0.032,
            },
        });

        self.screen_quads_gpu_info.set_screen_size(
            .{ .x = @floatFromInt(window.width), .y = @floatFromInt(window.height) },
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
        self.cube_meshes.set_scene_push_constants(&self.scene_info.push_constants);

        const mesh_positions = frame_alloc.alloc(MeshInfo, 16) catch unreachable;
        for (mesh_positions, 0..) |*mp, i| {
            const i_f32: f32 = @floatFromInt(i);
            const a = Vec2.X.rotate(i_f32 * std.math.pi / 8.0).mul_f32(10.0);
            mp.transform = Mat4.IDENDITY.translate(
                .{ .x = a.x, .y = a.y },
            );
        }

        self.cube_meshes.add_instance_infos(mesh_positions);

        const text_fps = Text.init(
            &self.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            32.0,
            .{
                .x = @as(f32, @floatFromInt(window.width)) / 2.0 - 100.0,
                .y = @as(f32, @floatFromInt(window.height)) / 2.0 + 300.0,
            },
            0.0,
            .{},
            null,
            .{},
        );
        text_fps.to_screen_quads(frame_alloc, &self.screen_quads);

        const frame_memory_text = Text.init(
            &self.font,
            std.fmt.allocPrint(
                memory.frame_alloc(),
                "FM: {} bytes",
                .{memory.frame_allocator.end_index},
            ) catch unreachable,
            16.0,
            .{
                .x = @as(f32, @floatFromInt(window.width)) / 2.0 - 100.0,
                .y = @as(f32, @floatFromInt(window.height)) / 2.0 + 250.0,
            },
            @sin(A.a) * 0.25,
            .{},
            .GREEN,
            .{},
        );
        frame_memory_text.to_screen_quads(frame_alloc, &self.screen_quads);

        self.screen_quads.add_quad(.{
            .texture_id = Textures.Texture.ID_VERT_COLOR,
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
            .color = .MAGENTA,
            .texture_id = Textures.Texture.ID_SOLID_COLOR,
            .position = .{
                .x = 100.0,
                .y = 300.0,
            },
            .size = .{
                .x = 200.0,
                .y = 200.0,
            },
        });

        const letter_a = self.texture_store.get_texture(self.texture_letter_a);
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

        const grid_push_constant = GridPushConstant{
            .camera_info_buffer_address = self.scene_info.push_constants.camera_buffer_address,
        };

        const frame_context = self.vk_renderer.start_frame_context() catch unreachable;
        self.vk_renderer.start_rendering(&frame_context) catch unreachable;
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
        self.grid_pipeline.render(&frame_context, &grid_push_constant);
        self.vk_renderer.end_rendering(&frame_context) catch unreachable;

        self.vk_renderer.transition_swap_chain(&frame_context);
        self.vk_renderer.end_frame_context(&frame_context) catch unreachable;
        self.vk_renderer.queue_frame_context(&frame_context) catch unreachable;
        self.vk_renderer.present_frame_context(&frame_context) catch unreachable;
    }
};

pub export fn runtime_main(
    window: *Window,
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

    if (runtime_ptr == null) {
        log.info(@src(), "First time runtime init", .{});
        const game_alloc = memory.game_alloc();
        runtime_ptr = &(game_alloc.alloc(Runtime, 1) catch unreachable)[0];
        runtime_ptr.?.init(window, memory) catch unreachable;
    } else {
        var runtime = runtime_ptr.?;
        runtime.run(window, memory, dt, events);
    }
    return @ptrCast(runtime_ptr);
}

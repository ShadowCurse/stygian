const std = @import("std");
const stygian = @import("stygian_runtime");
const build_options = stygian.build_options;

const log = stygian.log;
// This configures log level for the runtime
pub const log_options = log.Options{
    .level = .Debug,
};

const Allocator = std.mem.Allocator;

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
const GpuBuffer = stygian.vk_renderer.gpu_buffer;
const Pipeline = stygian.vk_renderer.pipeline.Pipeline;

const Memory = stygian.memory;
const Events = stygian.platform.event;
const VkRenderer = stygian.vk_renderer.renderer;

const ColorU32 = stygian.color.ColorU32;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _mesh = stygian.mesh;
const CubeMesh = _mesh.CubeMesh;

const Circle = extern struct {
    center: Vec2,
    radius: f32,
    color: ColorU32,
};

pub const CascadesPushConstant = extern struct {
    cascade_info_buffer_address: vk.VkDeviceAddress,
    circle_info_buffer_address: vk.VkDeviceAddress,
    screen_size: Vec2,
    circles_num: u32,
    level: u32,
    cmd: u32,
};

pub const CascadesGpuInfo = struct {
    cascades_info_buffer: GpuBuffer,
    circles_info_buffer: GpuBuffer,
    push_constants: CascadesPushConstant,

    const Self = @This();

    pub fn init(renderer: *VkRenderer, cascades: u32, circles: u32) !Self {
        const cascade_info_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(Cascade) * cascades,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        const circles_info_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(Circle) * circles,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        const push_constants: CascadesPushConstant = .{
            .cascade_info_buffer_address = cascade_info_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .circle_info_buffer_address = circles_info_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .circles_num = circles,
            .screen_size = .{},
            .level = 0,
            .cmd = 0,
        };

        return .{
            .cascades_info_buffer = cascade_info_buffer,
            .circles_info_buffer = circles_info_buffer,
            .push_constants = push_constants,
        };
    }

    pub fn set_screen_size(self: *CascadesGpuInfo, screen_size: Vec2) void {
        self.push_constants.screen_size = screen_size;
    }

    pub fn set_level_cmd(self: *CascadesGpuInfo, level: u32, cmd: u32) void {
        self.push_constants.level = level;
        self.push_constants.cmd = cmd;
    }

    pub fn set_cascades_infos(self: *const CascadesGpuInfo, infos: []const Cascade) void {
        var info_slice: []Cascade = undefined;
        info_slice.ptr = @alignCast(
            @ptrCast(self.cascades_info_buffer.allocation_info.pMappedData),
        );
        info_slice.len = infos.len;
        @memcpy(info_slice, infos);
    }

    pub fn set_circles_infos(self: *const CascadesGpuInfo, infos: []const Circle) void {
        var info_slice: []Circle = undefined;
        info_slice.ptr = @alignCast(
            @ptrCast(self.circles_info_buffer.allocation_info.pMappedData),
        );
        info_slice.len = infos.len;
        @memcpy(info_slice, infos);
    }
};

const Cascade = extern struct {
    point_offset: f32,
    ray_length: f32,
    sample_size: u32,
    samples_per_row: u32,
    samples_per_column: u32,

    // The screen size is `width` and `height`
    // The resolution in ELEMENTS of the level_0 cascade is `width / 2` and `height / 2`
    // BUT the resolution in SAMPLES is HALF again `width / 4` and `height / 4`
    // because 4 ELEMENTS are used for 4 directions
    // For highter cascades the divisor is 16, 64 and so on
    const PIXEL_SIZE = 1;
    const LEVEL_0_INTERVAL = 25.0;

    const Self = @This();

    const CascadesNeedeResult = struct {
        width: u32,
        height: u32,
        n: u32,
    };
    fn cascades_needed(width: u32, height: u32) CascadesNeedeResult {
        const c_width = @divFloor(width, Self.PIXEL_SIZE);
        const c_height = @divFloor(height, Self.PIXEL_SIZE);

        // nuber of cascades is dependent on the screen size
        const diagonal = @sqrt(@as(f32, @floatFromInt(width * width)) +
            @as(f32, @floatFromInt(height * height)));
        const n: u32 =
            @intFromFloat(@ceil(std.math.log(f32, 4, diagonal / Self.LEVEL_0_INTERVAL)));
        return .{
            .width = c_width,
            .height = c_height,
            .n = n,
        };
    }

    fn init(width: u32, height: u32, level: u32) Self {
        // For each level the rays have an offset from the center of the sample and
        // a maximum distance the ray samples at. Each level must have 2 times longer ray length
        // and 2 times more granual angular stepping.
        const point_offset = (LEVEL_0_INTERVAL *
            (1.0 - @as(f32, @floatFromInt(std.math.pow(u32, 4, level))))) / -3.0;
        const ray_length = LEVEL_0_INTERVAL *
            @as(f32, @floatFromInt(std.math.pow(u32, 4, level)));
        // The amount of samples can fit in the cascade data layer is inverse proportional to
        // the level;
        // level 0 uses 4 elements (4 angles), so divisor will be 2 (for width and height)
        // level 1 uses 16 enements, so divisor will be 4
        const sample_size = std.math.pow(u32, 2, 1 + level);
        const samples_per_row = width / sample_size;
        const samples_per_column = height / sample_size;

        return .{
            .point_offset = point_offset,
            .ray_length = ray_length,
            .sample_size = sample_size,
            .samples_per_row = samples_per_row,
            .samples_per_column = samples_per_column,
        };
    }
};

const Runtime = struct {
    vk_renderer: VkRenderer,

    pipeline: Pipeline,
    descriptor_set_merge_1: vk.VkDescriptorSet,
    descriptor_set_merge_0: vk.VkDescriptorSet,
    descriptor_set_draw: vk.VkDescriptorSet,
    cascades_gpu_info: CascadesGpuInfo,
    sample_textures: []GpuTexture,
    merge_textures: []GpuTexture,
    cascades: []Cascade,

    const Self = @This();

    fn init(
        self: *Self,
        window: *Window,
        memory: *Memory,
    ) !void {
        const game_alloc = memory.game_alloc();

        self.vk_renderer = try VkRenderer.init(memory, window);

        self.sample_textures = try game_alloc.alloc(GpuTexture, 3);
        self.merge_textures = try game_alloc.alloc(GpuTexture, 2);
        self.cascades = try game_alloc.alloc(Cascade, 3);

        // Create textures for pipeline.
        // Sample textures: Each sample texture is used for separate layer of cascades
        // Merge textures: These are used as targets for cascades merge results.
        const cascades_info = Cascade.cascades_needed(window.width, window.height);
        for (self.sample_textures, self.cascades, 0..) |*ct, *c, level| {
            ct.* = try self.vk_renderer.create_texture(
                cascades_info.width,
                cascades_info.height,
                vk.VK_FORMAT_B8G8R8A8_UNORM,
            );
            c.* = Cascade.init(
                cascades_info.width,
                cascades_info.height,
                @intCast(level),
            );
        }
        for (self.merge_textures) |*ct| {
            ct.* = try self.vk_renderer.create_texture(
                cascades_info.width,
                cascades_info.height,
                vk.VK_FORMAT_B8G8R8A8_UNORM,
            );
        }

        // There is only 1 pipeline which has 3 functions: sample, merge, draw
        self.pipeline = try self.vk_renderer.vk_context.create_pipeline(
            memory,
            &.{
                // Texture array
                .{
                    .binding = 0,
                    .descriptorCount = 3,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            &.{
                vk.VkPushConstantRange{
                    .offset = 0,
                    .size = @sizeOf(CascadesGpuInfo),
                    .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            "radiance_cascades_vert.spv",
            "radiance_cascades_frag.spv",
            vk.VK_FORMAT_B8G8R8A8_UNORM,
            vk.VK_FORMAT_D32_SFLOAT,
            .Alpha,
        );

        // Create descriptor sets.
        // With one in pipeline object, there are 4 descriptor sets.
        // Here we create remaining 3.
        {
            var sets: [3]vk.VkDescriptorSet = undefined;
            var layouts = [3]vk.VkDescriptorSetLayout{
                self.pipeline.descriptor_set_layout,
                self.pipeline.descriptor_set_layout,
                self.pipeline.descriptor_set_layout,
            };
            const set_alloc_info = vk.VkDescriptorSetAllocateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .descriptorPool = self.vk_renderer.vk_context.descriptor_pool.pool,
                .pSetLayouts = @ptrCast(&layouts),
                .descriptorSetCount = sets.len,
            };
            try vk.check_result(vk.vkAllocateDescriptorSets(
                self.vk_renderer.vk_context.logical_device.device,
                &set_alloc_info,
                @ptrCast(&sets),
                // &self.descriptor_set_merge_1,
            ));
            self.descriptor_set_merge_0 = sets[0];
            self.descriptor_set_merge_1 = sets[1];
            self.descriptor_set_draw = sets[2];
        }

        // The reason all descriptor sets have 3 textures is to simplify logic of selection
        // of the cascade layer. Otherwise maximum of only 2 textures are sampled at a single step.
        //
        // Desriptor set in pipeline object are not useful, but it still need to be updated.
        // Here we just bind all sample textures with ATTACHMENT_OPTIMAL layout.
        {
            const desc_image_info_layer_1: [3]vk.VkDescriptorImageInfo = .{
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
                    .imageView = self.sample_textures[0].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
                    .imageView = self.sample_textures[1].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
                    .imageView = self.sample_textures[2].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
            };
            const desc_image_write_1 = vk.VkWriteDescriptorSet{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstBinding = 0,
                .dstSet = self.pipeline.descriptor_set,
                .dstArrayElement = 0,
                .descriptorCount = @intCast(desc_image_info_layer_1.len),
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &desc_image_info_layer_1,
            };
            const updates = [_]vk.VkWriteDescriptorSet{
                desc_image_write_1,
            };
            vk.vkUpdateDescriptorSets(
                self.vk_renderer.vk_context.logical_device.device,
                updates.len,
                @ptrCast(&updates),
                0,
                null,
            );
        }
        // For the first merge step we merge sample_texture[1] and sample_texture[2]
        // The only difference from pipeline descriptor set is the image layout.
        {
            log.info(@src(), "Update descriptor_merge_1", .{});
            const desc_image_info_layer_1: [3]vk.VkDescriptorImageInfo = .{
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.sample_textures[0].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.sample_textures[1].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.sample_textures[2].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
            };
            const desc_image_write_1 = vk.VkWriteDescriptorSet{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstBinding = 0,
                .dstSet = self.descriptor_set_merge_1,
                .dstArrayElement = 0,
                .descriptorCount = @intCast(desc_image_info_layer_1.len),
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &desc_image_info_layer_1,
            };
            const updates = [_]vk.VkWriteDescriptorSet{
                desc_image_write_1,
            };
            vk.vkUpdateDescriptorSets(
                self.vk_renderer.vk_context.logical_device.device,
                updates.len,
                @ptrCast(&updates),
                0,
                null,
            );
        }
        // For the second merge step we merge sample_texture[0] and merge_texture[1]
        {
            log.info(@src(), "Update descriptor_merge_0", .{});
            const desc_image_info_layer_1: [3]vk.VkDescriptorImageInfo = .{
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.sample_textures[0].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.merge_textures[1].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.sample_textures[2].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
            };
            const desc_image_write_1 = vk.VkWriteDescriptorSet{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstBinding = 0,
                .dstSet = self.descriptor_set_merge_0,
                .dstArrayElement = 0,
                .descriptorCount = @intCast(desc_image_info_layer_1.len),
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &desc_image_info_layer_1,
            };
            const updates = [_]vk.VkWriteDescriptorSet{
                desc_image_write_1,
            };
            vk.vkUpdateDescriptorSets(
                self.vk_renderer.vk_context.logical_device.device,
                updates.len,
                @ptrCast(&updates),
                0,
                null,
            );
        }
        // For the draw step we only need merge_texture[0], but since set needs all 3 textures,
        // just bind smth.
        {
            log.info(@src(), "Update descriptor_draw", .{});
            const desc_image_info_layer_1: [3]vk.VkDescriptorImageInfo = .{
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.merge_textures[0].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.merge_textures[1].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
                .{
                    .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    .imageView = self.sample_textures[2].view,
                    .sampler = self.vk_renderer.debug_sampler,
                },
            };
            const desc_image_write_1 = vk.VkWriteDescriptorSet{
                .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstBinding = 0,
                .dstSet = self.descriptor_set_draw,
                .dstArrayElement = 0,
                .descriptorCount = @intCast(desc_image_info_layer_1.len),
                .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .pImageInfo = &desc_image_info_layer_1,
            };
            const updates = [_]vk.VkWriteDescriptorSet{
                desc_image_write_1,
            };
            vk.vkUpdateDescriptorSets(
                self.vk_renderer.vk_context.logical_device.device,
                updates.len,
                @ptrCast(&updates),
                0,
                null,
            );
        }

        // This is a simple scene layout with several light emitting circles.
        self.cascades_gpu_info = try CascadesGpuInfo.init(&self.vk_renderer, 4, 4);
        self.cascades_gpu_info.set_cascades_infos(self.cascades);
        const circles = [_]Circle{
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(window.width)) / 2.0,
                    .y = @as(f32, @floatFromInt(window.height)) / 2.0,
                },
                .radius = 25.0,
                .color = ColorU32.ORANGE.swap_rgba_bgra(),
            },
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(window.width)) / 2.0,
                    .y = @as(f32, @floatFromInt(window.height)) / 2.0 - 100.0,
                },
                .radius = 50.0,
                .color = ColorU32.WHITE.swap_rgba_bgra(),
            },
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(window.width)) / 2.0,
                    .y = @as(f32, @floatFromInt(window.height)) / 2.0 + 100.0,
                },
                .radius = 30.0,
                .color = ColorU32.BLUE.swap_rgba_bgra(),
            },
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(window.width)) / 2.0 + 100.0,
                    .y = @as(f32, @floatFromInt(window.height)) / 2.0,
                },
                .radius = 40.0,
                .color = ColorU32.NONE.swap_rgba_bgra(),
            },
        };
        self.cascades_gpu_info.set_circles_infos(&circles);
        self.cascades_gpu_info.set_screen_size(
            .{ .x = @floatFromInt(cascades_info.width), .y = @floatFromInt(cascades_info.height) },
        );
    }

    fn run(
        self: *Self,
        window: *Window,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
    ) !void {
        _ = window;
        _ = memory;
        _ = dt;
        _ = events;

        const frame_context = try self.vk_renderer.start_frame_context();

        for (self.sample_textures) |*ct| {
            GpuTexture.transition_image(
                frame_context.command.cmd,
                ct.image,
                vk.VK_IMAGE_LAYOUT_UNDEFINED,
                vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
            );
        }

        vk.vkCmdBindPipeline(
            frame_context.command.cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline.pipeline,
        );
        vk.vkCmdBindDescriptorSets(
            frame_context.command.cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.pipeline.pipeline_layout,
            0,
            1,
            &self.pipeline.descriptor_set,
            0,
            null,
        );

        // Sample step. Go over all cascade layers and sample the scene.
        for (self.sample_textures, 0..) |*ct, i| {
            try self.vk_renderer.start_rendering_to_target(
                &frame_context,
                ct,
                true,
            );

            self.cascades_gpu_info.set_level_cmd(@intCast(i), 0);
            vk.vkCmdPushConstants(
                frame_context.command.cmd,
                self.pipeline.pipeline_layout,
                vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                0,
                @sizeOf(CascadesPushConstant),
                &self.cascades_gpu_info.push_constants,
            );
            vk.vkCmdDraw(frame_context.command.cmd, 6, 1, 0, 0);

            try self.vk_renderer.end_rendering_to_target(&frame_context);
        }

        for (self.sample_textures) |*ct| {
            GpuTexture.transition_image(
                frame_context.command.cmd,
                ct.image,
                vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
                vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            );
        }

        // First merge step. Merge cascade layers 1 and 2
        {
            vk.vkCmdBindDescriptorSets(
                frame_context.command.cmd,
                vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
                self.pipeline.pipeline_layout,
                0,
                1,
                &self.descriptor_set_merge_1,
                0,
                null,
            );
            const idx = 1;
            const ct = &self.merge_textures[idx];

            try self.vk_renderer.start_rendering_to_target(
                &frame_context,
                ct,
                false,
            );

            self.cascades_gpu_info.set_level_cmd(@intCast(idx), 1);
            vk.vkCmdPushConstants(
                frame_context.command.cmd,
                self.pipeline.pipeline_layout,
                vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                0,
                @sizeOf(CascadesPushConstant),
                &self.cascades_gpu_info.push_constants,
            );
            vk.vkCmdDraw(frame_context.command.cmd, 6, 1, 0, 0);

            try self.vk_renderer.end_rendering_to_target(&frame_context);
            GpuTexture.transition_image(
                frame_context.command.cmd,
                ct.image,
                vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
                vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            );
        }

        // Second merge step. Merge cascade layers 0 and 1
        {
            vk.vkCmdBindDescriptorSets(
                frame_context.command.cmd,
                vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
                self.pipeline.pipeline_layout,
                0,
                1,
                &self.descriptor_set_merge_0,
                0,
                null,
            );

            const idx = 0;
            const ct = &self.merge_textures[idx];

            try self.vk_renderer.start_rendering_to_target(
                &frame_context,
                ct,
                false,
            );

            self.cascades_gpu_info.set_level_cmd(@intCast(idx), 1);
            vk.vkCmdPushConstants(
                frame_context.command.cmd,
                self.pipeline.pipeline_layout,
                vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                0,
                @sizeOf(CascadesPushConstant),
                &self.cascades_gpu_info.push_constants,
            );
            vk.vkCmdDraw(frame_context.command.cmd, 6, 1, 0, 0);

            try self.vk_renderer.end_rendering_to_target(&frame_context);
            GpuTexture.transition_image(
                frame_context.command.cmd,
                ct.image,
                vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
                vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            );
        }

        // Draw step. Merge texture 0 contains final merged cascade.
        {
            vk.vkCmdBindDescriptorSets(
                frame_context.command.cmd,
                vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
                self.pipeline.pipeline_layout,
                0,
                1,
                &self.descriptor_set_draw,
                0,
                null,
            );
            try self.vk_renderer.start_rendering(&frame_context);
            self.cascades_gpu_info.set_level_cmd(0, 2);
            vk.vkCmdPushConstants(
                frame_context.command.cmd,
                self.pipeline.pipeline_layout,
                vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                0,
                @sizeOf(CascadesPushConstant),
                &self.cascades_gpu_info.push_constants,
            );
            vk.vkCmdDraw(frame_context.command.cmd, 6, 1, 0, 0);
            try self.vk_renderer.end_rendering(&frame_context);
        }

        self.vk_renderer.transition_swap_chain(&frame_context);
        try self.vk_renderer.end_frame_context(&frame_context);
        try self.vk_renderer.queue_frame_context(&frame_context);
        try self.vk_renderer.present_frame_context(&frame_context);
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
        runtime.run(window, memory, dt, events) catch unreachable;
    }
    return @ptrCast(runtime_ptr);
}

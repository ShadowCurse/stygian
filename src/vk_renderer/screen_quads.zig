const log = @import("../log.zig");
const vk = @import("../bindings/vulkan.zig");

const VkRenderer = @import("renderer.zig");
const FrameContext = VkRenderer.FrameContext;

const Memory = @import("../memory.zig");
const GpuBuffer = @import("gpu_buffer.zig");
const Pipeline = @import("pipeline.zig").Pipeline;

const ScreenQuad = @import("../screen_quads.zig").ScreenQuad;

const _math = @import("../math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const GpuScreenQuadPushConstant = extern struct {
    buffer_address: vk.VkDeviceAddress,
    screen_size: Vec2,
};

pub const ScreenQuadsGpuInfo = struct {
    instance_info_buffer: GpuBuffer,
    num_instances: u32,
    push_constants: GpuScreenQuadPushConstant,

    const Self = @This();

    pub fn init(renderer: *VkRenderer, instances: u32) !Self {
        const instance_info_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(ScreenQuad) * instances,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        const push_constants: GpuScreenQuadPushConstant = .{
            .buffer_address = instance_info_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .screen_size = .{},
        };

        return .{
            .instance_info_buffer = instance_info_buffer,
            .num_instances = instances,
            .push_constants = push_constants,
        };
    }

    pub fn deinit(self: *const Self, renderer: *const VkRenderer) void {
        self.instance_info_buffer.deinit(renderer.vk_context.vma_allocator);
    }

    pub fn set_screen_size(self: *ScreenQuadsGpuInfo, screen_size: Vec2) void {
        self.push_constants.screen_size = screen_size;
    }

    pub fn set_instance_infos(self: *const ScreenQuadsGpuInfo, infos: []const ScreenQuad) void {
        var n = infos.len;
        if (self.num_instances < infos.len) {
            log.warn(
                @src(),
                "Trying to set more instances than available: {} < {}",
                .{ self.num_instances, infos.len },
            );
            n = @min(self.num_instances, infos.len);
        }
        var info_slice: []ScreenQuad = undefined;
        info_slice.ptr = @alignCast(
            @ptrCast(self.instance_info_buffer.allocation_info.pMappedData),
        );
        info_slice.len = n;
        @memcpy(info_slice, infos[0..n]);
    }
};

pub const ScreenQuadsPipeline = struct {
    pipeline: Pipeline,

    const Self = @This();

    pub fn init(memory: *Memory, renderer: *VkRenderer) !Self {
        const pipeline = try renderer.vk_context.create_pipeline(
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
                    .size = @sizeOf(GpuScreenQuadPushConstant),
                    .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            "ui_quad_vert.spv",
            "ui_quad_frag.spv",
            vk.VK_FORMAT_B8G8R8A8_UNORM,
            vk.VK_FORMAT_D32_SFLOAT,
            .Alpha,
        );

        return .{
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: *const Self, renderer: *VkRenderer) void {
        self.pipeline.deinit(renderer.vk_context.logical_device.device);
    }

    pub fn set_textures(
        self: *const Self,
        renderer: *const VkRenderer,
        debug_view: vk.VkImageView,
        debug_sampler: vk.VkSampler,
        font_view: vk.VkImageView,
        font_sampler: vk.VkSampler,
        color_view: vk.VkImageView,
        color_sampler: vk.VkSampler,
    ) void {
        const desc_image_info = [_]vk.VkDescriptorImageInfo{
            .{
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = debug_view,
                .sampler = debug_sampler,
            },
            .{
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = font_view,
                .sampler = font_sampler,
            },
            .{
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = color_view,
                .sampler = color_sampler,
            },
        };
        const desc_image_write = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 0,
            .dstSet = self.pipeline.descriptor_set,
            .dstArrayElement = 0,
            .descriptorCount = desc_image_info.len,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        const updates = [_]vk.VkWriteDescriptorSet{desc_image_write};
        vk.vkUpdateDescriptorSets(
            renderer.vk_context.logical_device.device,
            updates.len,
            @ptrCast(&updates),
            0,
            null,
        );
    }

    pub const Bundle = struct { *const ScreenQuadsGpuInfo, u32 };
    pub fn render(
        self: *const Self,
        frame_context: *const FrameContext,
        bundles: []const Bundle,
    ) void {
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
        for (bundles) |bundle| {
            vk.vkCmdPushConstants(
                frame_context.command.cmd,
                self.pipeline.pipeline_layout,
                vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                0,
                @sizeOf(GpuScreenQuadPushConstant),
                &bundle[0].push_constants,
            );
            vk.vkCmdDraw(frame_context.command.cmd, 6, bundle[1], 0, 0);
        }
    }
};

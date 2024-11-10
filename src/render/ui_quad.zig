const vk = @import("../vulkan.zig");

const VkRenderer = @import("vk_renderer.zig");
const FrameContext = VkRenderer.FrameContext;

const GpuBuffer = @import("gpu_buffer.zig");
const Pipeline = @import("pipeline.zig").Pipeline;

const _math = @import("../math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const UiQuadPushConstant = extern struct {
    buffer_address: vk.VkDeviceAddress,
};
pub const UiQuadInfo = extern struct {
    color: Vec3 = .{},
    type: UiQuadType = .VertColor,
    pos: Vec2 = .{},
    scale: Vec2 = .{},
    uv_pos: Vec2 = .{},
    uv_scale: Vec2 = .{},
};
pub const UiQuadType = enum(u32) {
    VertColor = 0,
    SolidColor = 1,
    Texture = 2,
    Font = 3,
};

pub const RenderUiQuadInfo = struct {
    instance_info_buffer: GpuBuffer,
    num_instances: u32,
    push_constants: UiQuadPushConstant,

    const Self = @This();

    pub fn init(renderer: *VkRenderer, instances: u32) !Self {
        const instance_info_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(UiQuadInfo) * instances,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        const push_constants: UiQuadPushConstant = .{
            .buffer_address = instance_info_buffer.get_device_address(renderer.vk_context.logical_device.device),
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

    pub fn set_instance_info(self: *const RenderUiQuadInfo, index: u32, info: UiQuadInfo) void {
        var info_slice: []UiQuadInfo = undefined;
        info_slice.ptr = @alignCast(@ptrCast(self.instance_info_buffer.allocation_info.pMappedData));
        info_slice.len = self.num_instances;
        info_slice[index] = info;
    }
};

pub const UiQuadPipeline = struct {
    pipeline: Pipeline,

    const Self = @This();

    pub fn init(renderer: *VkRenderer) !Self {
        const pipeline = try renderer.vk_context.create_pipeline(
            &.{
                // Color texture
                .{
                    .binding = 0,
                    .descriptorCount = 1,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
                // Font texture
                .{
                    .binding = 1,
                    .descriptorCount = 1,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            &.{
                vk.VkPushConstantRange{
                    .offset = 0,
                    .size = @sizeOf(UiQuadPushConstant),
                    .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            "ui_quad_vert.spv",
            "ui_quad_frag.spv",
            vk.VK_FORMAT_R16G16B16A16_SFLOAT,
            vk.VK_FORMAT_D32_SFLOAT,
            .Alpha,
        );

        const desc_image_info = vk.VkDescriptorImageInfo{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = renderer.debug_texture.view,
            .sampler = renderer.debug_sampler,
        };
        const color_desc_set_update = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 0,
            .dstSet = pipeline.descriptor_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        const font_desc_set_update = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 1,
            .dstSet = pipeline.descriptor_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        const updates = [_]vk.VkWriteDescriptorSet{ color_desc_set_update, font_desc_set_update };
        vk.vkUpdateDescriptorSets(renderer.vk_context.logical_device.device, updates.len, @ptrCast(&updates), 0, null);

        return .{
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: *const Self, renderer: *VkRenderer) void {
        self.pipeline.deinit(renderer.vk_context.logical_device.device);
    }

    pub fn set_color_texture(self: *const Self, renderer: *const VkRenderer, view: vk.VkImageView, sampler: vk.VkSampler) void {
        const desc_image_info = vk.VkDescriptorImageInfo{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = view,
            .sampler = sampler,
        };
        const desc_image_write = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 0,
            .dstSet = self.pipeline.descriptor_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        const updates = [_]vk.VkWriteDescriptorSet{desc_image_write};
        vk.vkUpdateDescriptorSets(renderer.vk_context.logical_device.device, updates.len, @ptrCast(&updates), 0, null);
    }

    pub fn set_font_texture(self: *const Self, renderer: *const VkRenderer, view: vk.VkImageView, sampler: vk.VkSampler) void {
        const desc_image_info = vk.VkDescriptorImageInfo{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = view,
            .sampler = sampler,
        };
        const desc_image_write = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 1,
            .dstSet = self.pipeline.descriptor_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        const updates = [_]vk.VkWriteDescriptorSet{desc_image_write};
        vk.vkUpdateDescriptorSets(renderer.vk_context.logical_device.device, updates.len, @ptrCast(&updates), 0, null);
    }

    pub const Bundle = struct { *const RenderUiQuadInfo, u32 };
    pub fn render(
        self: *const Self,
        frame_context: *const FrameContext,
        bundles: []const Bundle,
    ) void {
        vk.vkCmdBindPipeline(frame_context.command.cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline.pipeline);
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
                @sizeOf(UiQuadPushConstant),
                &bundle[0].push_constants,
            );
            vk.vkCmdDraw(frame_context.command.cmd, 6, bundle[1], 0, 0);
        }
    }
};

const std = @import("std");
const log = @import("../log.zig");
const vk = @import("../bindings/vulkan.zig");

const VkRenderer = @import("renderer.zig");
const FrameContext = VkRenderer.FrameContext;

const Memory = @import("../memory.zig");
const GpuBuffer = @import("gpu_buffer.zig");
const Pipeline = @import("pipeline.zig").Pipeline;

const _mesh = @import("../mesh.zig");
const DefaultVertex = _mesh.DefaultVertex;

const _scene = @import("scene.zig");
const SceneInfo = _scene.SceneInfo;
const ScenePushConstant = _scene.ScenePushConstant;

const _math = @import("../math.zig");
const Mat4 = _math.Mat4;

pub const MeshPushConstant = extern struct {
    vertex_buffer_address: vk.VkDeviceAddress,
    instance_info_buffer_address: vk.VkDeviceAddress,
    scene_push_constants: ScenePushConstant,
};
pub const MeshInfo = extern struct {
    transform: Mat4,
};

pub const RenderMeshInfo = struct {
    vertex_buffer: GpuBuffer,
    index_buffer: GpuBuffer,
    instance_info_buffer: GpuBuffer,
    num_instances: u32,
    num_instances_used: u32,
    num_indices: u32,
    push_constants: MeshPushConstant,

    const Self = @This();

    pub fn init(
        renderer: *VkRenderer,
        indices: []const u32,
        vertices: []const DefaultVertex,
        instances: u32,
    ) !Self {
        const vertex_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(DefaultVertex) * vertices.len,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        var vertex_slice: []DefaultVertex = undefined;
        vertex_slice.ptr = @alignCast(@ptrCast(vertex_buffer.allocation_info.pMappedData));
        vertex_slice.len = vertices.len;
        @memcpy(vertex_slice, vertices);

        const index_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(u32) * indices.len,
            vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        var index_slice: []u32 = undefined;
        index_slice.ptr = @alignCast(@ptrCast(index_buffer.allocation_info.pMappedData));
        index_slice.len = indices.len;
        @memcpy(index_slice, indices);

        const instance_info_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(MeshInfo) * instances,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        const push_constants: MeshPushConstant = .{
            .vertex_buffer_address = vertex_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .instance_info_buffer_address = instance_info_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .scene_push_constants = undefined,
        };

        return .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .instance_info_buffer = instance_info_buffer,
            .num_instances = instances,
            .num_instances_used = 0,
            .num_indices = @intCast(indices.len),
            .push_constants = push_constants,
        };
    }

    pub fn deinit(self: *Self, renderer: *const VkRenderer) void {
        self.instance_info_buffer.deinit(renderer.vk_context.vma_allocator);
        self.index_buffer.deinit(renderer.vk_context.vma_allocator);
        self.vertex_buffer.deinit(renderer.vk_context.vma_allocator);
    }

    pub fn reset(self: *Self) void {
        self.num_instances_used = 0;
    }

    pub fn add_instance_infos(self: *RenderMeshInfo, infos: []const MeshInfo) void {
        if (self.num_instances < self.num_instances_used + infos.len) {
            log.warn(
                @src(),
                "Tryingt to use more instances than available: {} < {}",
                .{ self.num_instances, self.num_instances_used + infos.len },
            );
            return;
        }
        var info_slice: []MeshInfo = undefined;
        info_slice.ptr = @alignCast(
            @ptrCast(self.instance_info_buffer.allocation_info.pMappedData),
        );
        info_slice.len = self.num_instances;
        @memcpy(
            info_slice[self.num_instances_used .. self.num_instances_used + infos.len],
            infos,
        );
        self.num_instances_used += @intCast(infos.len);
    }

    pub fn set_scene_push_constants(self: *RenderMeshInfo, spc: *const ScenePushConstant) void {
        self.push_constants.scene_push_constants = spc.*;
    }
};

pub const MeshPipeline = struct {
    pipeline: Pipeline,

    const Self = @This();

    pub fn init(memory: *Memory, renderer: *VkRenderer) !Self {
        const pipeline = try renderer.vk_context.create_pipeline(
            memory,
            &.{
                .{
                    .binding = 0,
                    .descriptorCount = 1,
                    .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            &.{
                vk.VkPushConstantRange{
                    .offset = 0,
                    .size = @sizeOf(MeshPushConstant),
                    .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            "mesh_vert.spv",
            "mesh_frag.spv",
            vk.VK_FORMAT_B8G8R8A8_UNORM,
            vk.VK_FORMAT_D32_SFLOAT,
            .None,
        );

        return .{
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: *const Self, renderer: *VkRenderer) void {
        self.pipeline.deinit(renderer.vk_context.logical_device.device);
    }

    pub fn set_texture(
        self: *const Self,
        renderer: *const VkRenderer,
        view: vk.VkImageView,
        sampler: vk.VkSampler,
    ) void {
        const desc_image_info = vk.VkDescriptorImageInfo{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = view,
            .sampler = sampler,
        };
        const mesh_desc_set_update = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 0,
            .dstSet = self.pipeline.descriptor_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        const updates = [_]vk.VkWriteDescriptorSet{mesh_desc_set_update};
        vk.vkUpdateDescriptorSets(
            renderer.vk_context.logical_device.device,
            updates.len,
            @ptrCast(&updates),
            0,
            null,
        );
    }

    pub const Bundle = struct { *const RenderMeshInfo, u32 };
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
                @sizeOf(MeshPushConstant),
                &bundle[0].push_constants,
            );
            vk.vkCmdBindIndexBuffer(
                frame_context.command.cmd,
                bundle[0].index_buffer.buffer,
                0,
                vk.VK_INDEX_TYPE_UINT32,
            );
            vk.vkCmdDrawIndexed(
                frame_context.command.cmd,
                bundle[0].num_indices,
                bundle[1],
                0,
                0,
                0,
            );
        }
    }
};

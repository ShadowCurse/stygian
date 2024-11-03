const std = @import("std");
const log = @import("../log.zig");
const vk = @import("../vulkan.zig");
const sdl = @import("../sdl.zig");
const stb = @import("../stb.zig");

const Image = @import("../image.zig");
const Color = @import("../color.zig").Color;
const Memory = @import("../memory.zig");

const VkContext = @import("vk_context.zig");
const RenderCommand = VkContext.RenderCommand;
const ImmediateCommand = VkContext.ImmediateCommand;

const AllocatedImage = @import("image.zig").AllocatedImage;
const AllocatedBuffer = @import("buffer.zig").AllocatedBuffer;

const Pipeline = @import("pipeline.zig").Pipeline;

const _image = @import("image.zig");

const _mesh = @import("../mesh.zig");
const DefaultVertex = _mesh.DefaultVertex;

const _math = @import("../math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const UiQuadPushConstant = extern struct {
    buffer_address: vk.VkDeviceAddress,
};
pub const UiQuadInfo = extern struct {
    transform: Mat4,
    color: Vec3,
    type: UiQuadType,
};
pub const UiQuadType = enum(u32) {
    VertColor = 0,
    SolidColor = 1,
    Texture = 2,
};

pub const MeshPushConstant = extern struct {
    view_proj: Mat4,
    vertex_buffer_address: vk.VkDeviceAddress,
    instance_info_buffer_address: vk.VkDeviceAddress,
};
pub const MeshInfo = extern struct {
    transform: Mat4,
};

const FRAMES = 2;

const Self = @This();
window_width: u32,
window_height: u32,

vk_context: VkContext,
draw_image: AllocatedImage,
depth_image: AllocatedImage,

current_framme_idx: usize,
commands: [FRAMES]RenderCommand,
immediate_command: ImmediateCommand,

ui_quad_pipeline: Pipeline,
mesh_pipeline: Pipeline,

debug_texture: AllocatedImage,
debug_sampler: vk.VkSampler,

pub fn init(
    memory: *Memory,
    width: u32,
    height: u32,
) !Self {
    var vk_context = try VkContext.init(memory, width, height);

    const draw_image = try vk_context.create_image(
        vk_context.swap_chain.extent.width,
        vk_context.swap_chain.extent.height,
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
        vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    );

    const depth_image = try vk_context.create_image(
        vk_context.swap_chain.extent.width,
        vk_context.swap_chain.extent.height,
        vk.VK_FORMAT_D32_SFLOAT,
        vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
    );

    const commands = [_]RenderCommand{
        try vk_context.create_render_command(),
        try vk_context.create_render_command(),
    };

    const immediate_command = try vk_context.create_immediate_command();

    const ui_quad_pipeline = try vk_context.create_pipeline(
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

    const mesh_pipeline = try vk_context.create_pipeline(
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
                .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            },
        },
        "mesh_vert.spv",
        "mesh_frag.spv",
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
        vk.VK_FORMAT_D32_SFLOAT,
        .None,
    );

    const debug_texture = try vk_context.create_image(
        16,
        16,
        vk.VK_FORMAT_B8G8R8A8_UNORM,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
    );

    {
        const staging_buffer = try vk_context.create_buffer(
            16 * 16 * @sizeOf(Color),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        defer staging_buffer.deinit(vk_context.vma_allocator);

        var buffer_slice: []Color = undefined;
        buffer_slice.ptr = @alignCast(@ptrCast(staging_buffer.allocation_info.pMappedData));
        buffer_slice.len = 16 * 16;

        for (0..16) |x| {
            for (0..16) |y| {
                buffer_slice[y * 16 + x] = if ((x % 2) ^ (y % 2) != 0) Color.MAGENTA else Color.GREY;
            }
        }

        try immediate_command.begin(vk_context.logical_device.device);
        defer immediate_command.end(
            vk_context.logical_device.device,
            vk_context.logical_device.graphics_queue,
        ) catch @panic("immediate_command error");

        _image.copy_buffer_to_image(
            immediate_command.cmd,
            staging_buffer.buffer,
            debug_texture.image,
            .{
                .height = 16,
                .width = 16,
                .depth = 1,
            },
        );
    }
    const debug_sampler = try vk_context.create_sampler(vk.VK_FILTER_NEAREST, vk.VK_FILTER_NEAREST);

    const desc_image_info = vk.VkDescriptorImageInfo{
        .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = debug_texture.view,
        .sampler = debug_sampler,
    };
    const mesh_desc_set_update = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = mesh_pipeline.descriptor_set,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &desc_image_info,
    };
    const ui_quad_desc_set_update = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = ui_quad_pipeline.descriptor_set,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &desc_image_info,
    };
    const updates = [_]vk.VkWriteDescriptorSet{ mesh_desc_set_update, ui_quad_desc_set_update };
    vk.vkUpdateDescriptorSets(vk_context.logical_device.device, updates.len, @ptrCast(&updates), 0, null);

    return .{
        .window_width = width,
        .window_height = height,
        .vk_context = vk_context,
        .draw_image = draw_image,
        .depth_image = depth_image,
        .current_framme_idx = 0,
        .commands = commands,
        .immediate_command = immediate_command,
        .ui_quad_pipeline = ui_quad_pipeline,
        .mesh_pipeline = mesh_pipeline,
        .debug_texture = debug_texture,
        .debug_sampler = debug_sampler,
    };
}

pub fn deinit(self: *Self) void {
    vk.vkDestroySampler(self.vk_context.logical_device.device, self.debug_sampler, null);
    self.debug_texture.deinit(self.vk_context.logical_device.device, self.vk_context.vma_allocator);

    self.mesh_pipeline.deinit(self.vk_context.logical_device.device);
    self.ui_quad_pipeline.deinit(self.vk_context.logical_device.device);

    self.immediate_command.deinit(self.vk_context.logical_device.device);
    for (&self.commands) |*c| {
        c.deinit(self.vk_context.logical_device.device);
    }

    self.depth_image.deinit(self.vk_context.logical_device.device, self.vk_context.vma_allocator);
    self.draw_image.deinit(self.vk_context.logical_device.device, self.vk_context.vma_allocator);

    self.vk_context.deinit();
}

pub const RenderMeshInfo = struct {
    vertex_buffer: AllocatedBuffer,
    index_buffer: AllocatedBuffer,
    instance_info_buffer: AllocatedBuffer,
    num_instances: u32,
    num_indices: u32,
    push_constants: MeshPushConstant,

    pub fn set_instance_info(self: *const RenderMeshInfo, index: u32, info: MeshInfo) void {
        var info_slice: []MeshInfo = undefined;
        info_slice.ptr = @alignCast(@ptrCast(self.instance_info_buffer.allocation_info.pMappedData));
        info_slice.len = self.num_instances;
        info_slice[index] = info;
    }
};

pub fn create_texture(self: *Self, width: u32, height: u32) !AllocatedImage {
    return try self.vk_context.create_image(
        width,
        height,
        // vk.VK_FORMAT_B8G8R8A8_UNORM,
        vk.VK_FORMAT_R8G8B8A8_SRGB,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
    );
}

pub fn delete_texture(self: *Self, texture: *const AllocatedImage) void {
    self.vk_context.delete_image(texture);
}

pub fn upload_texture_image(self: *Self, texture: *const AllocatedImage, image: *const Image) !void {
    if ((vk.VK_FORMAT_R8G8B8A8_UNORM <= texture.format and texture.format <= vk.VK_FORMAT_A2B10G10R10_SINT_PACK32) and
        image.channels != 4)
    {
        return error.TextureAndImageIncopatibleChannelDepth;
    }

    const staging_buffer = try self.vk_context.create_buffer(
        image.width * image.height * image.channels,
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer staging_buffer.deinit(self.vk_context.vma_allocator);

    var buffer_slice: []u8 = undefined;
    buffer_slice.ptr = @alignCast(@ptrCast(staging_buffer.allocation_info.pMappedData));
    buffer_slice.len = image.width * image.height * image.channels;
    @memcpy(buffer_slice, image.data);

    try self.immediate_command.begin(self.vk_context.logical_device.device);
    defer self.immediate_command.end(
        self.vk_context.logical_device.device,
        self.vk_context.logical_device.graphics_queue,
    ) catch @panic("immediate_command error");

    _image.copy_buffer_to_image(
        self.immediate_command.cmd,
        staging_buffer.buffer,
        texture.image,
        .{
            .height = image.height,
            .width = image.width,
            .depth = 1,
        },
    );
}

pub fn create_mesh(self: *Self, indices: []const u32, vertices: []const DefaultVertex, instances: u32) !RenderMeshInfo {
    const vertex_buffer = try self.vk_context.create_buffer(
        @sizeOf(DefaultVertex) * vertices.len,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    var vertex_slice: []DefaultVertex = undefined;
    vertex_slice.ptr = @alignCast(@ptrCast(vertex_buffer.allocation_info.pMappedData));
    vertex_slice.len = vertices.len;
    @memcpy(vertex_slice, vertices);

    const index_buffer = try self.vk_context.create_buffer(
        @sizeOf(u32) * indices.len,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    var index_slice: []u32 = undefined;
    index_slice.ptr = @alignCast(@ptrCast(index_buffer.allocation_info.pMappedData));
    index_slice.len = indices.len;
    @memcpy(index_slice, indices);

    const instance_info_buffer = try self.vk_context.create_buffer(
        @sizeOf(MeshInfo) * instances,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    const push_constants: MeshPushConstant = .{
        .view_proj = undefined,
        .vertex_buffer_address = vertex_buffer.get_device_address(self.vk_context.logical_device.device),
        .instance_info_buffer_address = instance_info_buffer.get_device_address(self.vk_context.logical_device.device),
    };

    return .{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .instance_info_buffer = instance_info_buffer,
        .num_instances = instances,
        .num_indices = @intCast(indices.len),
        .push_constants = push_constants,
    };
}

pub fn delete_mesh(self: *Self, render_mesh_info: *const RenderMeshInfo) void {
    render_mesh_info.instance_info_buffer.deinit(self.vk_context.vma_allocator);
    render_mesh_info.index_buffer.deinit(self.vk_context.vma_allocator);
    render_mesh_info.vertex_buffer.deinit(self.vk_context.vma_allocator);
}

pub const RenderUiQuadInfo = struct {
    instance_info_buffer: AllocatedBuffer,
    num_instances: u32,
    push_constants: UiQuadPushConstant,

    pub fn set_instance_info(self: *const RenderUiQuadInfo, index: u32, info: UiQuadInfo) void {
        var info_slice: []UiQuadInfo = undefined;
        info_slice.ptr = @alignCast(@ptrCast(self.instance_info_buffer.allocation_info.pMappedData));
        info_slice.len = self.num_instances;
        info_slice[index] = info;
    }
};

pub fn create_ui_quad(self: *Self, instances: u32) !RenderUiQuadInfo {
    const instance_info_buffer = try self.vk_context.create_buffer(
        @sizeOf(UiQuadInfo) * instances,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    const push_constants: UiQuadPushConstant = .{
        .buffer_address = instance_info_buffer.get_device_address(self.vk_context.logical_device.device),
    };

    return .{
        .instance_info_buffer = instance_info_buffer,
        .num_instances = instances,
        .push_constants = push_constants,
    };
}

pub fn delete_ui_quad(self: *Self, render_ui_quad_info: *const RenderUiQuadInfo) void {
    render_ui_quad_info.instance_info_buffer.deinit(self.vk_context.vma_allocator);
}

pub fn set_ui_quad_pipeline_texture(self: *const Self, view: vk.VkImageView, sampler: vk.VkSampler) void {
    const desc_image_info = vk.VkDescriptorImageInfo{
        .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = view,
        .sampler = sampler,
    };
    const desc_image_write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = self.ui_quad_pipeline.descriptor_set,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &desc_image_info,
    };
    const updates = [_]vk.VkWriteDescriptorSet{desc_image_write};
    vk.vkUpdateDescriptorSets(self.vk_context.logical_device.device, updates.len, @ptrCast(&updates), 0, null);
}

pub const FrameContext = struct {
    command: *const RenderCommand,
    image_index: u32,
};

pub fn start_rendering(self: *const Self) !FrameContext {
    const command = &self.commands[self.current_framme_idx % self.commands.len];

    try self.vk_context.wait_for_fence(command.render_fence);
    try self.vk_context.reset_fence(command.render_fence);

    const image_index = try self.vk_context.acquire_next_image(command.swap_chain_semaphore);

    try vk.check_result(vk.vkResetCommandBuffer(command.cmd, 0));
    const begin_info = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.check_result(vk.vkBeginCommandBuffer(command.cmd, &begin_info));

    _image.transition_image(
        command.cmd,
        self.draw_image.image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
    );

    _image.transition_image(
        command.cmd,
        self.depth_image.image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
    );

    const color_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.draw_image.view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 0.0 } } },
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
    };
    const depth_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .depthStencil = .{ .depth = 0.0 } },
    };

    const render_info = vk.VkRenderingInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .pColorAttachments = &color_attachment,
        .colorAttachmentCount = 1,
        .pDepthAttachment = &depth_attachment,
        .renderArea = .{ .extent = .{
            .width = self.draw_image.extent.width,
            .height = self.draw_image.extent.height,
        } },
        .layerCount = 1,
    };
    vk.vkCmdBeginRendering(command.cmd, &render_info);

    const viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.draw_image.extent.width),
        .height = @floatFromInt(self.draw_image.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(command.cmd, 0, 1, &viewport);
    const scissor = vk.VkRect2D{ .offset = .{
        .x = 0.0,
        .y = 0.0,
    }, .extent = .{
        .width = self.draw_image.extent.width,
        .height = self.draw_image.extent.height,
    } };
    vk.vkCmdSetScissor(command.cmd, 0, 1, &scissor);

    return .{
        .command = command,
        .image_index = image_index,
    };
}

pub fn end_rendering(self: *Self, frame_context: FrameContext) !void {
    self.current_framme_idx +%= 1;

    const command = frame_context.command;
    const image_index = frame_context.image_index;

    vk.vkCmdEndRendering(command.cmd);

    _image.transition_image(
        command.cmd,
        self.draw_image.image,
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    );
    _image.transition_image(
        command.cmd,
        self.vk_context.swap_chain.images[image_index],
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );
    _image.copy_image_to_image(
        command.cmd,
        self.draw_image.image,
        .{
            .width = self.draw_image.extent.width,
            .height = self.draw_image.extent.height,
        },
        self.vk_context.swap_chain.images[image_index],
        self.vk_context.swap_chain.extent,
    );
    _image.transition_image(
        command.cmd,
        self.vk_context.swap_chain.images[image_index],
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    );

    try vk.check_result(vk.vkEndCommandBuffer(command.cmd));

    // Submit commands
    const buffer_submit_info = vk.VkCommandBufferSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = command.cmd,
        .deviceMask = 0,
    };
    const wait_semaphore_info = vk.VkSemaphoreSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = command.swap_chain_semaphore,
        .stageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    };
    const signal_semaphore_info = vk.VkSemaphoreSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = command.render_semaphore,
        .stageMask = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    };
    const submit_info = vk.VkSubmitInfo2{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .pWaitSemaphoreInfos = &wait_semaphore_info,
        .waitSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_semaphore_info,
        .signalSemaphoreInfoCount = 1,
        .pCommandBufferInfos = &buffer_submit_info,
        .commandBufferInfoCount = 1,
    };
    try self.vk_context.queue_submit_2(&submit_info, command.render_fence);

    // Present image in the screen
    const present_info = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.vk_context.swap_chain.swap_chain,
        .swapchainCount = 1,
        .pWaitSemaphores = &command.render_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };
    try self.vk_context.queue_present(&present_info);
}

pub fn render_mesh(
    self: *Self,
    frame_context: *const FrameContext,
    render_mesh_info: *const RenderMeshInfo,
    instances: u32,
) !void {
    vk.vkCmdBindPipeline(frame_context.command.cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline.pipeline);
    vk.vkCmdBindDescriptorSets(
        frame_context.command.cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.mesh_pipeline.pipeline_layout,
        0,
        1,
        &self.mesh_pipeline.descriptor_set,
        0,
        null,
    );
    vk.vkCmdPushConstants(
        frame_context.command.cmd,
        self.mesh_pipeline.pipeline_layout,
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(MeshPushConstant),
        &render_mesh_info.push_constants,
    );
    vk.vkCmdBindIndexBuffer(frame_context.command.cmd, render_mesh_info.index_buffer.buffer, 0, vk.VK_INDEX_TYPE_UINT32);
    vk.vkCmdDrawIndexed(frame_context.command.cmd, render_mesh_info.num_indices, instances, 0, 0, 0);
}

pub fn render_ui_quad(
    self: *Self,
    command: *const FrameContext,
    render_ui_quad_info: *const RenderUiQuadInfo,
    instances: u32,
) !void {
    vk.vkCmdBindPipeline(command.command.cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.ui_quad_pipeline.pipeline);
    vk.vkCmdBindDescriptorSets(
        command.command.cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.ui_quad_pipeline.pipeline_layout,
        0,
        1,
        &self.ui_quad_pipeline.descriptor_set,
        0,
        null,
    );
    vk.vkCmdPushConstants(
        command.command.cmd,
        self.ui_quad_pipeline.pipeline_layout,
        vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        0,
        @sizeOf(UiQuadPushConstant),
        &render_ui_quad_info.push_constants,
    );
    vk.vkCmdDraw(command.command.cmd, 6, instances, 0, 0);
}

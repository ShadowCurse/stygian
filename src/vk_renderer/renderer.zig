const std = @import("std");
const vk = @import("../bindings/vulkan.zig");
const log = @import("../log.zig");
const stb = @import("../bindings/stb.zig");

const platform = @import("../platform/root.zig");
const Window = platform.Window;

const Memory = @import("../memory.zig");
const Textures = @import("../textures.zig");
const Color = @import("../color.zig").Color;

const VkContext = @import("context.zig");
const RenderCommand = VkContext.RenderCommand;
const ImmediateCommand = VkContext.ImmediateCommand;

const GpuTexture = @import("gpu_texture.zig");

const FRAMES = 2;

const Self = @This();

vk_context: VkContext,
depth_texture: GpuTexture,

current_framme_idx: usize,
commands: [FRAMES]RenderCommand,
immediate_command: ImmediateCommand,

debug_sampler: vk.VkSampler,

pub fn init(
    memory: *Memory,
    window: *Window,
) !Self {
    var vk_context = try VkContext.init(memory, window);

    const depth_texture = try vk_context.create_texture(
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

    const debug_sampler = try vk_context.create_sampler(
        vk.VK_FILTER_NEAREST,
        vk.VK_FILTER_NEAREST,
    );

    return .{
        .vk_context = vk_context,
        .depth_texture = depth_texture,
        .current_framme_idx = 0,
        .commands = commands,
        .immediate_command = immediate_command,
        .debug_sampler = debug_sampler,
    };
}

pub fn deinit(self: *Self, memory: *Memory) void {
    vk.vkDestroySampler(self.vk_context.logical_device.device, self.debug_sampler, null);
    self.immediate_command.deinit(self.vk_context.logical_device.device);
    for (&self.commands) |*c| {
        c.deinit(self.vk_context.logical_device.device);
    }
    self.depth_texture.deinit(
        self.vk_context.logical_device.device,
        self.vk_context.vma_allocator,
    );

    self.vk_context.deinit(memory);
}

pub fn create_texture(self: *Self, width: u32, height: u32, format: vk.VkFormat) !GpuTexture {
    const texture = try self.vk_context.create_texture(
        width,
        height,
        format,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_SAMPLED_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    );
    log.debug(@src(), "Created texture: image: 0x{x}, view: 0x{x}", .{
        @as(usize, @intFromPtr(texture.image)),
        @as(usize, @intFromPtr(texture.view)),
    });
    return texture;
}

pub fn delete_texture(self: *Self, texture: *const GpuTexture) void {
    self.vk_context.delete_texture(texture);
}

pub fn upload_texture_to_gpu(
    self: *Self,
    gpu_texture: *const GpuTexture,
    texture: *const Textures.Texture,
) !void {
    if ((vk.VK_FORMAT_R8G8B8A8_UNORM <= gpu_texture.format and
        gpu_texture.format <= vk.VK_FORMAT_A2B10G10R10_SINT_PACK32) and
        texture.channels != 4)
    {
        return error.TextureAndImageIncopatibleChannelDepth;
    }

    const staging_buffer = try self.vk_context.create_buffer(
        texture.width * texture.height * texture.channels,
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer staging_buffer.deinit(self.vk_context.vma_allocator);

    var buffer_slice: []u8 = undefined;
    buffer_slice.ptr = @alignCast(@ptrCast(staging_buffer.allocation_info.pMappedData));
    buffer_slice.len = texture.width * texture.height * texture.channels;
    @memcpy(buffer_slice, texture.data);

    try self.immediate_command.begin(self.vk_context.logical_device.device);
    defer self.immediate_command.end(
        self.vk_context.logical_device.device,
        self.vk_context.logical_device.graphics_queue,
    ) catch @panic("immediate_command error");

    GpuTexture.copy_buffer_to_image(
        self.immediate_command.cmd,
        staging_buffer.buffer,
        gpu_texture.image,
        .{
            .height = texture.height,
            .width = texture.width,
            .depth = 1,
        },
    );
}

pub const FrameContext = struct {
    command: *const RenderCommand,
    image_index: u32,
};

pub fn start_frame_context(self: *const Self) !FrameContext {
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

    return .{
        .command = command,
        .image_index = image_index,
    };
}

pub fn end_frame_context(self: *Self, frame_context: *const FrameContext) !void {
    self.current_framme_idx +%= 1;
    try vk.check_result(vk.vkEndCommandBuffer(frame_context.command.cmd));
}

pub fn queue_frame_context(self: *Self, frame_context: *const FrameContext) !void {
    // Submit commands
    const buffer_submit_info = vk.VkCommandBufferSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = frame_context.command.cmd,
        .deviceMask = 0,
    };
    const wait_semaphore_info = vk.VkSemaphoreSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame_context.command.swap_chain_semaphore,
        .stageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    };
    const signal_semaphore_info = vk.VkSemaphoreSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame_context.command.render_semaphore,
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
    try self.vk_context.queue_submit_2(&submit_info, frame_context.command.render_fence);
}

pub fn present_frame_context(self: *Self, frame_context: *const FrameContext) !void {
    const present_info = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.vk_context.swap_chain.swap_chain,
        .swapchainCount = 1,
        .pWaitSemaphores = &frame_context.command.render_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &frame_context.image_index,
    };
    try self.vk_context.queue_present(&present_info);
}

pub fn start_rendering(self: *const Self, frame_context: *const FrameContext) !void {
    const sc_image = self.vk_context.swap_chain.images[frame_context.image_index];
    const sc_view = self.vk_context.swap_chain.image_views[frame_context.image_index];

    GpuTexture.transition_image(
        frame_context.command.cmd,
        sc_image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
    );

    GpuTexture.transition_image(
        frame_context.command.cmd,
        self.depth_texture.image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
    );

    const color_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = sc_view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 0.0 } } },
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
    };
    const depth_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_texture.view,
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
        .renderArea = .{ .extent = self.vk_context.swap_chain.extent },
        .layerCount = 1,
    };
    vk.vkCmdBeginRendering(frame_context.command.cmd, &render_info);

    const viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.vk_context.swap_chain.extent.width),
        .height = @floatFromInt(self.vk_context.swap_chain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(frame_context.command.cmd, 0, 1, &viewport);
    const scissor = vk.VkRect2D{
        .offset = .{
            .x = 0.0,
            .y = 0.0,
        },
        .extent = self.vk_context.swap_chain.extent,
    };
    vk.vkCmdSetScissor(frame_context.command.cmd, 0, 1, &scissor);
}

pub fn transition_swap_chain(self: *Self, frame_context: *const FrameContext) void {
    GpuTexture.transition_image(
        frame_context.command.cmd,
        self.vk_context.swap_chain.images[frame_context.image_index],
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    );
}

pub fn end_rendering(self: *Self, frame_context: *const FrameContext) !void {
    _ = self;
    vk.vkCmdEndRendering(frame_context.command.cmd);
}

pub fn start_rendering_to_target(
    self: *const Self,
    frame_context: *const FrameContext,
    texture: *const GpuTexture,
    clear: bool,
) !void {
    GpuTexture.transition_image(
        frame_context.command.cmd,
        texture.image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
    );

    const color_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = texture.view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = if (clear) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 0.0 } } },
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
    };
    const depth_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_texture.view,
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
        .renderArea = .{
            .extent = .{
                .width = texture.extent.width,
                .height = texture.extent.height,
            },
        },
        .layerCount = 1,
    };
    vk.vkCmdBeginRendering(frame_context.command.cmd, &render_info);

    const viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(texture.extent.width),
        .height = @floatFromInt(texture.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(frame_context.command.cmd, 0, 1, &viewport);
    const scissor = vk.VkRect2D{
        .offset = .{
            .x = 0.0,
            .y = 0.0,
        },
        .extent = .{
            .width = texture.extent.width,
            .height = texture.extent.height,
        },
    };
    vk.vkCmdSetScissor(frame_context.command.cmd, 0, 1, &scissor);
}

pub fn end_rendering_to_target(self: *Self, frame_context: *const FrameContext) !void {
    _ = self;
    vk.vkCmdEndRendering(frame_context.command.cmd);
}

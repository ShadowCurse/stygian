const std = @import("std");
const log = @import("../log.zig");
const vk = @import("../vulkan.zig");
const sdl = @import("../sdl.zig");

const Color = @import("../color.zig").Color;
const Memory = @import("../memory.zig");

const Renderer = @import("renderer.zig");
const RenderCommand = Renderer.RenderCommand;
const ImmediateCommand = Renderer.ImmediateCommand;

const AllocatedImage = @import("image.zig").AllocatedImage;
const AllocatedBuffer = @import("buffer.zig").AllocatedBuffer;

const Pipeline = @import("pipeline.zig").Pipeline;

const _image = @import("image.zig");

const _mesh = @import("../mesh.zig");
const DefaultVertex = _mesh.DefaultVertex;

const _math = @import("../math.zig");
const Mat4 = _math.Mat4;
const Vec2 = _math.Vec2;

const UiQuadPushConstant = extern struct {
    buffer_address: vk.VkDeviceAddress,
};
const UiQuadInfo = extern struct {
    transform: Mat4,
};

const MeshPushConstant = extern struct {
    view_proj: Mat4,
    buffer_address: vk.VkDeviceAddress,
};

const FRAMES = 2;

const Self = @This();
window_width: u32,
window_height: u32,
renderer: Renderer,

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
    var renderer = try Renderer.init(memory, width, height);

    const commands = [_]Renderer.RenderCommand{
        try renderer.create_render_command(),
        try renderer.create_render_command(),
    };

    const immediate_command = try renderer.create_immediate_command();

    const ui_quad_pipeline = try renderer.create_pipeline(
        &.{},
        &.{
            vk.VkPushConstantRange{
                .offset = 0,
                .size = @sizeOf(UiQuadPushConstant),
                .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            },
        },
        "ui_quad_vert.spv",
        "ui_quad_frag.spv",
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
    );

    const mesh_pipeline = try renderer.create_pipeline(
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
    );

    const debug_texture = try renderer.create_image(
        16,
        16,
        vk.VK_FORMAT_B8G8R8A8_UNORM,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
    );

    {
        const staging_buffer = try renderer.create_buffer(
            16 * 16 * @sizeOf(Color),
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        defer staging_buffer.deinit(renderer.vma_allocator);

        var buffer_slice: []Color = undefined;
        buffer_slice.ptr = @alignCast(@ptrCast(staging_buffer.allocation_info.pMappedData));
        buffer_slice.len = 16 * 16;

        for (0..16) |x| {
            for (0..16) |y| {
                buffer_slice[y * 16 + x] = if ((x % 2) ^ (y % 2) != 0) Color.MAGENTA else Color.GREY;
            }
        }

        try immediate_command.begin(renderer.logical_device.device);
        defer immediate_command.end(
            renderer.logical_device.device,
            renderer.logical_device.graphics_queue,
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
    const debug_sampler = try renderer.create_sampler(vk.VK_FILTER_NEAREST, vk.VK_FILTER_NEAREST);

    const desc_image_info = vk.VkDescriptorImageInfo{
        .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = debug_texture.view,
        .sampler = debug_sampler,
    };
    const desc_image_write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = mesh_pipeline.descriptor_set,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &desc_image_info,
    };
    const updates = [_]vk.VkWriteDescriptorSet{desc_image_write};
    vk.vkUpdateDescriptorSets(renderer.logical_device.device, updates.len, @ptrCast(&updates), 0, null);

    return .{
        .window_width = width,
        .window_height = height,
        .renderer = renderer,
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
    vk.vkDestroySampler(self.renderer.logical_device.device, self.debug_sampler, null);
    self.debug_texture.deinit(self.renderer.logical_device.device, self.renderer.vma_allocator);

    self.mesh_pipeline.deinit(self.renderer.logical_device.device);
    self.ui_quad_pipeline.deinit(self.renderer.logical_device.device);

    self.immediate_command.deinit(self.renderer.logical_device.device);
    for (&self.commands) |*c| {
        c.deinit(self.renderer.logical_device.device);
    }

    self.renderer.deinit();
}

pub const RenderMeshInfo = struct {
    vertex_buffer: AllocatedBuffer,
    index_buffer: AllocatedBuffer,
    num_indices: u32,
    push_constants: MeshPushConstant,
};

pub fn create_mesh(self: *Self, indices: []const u32, vertices: []const DefaultVertex) !RenderMeshInfo {
    const vertex_buffer = try self.renderer.create_buffer(
        @sizeOf(DefaultVertex) * vertices.len,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    // defer vertex_buffer.deinit(renderer.vma_allocator);
    var vertex_slice: []DefaultVertex = undefined;
    vertex_slice.ptr = @alignCast(@ptrCast(vertex_buffer.allocation_info.pMappedData));
    vertex_slice.len = vertices.len;
    @memcpy(vertex_slice, vertices);

    const index_buffer = try self.renderer.create_buffer(
        @sizeOf(u32) * indices.len,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    // defer index_buffer.deinit(renderer.vma_allocator);
    var index_slice: []u32 = undefined;
    index_slice.ptr = @alignCast(@ptrCast(index_buffer.allocation_info.pMappedData));
    index_slice.len = indices.len;
    @memcpy(index_slice, indices);

    const push_constants: MeshPushConstant = .{
        .view_proj = undefined,
        .buffer_address = vertex_buffer.get_device_address(self.renderer.logical_device.device),
    };

    return .{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .num_indices = @intCast(indices.len),
        .push_constants = push_constants,
    };
}

pub fn delete_mesh(self: *Self, render_mesh_info: *const RenderMeshInfo) void {
    render_mesh_info.index_buffer.deinit(self.renderer.vma_allocator);
    render_mesh_info.vertex_buffer.deinit(self.renderer.vma_allocator);
}

pub const RenderUiQuadInfo = struct {
    buffer: AllocatedBuffer,
    push_constants: UiQuadPushConstant,
};

pub fn create_ui_quad(self: *Self, size: Vec2, pos: Vec2) !RenderUiQuadInfo {
    const buffer = try self.renderer.create_buffer(
        @sizeOf(UiQuadInfo),
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    var ui_quad_infos: []UiQuadInfo = undefined;
    ui_quad_infos.ptr = @alignCast(@ptrCast(buffer.allocation_info.pMappedData));
    ui_quad_infos.len = 1;

    var transform = Mat4.IDENDITY;
    transform.i.x = size.x / @as(f32, @floatFromInt(self.window_width));
    transform.j.y = size.y / @as(f32, @floatFromInt(self.window_height));
    transform = transform.translate(.{
        .x = pos.x / (@as(f32, @floatFromInt(self.window_width)) / 2.0),
        .y = pos.y / (@as(f32, @floatFromInt(self.window_height)) / 2.0),
        .z = 0.0,
    });

    ui_quad_infos[0].transform = transform;
    const push_constants: UiQuadPushConstant = .{
        .buffer_address = buffer.get_device_address(self.renderer.logical_device.device),
    };

    return .{
        .buffer = buffer,
        .push_constants = push_constants,
    };
}

pub fn delete_ui_quad(self: *Self, render_ui_quad_info: *const RenderUiQuadInfo) void {
    render_ui_quad_info.buffer.deinit(self.renderer.vma_allocator);
}

pub fn start_rendering(self: *Self) !struct { *const RenderCommand, u32 } {
    const current_command = &self.commands[self.current_framme_idx % self.commands.len];
    return self.renderer.start_command(current_command);
}

pub fn end_rendering(self: *Self, command: struct { *const RenderCommand, u32 }) !void {
    try self.renderer.finish_command(command);
    self.current_framme_idx +%= 1;
    return;
}

pub fn render_mesh(
    self: *Self,
    command: struct { *const RenderCommand, u32 },
    render_mesh_info: *const RenderMeshInfo,
) !void {
    vk.vkCmdBindPipeline(command[0].cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline.pipeline);
    vk.vkCmdBindDescriptorSets(
        command[0].cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.mesh_pipeline.pipeline_layout,
        0,
        1,
        &self.mesh_pipeline.descriptor_set,
        0,
        null,
    );
    vk.vkCmdPushConstants(
        command[0].cmd,
        self.mesh_pipeline.pipeline_layout,
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(MeshPushConstant),
        &render_mesh_info.push_constants,
    );
    vk.vkCmdBindIndexBuffer(command[0].cmd, render_mesh_info.index_buffer.buffer, 0, vk.VK_INDEX_TYPE_UINT32);
    vk.vkCmdDrawIndexed(command[0].cmd, render_mesh_info.num_indices, 1, 0, 0, 0);
}

pub fn render_ui_quad(
    self: *Self,
    command: struct { *const RenderCommand, u32 },
    render_ui_quad_info: *const RenderUiQuadInfo,
) !void {
    vk.vkCmdBindPipeline(command[0].cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.ui_quad_pipeline.pipeline);
    vk.vkCmdBindDescriptorSets(
        command[0].cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.ui_quad_pipeline.pipeline_layout,
        0,
        1,
        &self.ui_quad_pipeline.descriptor_set,
        0,
        null,
    );
    vk.vkCmdPushConstants(
        command[0].cmd,
        self.ui_quad_pipeline.pipeline_layout,
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(UiQuadPushConstant),
        &render_ui_quad_info.push_constants,
    );
    vk.vkCmdDraw(command[0].cmd, 6, 1, 0, 0);
}

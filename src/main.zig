const std = @import("std");
const log = @import("log.zig");
const vk = @import("vulkan.zig");
const sdl = @import("sdl.zig");

const Memory = @import("memory.zig");
const Renderer = @import("render/renderer.zig");
const _buffer = @import("render/buffer.zig");

const _image = @import("render/image.zig");

const _math = @import("math.zig");
const Mat4 = _math.Mat4;

const _mesh = @import("mesh.zig");
const DefaultVertex = _mesh.DefaultVertex;
const CubeMesh = _mesh.CubeMesh;

const CameraController = @import("camera.zig").CameraController;

const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const GREY = Color{ .r = 69, .g = 69, .b = 69, .a = 255 };
    pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
};

const QuadPushConstant = extern struct {
    buffer_address: vk.VkDeviceAddress,
};
const QuadInfo = extern struct {
    transform: Mat4,
};
const NUM_QUADS = 3;
const QUAD_WIDTH = 100;
const QUAD_HEIGHT = 100;

const MeshPushConstant = extern struct {
    view_proj: Mat4,
    buffer_address: vk.VkDeviceAddress,
};

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;

pub fn main() !void {
    var memory = try Memory.init();
    defer memory.deinit();

    {
        const game_alloc = memory.game_alloc();
        const buf = try game_alloc.alloc(u8, 1024);
        defer game_alloc.free(buf);
        log.info(@src(), "game: alloc {} bytes. game requested bytes: {}", .{ buf.len, memory.game_allocator.total_requested_bytes });
    }
    log.info(@src(), "game: game requested bytes after: {}", .{memory.game_allocator.total_requested_bytes});

    {
        const frame_alloc = memory.frame_alloc();
        defer memory.reset_frame();
        const buf = try frame_alloc.alloc(u8, 1024);
        defer frame_alloc.free(buf);
        log.info(@src(), "frame: alloc {} bytes. frame alloc end index: {}", .{ buf.len, memory.frame_allocator.end_index });
    }
    log.info(@src(), "frame alloc end index after: {}", .{memory.frame_allocator.end_index});

    log.info(@src(), "info log", .{});
    log.debug(@src(), "debug log", .{});
    log.warn(@src(), "warn log", .{});
    log.err(@src(), "err log", .{});

    var renderer = try Renderer.init(&memory, WINDOW_WIDTH, WINDOW_HEIGHT);
    defer renderer.deinit();

    var current_framme_idx: usize = 0;
    const commands = [_]Renderer.RenderCommand{
        try renderer.create_render_command(),
        try renderer.create_render_command(),
    };
    defer {
        commands[0].deinit(renderer.logical_device.device);
        commands[1].deinit(renderer.logical_device.device);
    }

    const immediate_command = try renderer.create_immediate_command();
    defer immediate_command.deinit(renderer.logical_device.device);

    const triangle_pipeline = try renderer.create_pipeline(
        &.{},
        &.{
            vk.VkPushConstantRange{
                .offset = 0,
                .size = @sizeOf(QuadPushConstant),
                .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            },
        },
        "triangle_mesh_vert.spv",
        "triangle_mesh_frag.spv",
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
    );
    defer triangle_pipeline.deinit(renderer.logical_device.device);

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
    defer mesh_pipeline.deinit(renderer.logical_device.device);

    const quad_buffer = try renderer.create_buffer(
        @sizeOf(QuadInfo) * NUM_QUADS,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer quad_buffer.deinit(renderer.vma_allocator);

    var quad_infos: []QuadInfo = undefined;
    quad_infos.ptr = @alignCast(@ptrCast(quad_buffer.allocation_info.pMappedData));
    quad_infos.len = NUM_QUADS;
    for (quad_infos, 0..) |*qi, i| {
        const t_pos: _math.Vec3 = .{
            .x = -WINDOW_WIDTH / 2.0 + QUAD_WIDTH / 2.0 + @as(f32, @floatFromInt(i)) * QUAD_WIDTH,
            .y = -WINDOW_HEIGHT / 2.0 + QUAD_HEIGHT / 2.0,
            .z = 0.0,
        };
        const t_size: _math.Vec2 = .{ .x = QUAD_WIDTH, .y = QUAD_HEIGHT };
        var transform = Mat4.IDENDITY;
        transform.i.x = t_size.x / WINDOW_WIDTH;
        transform.j.y = t_size.y / WINDOW_HEIGHT;
        transform = transform.translate(.{
            .x = t_pos.x / (WINDOW_WIDTH / 2.0),
            .y = t_pos.y / (WINDOW_HEIGHT / 2.0),
            .z = 0.0,
        });
        qi.*.transform = transform;
    }
    var quad_push_constants: QuadPushConstant = .{
        .buffer_address = quad_buffer.get_device_address(renderer.logical_device.device),
    };

    const cube_vertex_buffer = try renderer.create_buffer(
        @sizeOf(DefaultVertex) * CubeMesh.vertices.len,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer cube_vertex_buffer.deinit(renderer.vma_allocator);
    var cube_vertex_slice: []DefaultVertex = undefined;
    cube_vertex_slice.ptr = @alignCast(@ptrCast(cube_vertex_buffer.allocation_info.pMappedData));
    cube_vertex_slice.len = CubeMesh.vertices.len;
    @memcpy(cube_vertex_slice, &CubeMesh.vertices);

    const cube_index_buffer = try renderer.create_buffer(
        @sizeOf(u32) * CubeMesh.indices.len,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer cube_index_buffer.deinit(renderer.vma_allocator);
    var cube_index_slice: []u32 = undefined;
    cube_index_slice.ptr = @alignCast(@ptrCast(cube_index_buffer.allocation_info.pMappedData));
    cube_index_slice.len = CubeMesh.indices.len;
    @memcpy(cube_index_slice, &CubeMesh.indices);

    var mesh_push_constants: MeshPushConstant = .{
        .view_proj = undefined,
        .buffer_address = cube_vertex_buffer.get_device_address(renderer.logical_device.device),
    };

    const debug_texture = try renderer.create_image(
        16,
        16,
        vk.VK_FORMAT_B8G8R8A8_UNORM,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
    );
    defer debug_texture.deinit(renderer.logical_device.device, renderer.vma_allocator);

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
        defer immediate_command.end(renderer.logical_device.device, renderer.logical_device.graphics_queue) catch @panic("immediate_command error");

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

    const nearest_sampler = try renderer.create_sampler(vk.VK_FILTER_NEAREST, vk.VK_FILTER_NEAREST);
    defer vk.vkDestroySampler(renderer.logical_device.device, nearest_sampler, null);

    // update descriptor set
    const desc_image_info = vk.VkDescriptorImageInfo{
        .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = debug_texture.view,
        .sampler = nearest_sampler,
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

    var camera_controller = CameraController{};
    camera_controller.position.z = -5.0;

    var stop = false;
    var t = std.time.nanoTimestamp();
    while (!stop) {
        const new_t = std.time.nanoTimestamp();
        const dt = @as(f32, @floatFromInt(new_t - t)) / 1000_000_000.0;
        t = new_t;

        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event) != 0) {
            if (sdl_event.type == sdl.SDL_QUIT) {
                stop = true;
                break;
            }
            camera_controller.process_input(&sdl_event, dt);
        }
        camera_controller.update(dt);

        const current_command = &commands[current_framme_idx % commands.len];
        const command = try renderer.start_command(current_command);

        const view = camera_controller.view_matrix();
        var projection = Mat4.perspective(
            std.math.degreesToRadians(70.0),
            @as(f32, @floatFromInt(renderer.draw_image.extent.width)) /
                @as(f32, @floatFromInt(renderer.draw_image.extent.height)),
            10000.0,
            0.1,
        );
        projection.j.y *= -1.0;

        mesh_push_constants.view_proj = view.mul(projection);

        vk.vkCmdBindPipeline(command[0].cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, triangle_pipeline.pipeline);
        vk.vkCmdBindDescriptorSets(
            command[0].cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            triangle_pipeline.pipeline_layout,
            0,
            1,
            &triangle_pipeline.descriptor_set,
            0,
            null,
        );
        vk.vkCmdPushConstants(
            command[0].cmd,
            triangle_pipeline.pipeline_layout,
            vk.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            @sizeOf(QuadPushConstant),
            &quad_push_constants,
        );
        vk.vkCmdDraw(command[0].cmd, 6, NUM_QUADS, 0, 0);

        vk.vkCmdBindPipeline(command[0].cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, mesh_pipeline.pipeline);
        vk.vkCmdBindDescriptorSets(
            command[0].cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            mesh_pipeline.pipeline_layout,
            0,
            1,
            &mesh_pipeline.descriptor_set,
            0,
            null,
        );
        vk.vkCmdPushConstants(
            command[0].cmd,
            mesh_pipeline.pipeline_layout,
            vk.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            @sizeOf(MeshPushConstant),
            &mesh_push_constants,
        );
        vk.vkCmdBindIndexBuffer(command[0].cmd, cube_index_buffer.buffer, 0, vk.VK_INDEX_TYPE_UINT32);
        vk.vkCmdDrawIndexed(command[0].cmd, CubeMesh.indices.len, 1, 0, 0, 0);

        try renderer.finish_command(command);
        current_framme_idx +%= 1;
    }

    renderer.wait_idle();
    log.info(@src(), "Exiting", .{});
}

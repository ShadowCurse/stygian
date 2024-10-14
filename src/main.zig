const std = @import("std");
const log = @import("log.zig");
const vk = @import("vulkan.zig");
const sdl = @import("sdl.zig");

const Memory = @import("memory.zig");
const Renderer = @import("render/renderer.zig");
const _buffer = @import("render/buffer.zig");

const TrianglePushConstant = extern struct {
    buffer_address: vk.VkDeviceAddress,
};
const TriangleInfo = extern struct {
    offset: [3]f32,
    _: f32 = 0,
};
const NUM_TRIANGLES = 5;

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

    var renderer = try Renderer.init(&memory);
    defer renderer.deinit();

    const pipeline_idx = try renderer.create_pipeline(
        &.{},
        &.{
            vk.VkPushConstantRange{
                .offset = 0,
                .size = @sizeOf(TrianglePushConstant),
                .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
            },
        },
        "mesh_vert.spv",
        "mesh_frag.spv",
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
    );

    const buffer_idx = try renderer.create_buffer(
        @sizeOf(TriangleInfo) * NUM_TRIANGLES,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    const buffer = &renderer.buffers.items[buffer_idx];
    var triangle_offsets: []TriangleInfo = undefined;
    triangle_offsets.ptr = @alignCast(@ptrCast(buffer.allocation_info.pMappedData));
    triangle_offsets.len = NUM_TRIANGLES;
    for (triangle_offsets, 0..) |*ti, i| {
        ti.* = .{
            .offset = .{
                0.0 + 0.1 * @as(f32, @floatFromInt(i)),
                0.0 + 0.1 * @as(f32, @floatFromInt(i)),
                0.0 + 0.1 * @as(f32, @floatFromInt(i)),
            },
        };
    }
    const push_constants: TrianglePushConstant = .{
        .buffer_address = _buffer.get_buffer_address(buffer, renderer.logical_device.device),
    };

    var current_framme_idx: usize = 0;
    const command_idx = [_]Renderer.CommandIdx{
        try renderer.create_command(),
        try renderer.create_command(),
    };

    var stop = false;
    while (!stop) {
        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event) != 0) {
            if (sdl_event.type == sdl.SDL_QUIT) {
                stop = true;
                break;
            }
        }

        const current_command_idx = command_idx[current_framme_idx % command_idx.len];
        const command = try renderer.start_command(current_command_idx);
        const pipeline = &renderer.pipelines.items[pipeline_idx];

        vk.vkCmdBindPipeline(command[0].buffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
        vk.vkCmdBindDescriptorSets(
            command[0].buffer,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline.pipeline_layout,
            0,
            1,
            &pipeline.descriptor_set,
            0,
            null,
        );
        vk.vkCmdPushConstants(
            command[0].buffer,
            pipeline.pipeline_layout,
            vk.VK_SHADER_STAGE_VERTEX_BIT,
            0,
            @sizeOf(TrianglePushConstant),
            &push_constants,
        );
        vk.vkCmdDraw(command[0].buffer, 3, NUM_TRIANGLES, 0, 0);

        try renderer.finish_command(command);
        current_framme_idx +%= 1;
    }

    log.info(@src(), "Exiting", .{});
}

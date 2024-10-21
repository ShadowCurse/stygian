const std = @import("std");
const log = @import("log.zig");
const vk = @import("vulkan.zig");
const sdl = @import("sdl.zig");

const Memory = @import("memory.zig");
const Renderer = @import("render/renderer.zig");
const _buffer = @import("render/buffer.zig");

const _math = @import("math.zig");
const Mat4 = _math.Mat4;

const CameraController = @import("camera.zig").CameraController;

const TrianglePushConstant = extern struct {
    view_proj: Mat4,
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

    const pipeline = try renderer.create_pipeline(
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
    defer pipeline.deinit(renderer.logical_device.device);

    const buffer = try renderer.create_buffer(
        @sizeOf(TriangleInfo) * NUM_TRIANGLES,
        vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer buffer.deinit(renderer.vma_allocator);

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
    var push_constants: TrianglePushConstant = .{
        .view_proj = undefined,
        .buffer_address = buffer.get_device_address(renderer.logical_device.device),
    };

    var current_framme_idx: usize = 0;
    const commands = [_]Renderer.Command{
        try renderer.create_command(),
        try renderer.create_command(),
    };
    defer {
        commands[0].deinit(renderer.logical_device.device);
        commands[1].deinit(renderer.logical_device.device);
    }

    var camera_controller = CameraController{};

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
        push_constants.view_proj = view.mul(projection);

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

    renderer.wait_idle();
    log.info(@src(), "Exiting", .{});
}

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

const _math = @import("../math.zig");
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

const ColorU32 = @import("../color.zig").ColorU32;

pub const GridPushConstant = extern struct {
    view: Mat4,
    proj: Mat4,
    position: Vec3,
    color: ColorU32,
};

pub const GridPipeline = struct {
    pipeline: Pipeline,

    const Self = @This();

    pub fn init(memory: *Memory, renderer: *VkRenderer) !Self {
        const pipeline = try renderer.vk_context.create_pipeline(
            memory,
            &.{},
            &.{
                vk.VkPushConstantRange{
                    .offset = 0,
                    .size = @sizeOf(GridPushConstant),
                    .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
                },
            },
            "grid_vert.spv",
            "grid_frag.spv",
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

    pub fn render(
        self: *const Self,
        frame_context: *const FrameContext,
        push_constants: *const GridPushConstant,
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
        vk.vkCmdPushConstants(
            frame_context.command.cmd,
            self.pipeline.pipeline_layout,
            vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            0,
            @sizeOf(GridPushConstant),
            push_constants,
        );
        vk.vkCmdDraw(
            frame_context.command.cmd,
            6,
            1,
            0,
            0,
        );
    }
};

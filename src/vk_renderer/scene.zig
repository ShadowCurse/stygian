const std = @import("std");
const log = @import("../log.zig");
const vk = @import("../bindings/vulkan.zig");

const VkRenderer = @import("renderer.zig");
const GpuBuffer = @import("gpu_buffer.zig");
const ColorU32 = @import("../color.zig").ColorU32;

const _math = @import("../math.zig");
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const Light = extern struct {
    position: Vec3,
    color: ColorU32,
    constant: f32,
    linear: f32,
    quadratic: f32,
};

pub const CameraInfo = extern struct {
    view: Mat4,
    projection: Mat4,
    position: Vec3,
};

pub const ScenePushConstant = extern struct {
    camera_buffer_address: vk.VkDeviceAddress,
    lights_buffer_address: vk.VkDeviceAddress,
    num_lights: u32,
};

pub const SceneInfo = struct {
    camera_info_buffer: GpuBuffer,
    lights_buffer: GpuBuffer,
    num_lights_max: u32,
    num_lights_used: u32,
    push_constants: ScenePushConstant,

    const Self = @This();

    pub fn init(
        renderer: *VkRenderer,
        num_lights: u32,
    ) !Self {
        const camera_info_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(CameraInfo),
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        const lights_buffer = try renderer.vk_context.create_buffer(
            @sizeOf(Light) * num_lights,
            vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        const push_constants: ScenePushConstant = .{
            .camera_buffer_address = camera_info_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .lights_buffer_address = lights_buffer.get_device_address(
                renderer.vk_context.logical_device.device,
            ),
            .num_lights = 0,
        };

        return .{
            .camera_info_buffer = camera_info_buffer,
            .lights_buffer = lights_buffer,
            .num_lights_max = num_lights,
            .num_lights_used = 0,
            .push_constants = push_constants,
        };
    }

    pub fn deinit(self: *Self, renderer: *const VkRenderer) void {
        self.camera_info_buffer.deinit(renderer.vk_context.vma_allocator);
        self.lights_buffer.deinit(renderer.vk_context.vma_allocator);
    }

    pub fn reset(self: *Self) void {
        self.num_lights_used = 0;
    }

    pub fn set_camera_info(self: *const Self, camera_info: *const CameraInfo) void {
        const gpu_camera_info: *CameraInfo =
            @alignCast(@ptrCast(self.camera_info_buffer.allocation_info.pMappedData));
        gpu_camera_info.* = camera_info.*;
    }

    pub fn add_lights(self: *Self, lights: []const Light) void {
        if (self.num_lights_max < self.num_lights_used + lights.len) {
            log.warn(
                @src(),
                "Tryingt to use more lights than available: {} < {}",
                .{ self.num_lights_max, self.num_lights_used + lights.len },
            );
            return;
        }
        var lights_slice: []Light = undefined;
        lights_slice.ptr = @alignCast(
            @ptrCast(self.lights_buffer.allocation_info.pMappedData),
        );
        lights_slice.len = self.num_lights_max;
        @memcpy(
            lights_slice[self.num_lights_used .. self.num_lights_used + lights.len],
            lights,
        );
        self.num_lights_used += @intCast(lights.len);
        self.push_constants.num_lights = self.num_lights_used;
    }
};

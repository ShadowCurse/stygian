const std = @import("std");
const log = @import("../log.zig");
const sdl = @import("../sdl.zig");
const vk = @import("../vulkan.zig");
const _image = @import("image.zig");

const Memory = @import("../memory.zig");
const AllocatedImage = @import("../render/image.zig").AllocatedImage;
const AllocatedBuffer = @import("../render/buffer.zig").AllocatedBuffer;
const Pipeline = @import("../render/pipeline.zig").Pipeline;

const Allocator = std.mem.Allocator;

pub const CommandIdx = usize;
pub const PipelineIdx = usize;
pub const BufferIdx = usize;

const TIMEOUT = std.math.maxInt(u64);
const WIDTH = 1280;
const HEIGHT = 720;
const VK_VALIDATION_LAYERS_NAMES = [_][]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][]const u8{"VK_EXT_debug_utils"};
const VK_PHYSICAL_DEVICE_EXTENSION_NAMES = [_][]const u8{"VK_KHR_swapchain"};

const Self = @This();
memory: *Memory,
window: *sdl.SDL_Window,
surface: vk.VkSurfaceKHR,
vma_allocator: vk.VmaAllocator,
instance: Instance,
debug_messanger: DebugMessanger,
physical_device: PhysicalDevice,
logical_device: LogicalDevice,
swap_chain: Swapchain,
draw_image: AllocatedImage,
depth_image: AllocatedImage,
descriptor_pool: DescriptorPool,
commands: Commands,
pipelines: std.ArrayListUnmanaged(Pipeline),
buffers: std.ArrayListUnmanaged(AllocatedBuffer),

pub fn init(memory: *Memory) !Self {
    const game_allocator = memory.game_alloc();
    const frame_allocator = memory.frame_alloc();
    defer memory.reset_frame();

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        return error.SDLInit;
    }
    const window = sdl.SDL_CreateWindow(
        "stygian",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        sdl.SDL_WINDOW_VULKAN,
    ) orelse {
        return error.SDLCreateWindow;
    };
    sdl.SDL_ShowWindow(window);

    var sdl_extension_count: u32 = undefined;
    if (sdl.SDL_Vulkan_GetInstanceExtensions(window, &sdl_extension_count, null) != 1) {
        return error.SDLGetExtensions;
    }
    const sdl_extensions = try frame_allocator.alloc([*c]const u8, sdl_extension_count);
    if (sdl.SDL_Vulkan_GetInstanceExtensions(window, &sdl_extension_count, sdl_extensions.ptr) != 1) {
        return error.SDLGetExtensions;
    }
    for (sdl_extensions) |e| {
        log.debug(@src(), "Required SDL extension: {s}", .{e});
    }

    const instance = try Instance.init(frame_allocator, sdl_extensions);
    const debug_messanger = try DebugMessanger.init(instance.instance);

    // Casts are needed because SDL and vulkan imports same type,
    // but compiler sees them as different types.
    var surface: vk.VkSurfaceKHR = undefined;
    if (sdl.SDL_Vulkan_CreateSurface(window, @ptrCast(instance.instance), @ptrCast(&surface)) != 1) {
        return error.SDLCreateSurface;
    }

    const physical_device = try PhysicalDevice.init(frame_allocator, instance.instance, surface);
    const logical_device = try LogicalDevice.init(frame_allocator, &physical_device);

    const allocator_info = vk.VmaAllocatorCreateInfo{
        .instance = instance.instance,
        .physicalDevice = physical_device.device,
        .device = logical_device.device,
        .flags = vk.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    var vma_allocator: vk.VmaAllocator = undefined;
    try vk.check_result(vk.vmaCreateAllocator(&allocator_info, &vma_allocator));

    const swap_chain = try Swapchain.init(frame_allocator, game_allocator, &logical_device, &physical_device, surface, window);

    const draw_image = try AllocatedImage.init(
        vma_allocator,
        logical_device.device,
        swap_chain.extent.width,
        swap_chain.extent.height,
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
        vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    );

    const depth_image = try AllocatedImage.init(
        vma_allocator,
        logical_device.device,
        swap_chain.extent.width,
        swap_chain.extent.height,
        vk.VK_FORMAT_D32_SFLOAT,
        vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
    );

    const descriptor_pool = try DescriptorPool.init(logical_device.device, &.{
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 10,
        },
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 10,
        },
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 10,
        },
    });

    const commands = try Commands.init(logical_device.device, physical_device.graphics_queue_family);

    return .{
        .memory = memory,
        .window = window,
        .surface = surface,
        .vma_allocator = vma_allocator,
        .instance = instance,
        .debug_messanger = debug_messanger,
        .physical_device = physical_device,
        .logical_device = logical_device,
        .swap_chain = swap_chain,
        .draw_image = draw_image,
        .depth_image = depth_image,
        .descriptor_pool = descriptor_pool,
        .commands = commands,
        .pipelines = .{},
        .buffers = .{},
    };
}

pub fn deinit(self: *Self) void {
    const game_allocator = self.memory.game_alloc();

    _ = vk.vkDeviceWaitIdle(self.logical_device.device);
    for (self.buffers.items) |*b| {
        b.deinit(self.vma_allocator);
    }
    self.buffers.deinit(game_allocator);
    for (self.pipelines.items) |*p| {
        p.deinit(self.logical_device.device);
    }
    self.pipelines.deinit(game_allocator);
    self.descriptor_pool.deinit(self.logical_device.device);
    self.commands.deinit(game_allocator, self.logical_device.device);
    self.depth_image.deinit(self.logical_device.device, self.vma_allocator);
    self.draw_image.deinit(self.logical_device.device, self.vma_allocator);
    vk.vmaDestroyAllocator(self.vma_allocator);
    self.swap_chain.deinit(self.logical_device.device, game_allocator);
    self.logical_device.deinit();
    vk.vkDestroySurfaceKHR(self.instance.instance, self.surface, null);
    self.debug_messanger.deinit(self.instance.instance) catch {
        log.err(@src(), "Could not destroy debug messanger", .{});
    };
    self.instance.deinit();
    sdl.SDL_DestroyWindow(self.window);
}

pub fn create_pipeline(
    self: *Self,
    bindings: []const vk.VkDescriptorSetLayoutBinding,
    push_constants: []const vk.VkPushConstantRange,
    vertex_shader_path: [:0]const u8,
    fragment_shader_path: [:0]const u8,
    image_format: vk.VkFormat,
) !PipelineIdx {
    const frame_allocator = self.memory.frame_alloc();
    defer self.memory.reset_frame();
    const pipeline = try Pipeline.init(
        frame_allocator,
        self.logical_device.device,
        self.descriptor_pool.pool,
        bindings,
        push_constants,
        vertex_shader_path,
        fragment_shader_path,
        image_format,
        self.depth_image.format,
    );
    const idx = self.pipelines.items.len;
    try self.pipelines.append(self.memory.game_alloc(), pipeline);
    return idx;
}

pub fn create_buffer(
    self: *Self,
    size: u64,
    usage: vk.VkBufferUsageFlags,
    memory_usage: vk.VmaMemoryUsage,
) !BufferIdx {
    const idx = self.buffers.items.len;
    try self.buffers.append(self.memory.game_alloc(), try AllocatedBuffer.init(self.vma_allocator, size, usage, memory_usage));
    return idx;
}

pub fn create_command(self: *Self) !CommandIdx {
    return self.commands.allocate_command(self.memory.game_alloc(), self.logical_device.device);
}

pub fn start_command(self: *const Self, command_idx: CommandIdx) !struct { *const Command, u32 } {
    const current_command = &self.commands.commands.items[command_idx];

    try vk.check_result(vk.vkWaitForFences(
        self.logical_device.device,
        1,
        &current_command.render_fence,
        vk.VK_TRUE,
        TIMEOUT,
    ));
    try vk.check_result(vk.vkResetFences(self.logical_device.device, 1, &current_command.render_fence));

    var image_index: u32 = 0;
    try vk.check_result(vk.vkAcquireNextImageKHR(
        self.logical_device.device,
        self.swap_chain.swap_chain,
        TIMEOUT,
        current_command.swap_chain_semaphore,
        null,
        &image_index,
    ));

    try vk.check_result(vk.vkResetCommandBuffer(current_command.buffer, 0));
    const begin_info = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.check_result(vk.vkBeginCommandBuffer(current_command.buffer, &begin_info));

    _image.transition_image(
        current_command.buffer,
        self.draw_image.image,
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
    );

    _image.transition_image(
        current_command.buffer,
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
    vk.vkCmdBeginRendering(current_command.buffer, &render_info);

    const viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.draw_image.extent.width),
        .height = @floatFromInt(self.draw_image.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(current_command.buffer, 0, 1, &viewport);
    const scissor = vk.VkRect2D{ .offset = .{
        .x = 0.0,
        .y = 0.0,
    }, .extent = .{
        .width = self.draw_image.extent.width,
        .height = self.draw_image.extent.height,
    } };
    vk.vkCmdSetScissor(current_command.buffer, 0, 1, &scissor);

    return .{
        current_command,
        image_index,
    };
}

pub fn finish_command(self: *const Self, command: struct { *const Command, u32 }) !void {
    const current_command = command[0];
    const image_index = command[1];

    vk.vkCmdEndRendering(current_command.buffer);

    _image.transition_image(
        current_command.buffer,
        self.draw_image.image,
        vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    );
    _image.transition_image(
        current_command.buffer,
        self.swap_chain.images[image_index],
        vk.VK_IMAGE_LAYOUT_UNDEFINED,
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );
    _image.copy_image_to_image(
        current_command.buffer,
        self.draw_image.image,
        .{
            .width = self.draw_image.extent.width,
            .height = self.draw_image.extent.height,
        },
        self.swap_chain.images[image_index],
        self.swap_chain.extent,
    );
    _image.transition_image(
        current_command.buffer,
        self.swap_chain.images[image_index],
        vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    );

    try vk.check_result(vk.vkEndCommandBuffer(current_command.buffer));

    // Submit commands
    const buffer_submit_info = vk.VkCommandBufferSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = current_command.buffer,
        .deviceMask = 0,
    };
    const wait_semaphore_info = vk.VkSemaphoreSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = current_command.swap_chain_semaphore,
        .stageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    };
    const signal_semaphore_info = vk.VkSemaphoreSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = current_command.render_semaphore,
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
    try vk.check_result(vk.vkQueueSubmit2(
        self.logical_device.graphics_queue,
        1,
        &submit_info,
        current_command.render_fence,
    ));

    // Present image in the screen
    const present_info = vk.VkPresentInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.swap_chain.swap_chain,
        .swapchainCount = 1,
        .pWaitSemaphores = &current_command.render_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };
    try vk.check_result(vk.vkQueuePresentKHR(self.logical_device.graphics_queue, &present_info));
}

const Instance = struct {
    instance: vk.VkInstance,

    pub fn init(arena: Allocator, sdl_extensions: [][*c]const u8) !Instance {
        var extensions_count: u32 = 0;
        try vk.check_result(vk.vkEnumerateInstanceExtensionProperties(null, &extensions_count, null));
        const extensions = try arena.alloc(vk.VkExtensionProperties, extensions_count);
        try vk.check_result(vk.vkEnumerateInstanceExtensionProperties(null, &extensions_count, extensions.ptr));

        var found_sdl_extensions: u32 = 0;
        var found_additional_extensions: u32 = 0;
        for (extensions) |e| {
            var required = "--------";
            for (sdl_extensions) |se| {
                const sdl_name_span = std.mem.span(se);
                const extension_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&e.extensionName)));
                if (std.mem.eql(u8, extension_name_span, sdl_name_span)) {
                    found_sdl_extensions += 1;
                    required = "required";
                }
            }
            for (VK_ADDITIONAL_EXTENSIONS_NAMES) |ae| {
                const extension_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&e.extensionName)));
                if (std.mem.eql(u8, extension_name_span, ae)) {
                    found_additional_extensions += 1;
                    required = "required";
                }
            }
            log.debug(@src(), "({s}) Extension name: {s} version: {}", .{ required, e.extensionName, e.specVersion });
        }
        if (found_sdl_extensions != sdl_extensions.len) {
            return error.SDLExtensionsNotFound;
        }
        if (found_additional_extensions != VK_ADDITIONAL_EXTENSIONS_NAMES.len) {
            return error.AdditionalExtensionsNotFound;
        }

        var total_extensions = try std.ArrayListUnmanaged([*c]const u8).initCapacity(
            arena,
            sdl_extensions.len + VK_ADDITIONAL_EXTENSIONS_NAMES.len,
        );
        for (sdl_extensions) |e| {
            try total_extensions.append(arena, e);
        }
        for (VK_ADDITIONAL_EXTENSIONS_NAMES) |e| {
            try total_extensions.append(arena, e.ptr);
        }

        var layer_property_count: u32 = 0;
        try vk.check_result(vk.vkEnumerateInstanceLayerProperties(&layer_property_count, null));
        const layers = try arena.alloc(vk.VkLayerProperties, layer_property_count);
        try vk.check_result(vk.vkEnumerateInstanceLayerProperties(&layer_property_count, layers.ptr));

        var found_validation_layers: u32 = 0;
        for (layers) |l| {
            var required = "--------";
            for (VK_VALIDATION_LAYERS_NAMES) |vln| {
                const layer_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&l.layerName)));
                if (std.mem.eql(u8, layer_name_span, vln)) {
                    found_validation_layers += 1;
                    required = "required";
                }
            }
            log.debug(@src(), "({s}) Layer name: {s}, spec version: {}, description: {s}", .{ required, l.layerName, l.specVersion, l.description });
        }
        if (found_validation_layers != VK_VALIDATION_LAYERS_NAMES.len) {
            return error.ValidationLayersNotFound;
        }

        const app_info = vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "stygian",
            .applicationVersion = vk.VK_MAKE_VERSION(0, 0, 1),
            .pEngineName = "stygian",
            .engineVersion = vk.VK_MAKE_VERSION(0, 0, 1),
            .apiVersion = vk.VK_API_VERSION_1_3,
            .pNext = null,
        };
        const instance_create_info = vk.VkInstanceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
            .ppEnabledExtensionNames = total_extensions.items.ptr,
            .enabledExtensionCount = @as(u32, @intCast(total_extensions.items.len)),
            .ppEnabledLayerNames = @ptrCast(&VK_VALIDATION_LAYERS_NAMES),
            .enabledLayerCount = @as(u32, @intCast(VK_VALIDATION_LAYERS_NAMES.len)),
        };

        var vk_instance: vk.VkInstance = undefined;
        try vk.check_result(vk.vkCreateInstance(&instance_create_info, null, &vk_instance));
        return .{
            .instance = vk_instance,
        };
    }

    pub fn deinit(self: *const Instance) void {
        vk.vkDestroyInstance(self.instance, null);
    }
};

pub fn get_vk_func(comptime Fn: type, instance: vk.VkInstance, name: [*c]const u8) !Fn {
    if (sdl.SDL_Vulkan_GetVkGetInstanceProcAddr()) |f| {
        const get_proc_addr = @as(vk.PFN_vkGetInstanceProcAddr, @ptrCast(f)).?;
        if (get_proc_addr(instance, name)) |func| {
            return @ptrCast(func);
        } else {
            return error.VKGetInstanceProcAddr;
        }
    } else {
        log.err(@src(), "Cound not create debug messanger", .{});
        return error.SDLGetInstanceProcAddr;
    }
}

const DebugMessanger = struct {
    messanger: vk.VkDebugUtilsMessengerEXT,

    pub fn init(vk_instance: vk.VkInstance) !DebugMessanger {
        const create_fn = (try get_vk_func(vk.PFN_vkCreateDebugUtilsMessengerEXT, vk_instance, "vkCreateDebugUtilsMessengerEXT")).?;
        const create_info = vk.VkDebugUtilsMessengerCreateInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT |
                vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
            .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = DebugMessanger.debug_callback,
            .pUserData = null,
        };
        var vk_debug_messanger: vk.VkDebugUtilsMessengerEXT = undefined;
        try vk.check_result(create_fn(vk_instance, &create_info, null, &vk_debug_messanger));
        return .{
            .messanger = vk_debug_messanger,
        };
    }

    pub fn deinit(self: *const DebugMessanger, vk_instance: vk.VkInstance) !void {
        const destroy_fn = (try get_vk_func(vk.PFN_vkDestroyDebugUtilsMessengerEXT, vk_instance, "vkDestroyDebugUtilsMessengerEXT")).?;
        destroy_fn(vk_instance, self.messanger, null);
    }

    pub fn debug_callback(
        severity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
        msg_type: vk.VkDebugUtilsMessageTypeFlagsEXT,
        data: ?*const vk.VkDebugUtilsMessengerCallbackDataEXT,
        _: ?*anyopaque,
    ) callconv(.C) vk.VkBool32 {
        const ty = switch (msg_type) {
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT => "general",
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT => "validation",
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT => "performance",
            else => "unknown",
        };
        const msg: [*c]const u8 = if (data) |d| d.pMessage else "empty";
        switch (severity) {
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => {
                log.err(@src(), "[{s}]: {s}", .{ ty, msg });
            },
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => {
                log.warn(@src(), "[{s}]: {s}", .{ ty, msg });
            },
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => {
                log.debug(@src(), "[{s}]: {s}", .{ ty, msg });
            },
            else => {},
        }
        return vk.VK_FALSE;
    }
};

const PhysicalDevice = struct {
    device: vk.VkPhysicalDevice,
    graphics_queue_family: u32,
    present_queue_family: u32,
    compute_queue_family: u32,
    transfer_queue_family: u32,

    pub fn init(arena: Allocator, vk_instance: vk.VkInstance, vk_surface: vk.VkSurfaceKHR) !PhysicalDevice {
        var physical_device_count: u32 = 0;
        try vk.check_result(vk.vkEnumeratePhysicalDevices(vk_instance, &physical_device_count, null));
        const physical_devices = try arena.alloc(vk.VkPhysicalDevice, physical_device_count);
        try vk.check_result(vk.vkEnumeratePhysicalDevices(vk_instance, &physical_device_count, physical_devices.ptr));

        for (physical_devices) |pd| {
            var properties: vk.VkPhysicalDeviceProperties = undefined;
            var features: vk.VkPhysicalDeviceFeatures = undefined;
            vk.vkGetPhysicalDeviceProperties(pd, &properties);
            vk.vkGetPhysicalDeviceFeatures(pd, &features);

            log.debug(@src(), "Physical device: {s}", .{properties.deviceName});

            var extensions_count: u32 = 0;
            try vk.check_result(vk.vkEnumerateDeviceExtensionProperties(pd, null, &extensions_count, null));
            const extensions = try arena.alloc(vk.VkExtensionProperties, extensions_count);
            try vk.check_result(vk.vkEnumerateDeviceExtensionProperties(pd, null, &extensions_count, extensions.ptr));

            var found_extensions: u32 = 0;
            for (extensions) |e| {
                var required = "--------";
                for (VK_PHYSICAL_DEVICE_EXTENSION_NAMES) |re| {
                    const extension_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&e.extensionName)));
                    if (std.mem.eql(u8, extension_name_span, re)) {
                        found_extensions += 1;
                        required = "required";
                    }
                }
                log.debug(@src(), "({s}) extension name: {s}", .{ required, e.extensionName });
            }
            if (found_extensions != VK_PHYSICAL_DEVICE_EXTENSION_NAMES.len) {
                continue;
            }

            var queue_family_count: u32 = 0;
            vk.vkGetPhysicalDeviceQueueFamilyProperties(pd, &queue_family_count, null);
            const queue_families = try arena.alloc(vk.VkQueueFamilyProperties, queue_family_count);
            vk.vkGetPhysicalDeviceQueueFamilyProperties(pd, &queue_family_count, queue_families.ptr);

            var graphics_queue_family: ?u32 = null;
            var present_queue_family: ?u32 = null;
            var compute_queue_family: ?u32 = null;
            var transfer_queue_family: ?u32 = null;

            for (queue_families, 0..) |qf, i| {
                if (graphics_queue_family == null and qf.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                    graphics_queue_family = @intCast(i);
                }
                if (compute_queue_family == null and qf.queueFlags & vk.VK_QUEUE_COMPUTE_BIT != 0) {
                    compute_queue_family = @intCast(i);
                }
                if (transfer_queue_family == null and qf.queueFlags & vk.VK_QUEUE_TRANSFER_BIT != 0) {
                    transfer_queue_family = @intCast(i);
                }
                if (present_queue_family == null) {
                    var supported: vk.VkBool32 = 0;
                    try vk.check_result(vk.vkGetPhysicalDeviceSurfaceSupportKHR(pd, @intCast(i), vk_surface, &supported));
                    if (supported == vk.VK_TRUE) {
                        present_queue_family = @intCast(i);
                    }
                }
            }

            if (graphics_queue_family != null and
                present_queue_family != null and
                compute_queue_family != null and
                transfer_queue_family != null)
            {
                log.debug(@src(), "Selected graphics queue family: {}", .{graphics_queue_family.?});
                log.debug(@src(), "Selected present queue family: {}", .{present_queue_family.?});
                log.debug(@src(), "Selected compute queue family: {}", .{compute_queue_family.?});
                log.debug(@src(), "Selected transfer queue family: {}", .{transfer_queue_family.?});

                return .{
                    .device = pd,
                    .graphics_queue_family = graphics_queue_family.?,
                    .present_queue_family = present_queue_family.?,
                    .compute_queue_family = compute_queue_family.?,
                    .transfer_queue_family = transfer_queue_family.?,
                };
            }
        }
        return error.PhysicalDeviceNotSelected;
    }
};

const LogicalDevice = struct {
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    present_queue: vk.VkQueue,
    compute_queue: vk.VkQueue,
    transfer_queue: vk.VkQueue,

    pub fn init(arena: Allocator, physical_device: *const PhysicalDevice) !LogicalDevice {
        const all_queue_family_indexes: [4]u32 = .{
            physical_device.graphics_queue_family,
            physical_device.present_queue_family,
            physical_device.compute_queue_family,
            physical_device.transfer_queue_family,
        };
        var i: usize = 0;
        var unique_indexes: [4]u32 = .{ std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32) };
        for (all_queue_family_indexes) |qfi| {
            if (std.mem.count(u32, &unique_indexes, &.{qfi}) == 0) {
                unique_indexes[i] = qfi;
                i += 1;
            }
        }
        const unique = std.mem.sliceTo(&unique_indexes, std.math.maxInt(u32));
        const queue_create_infos = try arena.alloc(vk.VkDeviceQueueCreateInfo, unique.len);

        const queue_priority: f32 = 1.0;
        for (queue_create_infos, unique) |*qi, u| {
            qi.* = vk.VkDeviceQueueCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = u,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
            };
        }

        var physical_device_features_1_3 = vk.VkPhysicalDeviceVulkan13Features{
            .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            .dynamicRendering = vk.VK_TRUE,
            .synchronization2 = vk.VK_TRUE,
        };
        const physical_device_features_1_2 = vk.VkPhysicalDeviceVulkan12Features{
            .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            .bufferDeviceAddress = vk.VK_TRUE,
            .descriptorIndexing = vk.VK_TRUE,
            .pNext = @ptrCast(&physical_device_features_1_3),
        };
        const physical_device_features = vk.VkPhysicalDeviceFeatures{};

        const create_info = vk.VkDeviceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.len)),
            .pQueueCreateInfos = queue_create_infos.ptr,
            .ppEnabledLayerNames = null,
            .enabledLayerCount = 0,
            .ppEnabledExtensionNames = @ptrCast(&VK_PHYSICAL_DEVICE_EXTENSION_NAMES),
            .enabledExtensionCount = @as(u32, @intCast(VK_PHYSICAL_DEVICE_EXTENSION_NAMES.len)),
            .pEnabledFeatures = &physical_device_features,
            .pNext = &physical_device_features_1_2,
        };

        var logical_device: LogicalDevice = undefined;
        try vk.check_result(vk.vkCreateDevice(
            physical_device.device,
            &create_info,
            null,
            &logical_device.device,
        ));
        vk.vkGetDeviceQueue(
            logical_device.device,
            physical_device.present_queue_family,
            0,
            &logical_device.present_queue,
        );
        vk.vkGetDeviceQueue(
            logical_device.device,
            physical_device.graphics_queue_family,
            0,
            &logical_device.graphics_queue,
        );
        vk.vkGetDeviceQueue(
            logical_device.device,
            physical_device.compute_queue_family,
            0,
            &logical_device.compute_queue,
        );
        vk.vkGetDeviceQueue(
            logical_device.device,
            physical_device.transfer_queue_family,
            0,
            &logical_device.transfer_queue,
        );
        return logical_device;
    }

    pub fn deinit(self: *const LogicalDevice) void {
        vk.vkDestroyDevice(self.device, null);
    }
};

const Swapchain = struct {
    swap_chain: vk.VkSwapchainKHR,
    images: []vk.VkImage,
    image_views: []vk.VkImageView,
    format: vk.VkFormat,
    extent: vk.VkExtent2D,

    pub fn init(
        arena: Allocator,
        allocator: Allocator,
        logical_device: *const LogicalDevice,
        physical_device: *const PhysicalDevice,
        surface: vk.VkSurfaceKHR,
        window: *sdl.SDL_Window,
    ) !Swapchain {
        var surface_capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
        try vk.check_result(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device.device, surface, &surface_capabilities));

        var device_surface_format_count: u32 = 0;
        try vk.check_result(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(
            physical_device.device,
            surface,
            &device_surface_format_count,
            null,
        ));
        const device_surface_formats = try arena.alloc(vk.VkSurfaceFormatKHR, device_surface_format_count);
        try vk.check_result(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(
            physical_device.device,
            surface,
            &device_surface_format_count,
            device_surface_formats.ptr,
        ));
        var found_format: ?vk.VkSurfaceFormatKHR = null;
        for (device_surface_formats) |format| {
            if (format.format == vk.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                found_format = format;
                break;
            }
        }
        if (found_format == null) {
            return error.SurfaceFormatNotFound;
        }
        const surface_format = found_format.?;

        var swap_chain_extent: vk.VkExtent2D = surface_capabilities.currentExtent;
        if (swap_chain_extent.width == std.math.maxInt(u32)) {
            var w: i32 = 0;
            var h: i32 = 0;
            sdl.SDL_GetWindowSize(window, &w, &h);
            const window_w: u32 = @intCast(w);
            const window_h: u32 = @intCast(h);
            swap_chain_extent.width = @min(@max(window_w, surface_capabilities.minImageExtent.width), surface_capabilities.maxImageExtent.width);
            swap_chain_extent.height = @min(@max(window_h, surface_capabilities.minImageExtent.height), surface_capabilities.maxImageExtent.height);
        }

        const create_info = vk.VkSwapchainCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = surface_capabilities.minImageCount + 1,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = swap_chain_extent,
            .imageArrayLayers = 1,
            .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
            .preTransform = surface_capabilities.currentTransform,
            .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = vk.VK_PRESENT_MODE_FIFO_KHR,
            .clipped = vk.VK_TRUE,
            .oldSwapchain = null,
        };

        var swap_chain: Swapchain = undefined;
        try vk.check_result(vk.vkCreateSwapchainKHR(logical_device.device, &create_info, null, &swap_chain.swap_chain));
        swap_chain.format = surface_format.format;
        swap_chain.extent = swap_chain_extent;

        var swap_chain_images_count: u32 = 0;
        try vk.check_result(vk.vkGetSwapchainImagesKHR(
            logical_device.device,
            swap_chain.swap_chain,
            &swap_chain_images_count,
            null,
        ));
        swap_chain.images = try allocator.alloc(vk.VkImage, swap_chain_images_count);
        errdefer allocator.free(swap_chain.images);
        try vk.check_result(vk.vkGetSwapchainImagesKHR(
            logical_device.device,
            swap_chain.swap_chain,
            &swap_chain_images_count,
            swap_chain.images.ptr,
        ));

        swap_chain.image_views = try allocator.alloc(vk.VkImageView, swap_chain_images_count);
        errdefer allocator.free(swap_chain.image_views);
        for (swap_chain.images, swap_chain.image_views) |image, *view| {
            const view_create_info = vk.VkImageViewCreateInfo{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
                .format = swap_chain.format,
                .components = .{
                    .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };
            try vk.check_result(
                vk.vkCreateImageView(
                    logical_device.device,
                    &view_create_info,
                    null,
                    view,
                ),
            );
        }
        return swap_chain;
    }

    pub fn deinit(self: *const Swapchain, device: vk.VkDevice, allocator: Allocator) void {
        for (self.image_views) |view| {
            vk.vkDestroyImageView(device, view, null);
        }
        vk.vkDestroySwapchainKHR(device, self.swap_chain, null);
        allocator.free(self.images);
        allocator.free(self.image_views);
    }
};

const DescriptorPool = struct {
    pool: vk.VkDescriptorPool,

    pub fn init(device: vk.VkDevice, pool_sizes: []const vk.VkDescriptorPoolSize) !DescriptorPool {
        const pool_info = vk.VkDescriptorPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = 10,
            .pPoolSizes = pool_sizes.ptr,
            .poolSizeCount = @intCast(pool_sizes.len),
        };
        var pool: vk.VkDescriptorPool = undefined;
        try vk.check_result(vk.vkCreateDescriptorPool(device, &pool_info, null, &pool));
        return .{
            .pool = pool,
        };
    }

    pub fn deinit(self: *const DescriptorPool, device: vk.VkDevice) void {
        vk.vkDestroyDescriptorPool(device, self.pool, null);
    }
};

pub const Command = struct {
    buffer: vk.VkCommandBuffer,
    swap_chain_semaphore: vk.VkSemaphore,
    render_semaphore: vk.VkSemaphore,
    render_fence: vk.VkFence,

    pub fn deinit(self: *const Command, device: vk.VkDevice) void {
        vk.vkDestroyFence(device, self.render_fence, null);
        vk.vkDestroySemaphore(device, self.render_semaphore, null);
        vk.vkDestroySemaphore(device, self.swap_chain_semaphore, null);
    }
};

const Commands = struct {
    pool: vk.VkCommandPool,
    commands: std.ArrayListUnmanaged(Command),

    pub fn init(device: vk.VkDevice, queue_family_index: u32) !Commands {
        const pool_create_info = vk.VkCommandPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queue_family_index,
        };
        var pool: vk.VkCommandPool = undefined;
        try vk.check_result(vk.vkCreateCommandPool(device, &pool_create_info, null, &pool));
        return .{ .pool = pool, .commands = .{} };
    }

    pub fn deinit(self: *Commands, allocator: Allocator, device: vk.VkDevice) void {
        for (self.commands.items) |c| {
            c.deinit(device);
        }
        self.commands.deinit(allocator);
        vk.vkDestroyCommandPool(device, self.pool, null);
    }

    pub fn allocate_command(self: *Commands, allocator: Allocator, device: vk.VkDevice) !CommandIdx {
        const allocate_info = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };
        var buffer: vk.VkCommandBuffer = undefined;
        try vk.check_result(vk.vkAllocateCommandBuffers(device, &allocate_info, &buffer));

        const fence_create_info = vk.VkFenceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
        };
        var render_fence: vk.VkFence = undefined;
        try vk.check_result(vk.vkCreateFence(device, &fence_create_info, null, &render_fence));

        const semaphore_creaet_info = vk.VkSemaphoreCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };
        var render_semaphore: vk.VkSemaphore = undefined;
        var swap_chain_semaphore: vk.VkSemaphore = undefined;
        try vk.check_result(vk.vkCreateSemaphore(device, &semaphore_creaet_info, null, &render_semaphore));
        try vk.check_result(vk.vkCreateSemaphore(device, &semaphore_creaet_info, null, &swap_chain_semaphore));

        const command = Command{
            .buffer = buffer,
            .swap_chain_semaphore = swap_chain_semaphore,
            .render_semaphore = render_semaphore,
            .render_fence = render_fence,
        };
        const idx = self.commands.items.len;
        try self.commands.append(allocator, command);
        return idx;
    }
};
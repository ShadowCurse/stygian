const sdl = @import("../bindings/sdl.zig");
const vk = @import("../bindings/vulkan.zig");
const log = @import("../log.zig");

const Window = @import("window.zig");

pub fn platform_extensions() []const [*c]const u8 {
    var count: u32 = undefined;
    const ptr = sdl.SDL_Vulakn_GetInstanceExtensions(&count);
    var slice: []const [*c]const u8 = undefined;
    slice.ptr = ptr;
    slice.len = count;
    return slice;
}

pub fn create_surface(
    window: *const Window,
    instance: vk.VkInstance,
    surface: *vk.VkSurfaceKHR,
) bool {
    if (!sdl.SDL_Vulkan_CreateSurface(
        window.sdl_window,
        @ptrCast(instance),
        null,
        @ptrCast(surface),
    )) {
        log.err(
            @src(),
            "Cannot create Vulkan surface. Error: {s}",
            .{sdl.SDL_GetError()},
        );
        return false;
    }
    return true;
}

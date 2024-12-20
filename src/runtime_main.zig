const std = @import("std");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Memory = @import("memory.zig");

const Runtime = struct {
    counter: u32,

    const Self = @This();

    fn init(self: *Self) void {
        self.counter = 0;
    }
};

export fn runtime_main(window: *sdl.SDL_Window, sdl_events: [*]sdl.SDL_Event, sdl_events_num: usize, memory: *Memory, dt: f32, data: ?*anyopaque) *anyopaque {
    var events: []sdl.SDL_Event = undefined;
    events.ptr = sdl_events;
    events.len = sdl_events_num;
    _ = dt;
    var runtime_ptr: ?*Runtime = @alignCast(@ptrCast(data));
    if (runtime_ptr == null) {
        log.info(@src(), "First time runtime init", .{});
        const game_alloc = memory.game_alloc();
        runtime_ptr = &(game_alloc.alloc(Runtime, 1) catch unreachable)[0];
        runtime_ptr.?.init();
    } else {
        const runtime = runtime_ptr.?;
        runtime.counter += 1;
        log.info(@src(), "Runtime counter: {}", .{runtime.counter});

        const surface: *sdl.SDL_Surface = sdl.SDL_GetWindowSurface(window);

        _ = sdl.SDL_FillRect(surface, 0, 0xFF000000);
        var pixels: []u32 = undefined;
        pixels.ptr = @alignCast(@ptrCast(surface.pixels));
        pixels.len = @as(usize, @intCast(surface.w)) * @as(usize, @intCast(surface.h));

        for (100..300) |x| {
            for (100..300) |y| {
                pixels[x + y * @as(usize, @intCast(surface.w))] = 0xFF00FF00;
            }
        }

        _ = sdl.SDL_UpdateWindowSurface(window);
    }
    return @ptrCast(runtime_ptr);
}

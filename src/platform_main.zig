const std = @import("std");
const build_options = @import("build_options");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Memory = @import("memory.zig");
const RuntimeWatch = @import("platform/posix.zig").RuntimeWatch;
const RuntimeFn = *fn (
    *sdl.SDL_Window,
    [*]sdl.SDL_Event,
    usize,
    *Memory,
    f32,
    ?*anyopaque,
) *anyopaque;

const RUNTIME_LIB_PATH = "./zig-out/lib/libstygian_runtime.so";
const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;
const FPS = 60.0;
const FRAME_TIME = 1.0 / FPS;

const RuntimeLoad = struct {
    runtime_dl_handle: ?*anyopaque = null,

    const RUNTIME_LIB_FN = "runtime_main";
    const RTLD_NOW = 0x00002;
    const Self = @This();

    pub fn get_runtime_fn(self: *Self) !*anyopaque {
        if (self.runtime_dl_handle) |handle| {
            _ = std.c.dlclose(handle);
            self.runtime_dl_handle = null;
        }
        if (std.c.dlopen(RUNTIME_LIB_PATH, RTLD_NOW)) |handle| {
            self.runtime_dl_handle = handle;
            if (std.c.dlsym(handle, RUNTIME_LIB_FN)) |rl| {
                return rl;
            } else {
                log.err(@src(), "Cannot load {s} from libruntime.so", .{RUNTIME_LIB_FN});
                return error.NoRuntimeLibFn;
            }
        } else {
            log.err(@src(), "Cannot load libruntime.so from {s}", .{RUNTIME_LIB_PATH});
            return error.NoRuntimeLib;
        }
    }
};

pub fn main() !void {
    const runtime_watch = try RuntimeWatch.init(RUNTIME_LIB_PATH);
    var runtime_load: RuntimeLoad = .{};

    var runtime_fn: RuntimeFn = @ptrCast(try runtime_load.get_runtime_fn());
    var runtime_data: ?*anyopaque = null;

    var memory = try Memory.init();

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        log.err(@src(), "Cannot init SDL: {s}", .{sdl.SDL_GetError()});
        return error.SDLInit;
    }
    const flags = if (build_options.software_render)
        0
    else if (build_options.vulkan_render)
        sdl.SDL_WINDOW_VULKAN
    else
        @panic("No renderer type selected");

    const window = sdl.SDL_CreateWindow(
        "stygian",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        flags,
    ) orelse {
        log.err(@src(), "Cannot create a window: {s}", .{sdl.SDL_GetError()});
        return error.SDLCreateWindow;
    };
    sdl.SDL_ShowWindow(window);

    var sdl_events: [32]sdl.SDL_Event = undefined;
    var stop = false;
    var t = std.time.nanoTimestamp();
    while (!stop) {
        const new_t = std.time.nanoTimestamp();
        var dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
        t = new_t;
        if (dt < FRAME_TIME) {
            std.time.sleep(@intFromFloat((FRAME_TIME - dt) * std.time.ns_per_s));
            dt = FRAME_TIME;
        }

        sdl.SDL_FlushEvents(
            sdl.SDL_FIRSTEVENT,
            sdl.SDL_LASTEVENT,
        );
        sdl.SDL_PumpEvents();
        const num_events = sdl.SDL_PeepEvents(
            &sdl_events,
            sdl_events.len,
            sdl.SDL_PEEKEVENT,
            sdl.SDL_FIRSTEVENT,
            sdl.SDL_LASTEVENT,
        );

        const events =
            if (num_events < 0)
        e: {
            log.err(@src(), "Cannot get SDL events: {s}", .{sdl.SDL_GetError()});
            break :e sdl_events[0..0];
        } else sdl_events[0..@intCast(num_events)];

        for (events) |event| {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    stop = true;
                },
                sdl.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == sdl.SDLK_F5) {
                        log.info(@src(), "Loading new runtime", .{});
                        if (try runtime_watch.has_event()) {
                            if (runtime_load.get_runtime_fn()) |new_runtime_fn| {
                                log.info(@src(), "Loaded new runtime", .{});
                                runtime_fn = @ptrCast(new_runtime_fn);
                            } else |e| {
                                log.err(@src(), "Cannot load new runtime due to the error: {any}", .{e});
                            }
                        }
                    }
                },
                else => {},
            }
        }
        runtime_data = runtime_fn(window, events.ptr, events.len, &memory, dt, runtime_data);
    }
}

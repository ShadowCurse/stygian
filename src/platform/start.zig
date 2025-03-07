const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const log = @import("../log.zig");
const sdl = @import("../bindings/sdl.zig");

const Memory = @import("../memory.zig");
const Events = @import("event.zig");
const RuntimeFn = *fn (
    *sdl.SDL_Window,
    [*]const Events.Event,
    usize,
    *Memory,
    f32,
    ?*anyopaque,
) *anyopaque;

const RUNTIME_LIB_PATH: [:0]const u8 = std.fmt.comptimePrint("{s}", .{build_options.lib_path});

// TODO mention that this is needed in the actual main in the platform
// It has no effect here.
pub const os = if (builtin.os.tag != .emscripten) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

pub const log_options = log.Options{
    .level = .Info,
};

pub const WINDOW_WIDTH = build_options.window_width;
pub const WINDOW_HEIGHT = build_options.window_height;
pub const FPS = build_options.limit_fps;
pub const FRAME_TIME = 1.0 / @as(f32, FPS);

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

const EmscriptenPlatform = struct {
    extern fn runtime_main(
        *sdl.SDL_Window,
        [*]const Events.Event,
        usize,
        *Memory,
        f32,
        ?*anyopaque,
    ) *anyopaque;

    pub fn run(window: *sdl.SDL_Window) !void {
        const EmscriptenGlobals = struct {
            var memory: Memory = undefined;
            var w: *sdl.SDL_Window = undefined;
            var stop = false;
            var t: i128 = undefined;
            var runtime_data: ?*anyopaque = null;
            var events: [Events.MAX_EVENTS]Events.Event = undefined;

            const Self = @This();

            fn loop() callconv(.C) void {
                const new_t = std.time.nanoTimestamp();
                var dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
                Self.t = new_t;
                if (dt < FRAME_TIME) {
                    std.time.sleep(@intFromFloat((FRAME_TIME - dt) * std.time.ns_per_s));
                    dt = FRAME_TIME;
                }

                const filled_events = Events.get(&events);
                for (filled_events) |event| {
                    switch (event) {
                        Events.Event.Quit => {
                            stop = true;
                        },
                        else => {},
                    }
                }

                Self.runtime_data = runtime_main(
                    Self.w,
                    filled_events.ptr,
                    filled_events.len,
                    &Self.memory,
                    dt,
                    Self.runtime_data,
                );
            }
        };
        EmscriptenGlobals.memory = try Memory.init();
        EmscriptenGlobals.w = window;
        EmscriptenGlobals.t = std.time.nanoTimestamp();

        std.os.emscripten.emscripten_set_main_loop(EmscriptenGlobals.loop, 0, 1);
    }
};

const UnibuildPlatform = struct {
    extern fn runtime_main(
        *sdl.SDL_Window,
        [*]const Events.Event,
        usize,
        *Memory,
        f32,
        ?*anyopaque,
    ) *anyopaque;

    pub fn run(window: *sdl.SDL_Window) !void {
        var memory = try Memory.init();
        var events: [Events.MAX_EVENTS]Events.Event = undefined;
        var stop = false;
        var t = std.time.nanoTimestamp();
        var runtime_data: ?*anyopaque = null;

        while (!stop) {
            const new_t = std.time.nanoTimestamp();
            var dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
            t = new_t;
            if (dt < FRAME_TIME) {
                std.time.sleep(@intFromFloat((FRAME_TIME - dt) * std.time.ns_per_s));
                dt = FRAME_TIME;
            }

            const filled_events = Events.get(&events);
            for (filled_events) |event| {
                switch (event) {
                    Events.Event.Quit => {
                        stop = true;
                    },
                    else => {},
                }
            }
            runtime_data = runtime_main(
                window,
                filled_events.ptr,
                filled_events.len,
                &memory,
                dt,
                runtime_data,
            );
        }
    }
};

const DynamicPlatform = struct {
    pub fn run(window: *sdl.SDL_Window) !void {
        var memory = try Memory.init();
        var events: [Events.MAX_EVENTS]Events.Event = undefined;
        var stop = false;
        var t = std.time.nanoTimestamp();
        var runtime_data: ?*anyopaque = null;

        var runtime_load: RuntimeLoad = .{};
        var runtime_main: RuntimeFn = @ptrCast(try runtime_load.get_runtime_fn());
        while (!stop) {
            const new_t = std.time.nanoTimestamp();
            var dt = @as(f32, @floatFromInt(new_t - t)) / std.time.ns_per_s;
            t = new_t;
            if (dt < FRAME_TIME) {
                std.time.sleep(@intFromFloat((FRAME_TIME - dt) * std.time.ns_per_s));
                dt = FRAME_TIME;
            }
            const filled_events = Events.get(&events);
            for (filled_events) |event| {
                switch (event) {
                    .Quit => {
                        stop = true;
                    },
                    .Keyboard => |key| {
                        if (key.key == .F5) {
                            log.info(@src(), "Loading new runtime", .{});
                            if (runtime_load.get_runtime_fn()) |new_runtime_main| {
                                log.info(@src(), "Loaded new runtime", .{});
                                runtime_main = @ptrCast(new_runtime_main);
                            } else |e| {
                                log.err(@src(), "Cannot load new runtime due to the error: {any}", .{e});
                            }
                        }
                    },
                    else => {},
                }
            }
            runtime_data = runtime_main(
                window,
                filled_events.ptr,
                filled_events.len,
                &memory,
                dt,
                runtime_data,
            );
        }
    }
};

pub fn platform_start() !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO)) {
        log.err(@src(), "Cannot init SDL: {s}", .{sdl.SDL_GetError()});
        return error.SDLInit;
    }
    const window = sdl.SDL_CreateWindow(
        "stygian",
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        0,
    ) orelse {
        log.err(@src(), "Cannot create a window: {s}", .{sdl.SDL_GetError()});
        return error.SDLCreateWindow;
    };
    if (!sdl.SDL_ShowWindow(window)) {
        log.err(@src(), "Cannot show a window: {s}", .{sdl.SDL_GetError()});
        return error.SDLShowWindow;
    }

    if (builtin.os.tag == .emscripten) {
        try EmscriptenPlatform.run(window);
    } else if (build_options.unibuild) {
        try UnibuildPlatform.run(window);
    } else {
        try DynamicPlatform.run(window);
    }
}

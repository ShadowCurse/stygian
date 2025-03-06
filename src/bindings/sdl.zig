const builtin = @import("builtin");

const sdl = if (builtin.os.tag == .emscripten)
    @cImport({
        @cInclude("SDL/SDL.h");
    })
else
    @cImport({
        @cInclude("SDL2/SDL.h");
    });

pub const SDL_VideoData = extern struct {
    _: u32,
    display: *anyopaque,
};

pub const SDL_WindowData = extern struct {
    window: *anyopaque,
    data: *SDL_VideoData,
    surface: *anyopaque,
};

pub const SDL_Rect = extern struct { x: u32, y: u32, w: u32, h: u32 };

pub const SDL_Window = extern struct {
    magic: *anyopaque,
    id: u32,
    title: *anyopaque,
    icon: *anyopaque,
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    min_w: u32,
    min_h: u32,
    max_w: u32,
    max_h: u32,
    flags: u32,
    last_fullscreen_flags: u32,
    display_index: u32,
    windowed: SDL_Rect,
    fullscreen_mode: extern struct {
        format: u32,
        w: u32,
        h: u32,
        refresh_rate: u32,
        driverdata: *anyopaque,
    },
    opacity: f32,
    brightness: f32,
    gamma: *anyopaque,
    saved_gamma: *anyopaque,
    surface: *anyopaque,
    surface_valid: u32,
    is_hiding: u32,
    is_destroying: u32,
    is_dropping: u32,
    mouse_rect: SDL_Rect,
    shaper: *anyopaque,
    hit_test: *anyopaque,
    hit_test_data: *anyopaque,
    data: *anyopaque,
    driverdata: *SDL_WindowData,
};

pub const SDL_Init = sdl.SDL_Init;
pub extern fn SDL_GetWindowSize(window: *SDL_Window, w: [*c]c_int, h: [*c]c_int) void;
pub const SDL_GetError = sdl.SDL_GetError;
pub extern fn SDL_CreateWindow(
    title: [*c]const u8,
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
    flags: u32,
) ?*SDL_Window;
pub extern fn SDL_ShowWindow(window: *SDL_Window) void;
pub const SDL_FlushEvents = sdl.SDL_FlushEvents;
pub const SDL_PumpEvents = sdl.SDL_PumpEvents;
pub const SDL_PeepEvents = sdl.SDL_PeepEvents;
pub const SDL_Event = sdl.SDL_Event;
pub const SDL_FIRSTEVENT = sdl.SDL_FIRSTEVENT;
pub const SDL_LASTEVENT = sdl.SDL_LASTEVENT;
pub const SDL_PEEKEVENT = sdl.SDL_PEEKEVENT;
pub const SDL_QUIT = sdl.SDL_QUIT;
pub const SDL_TEXTINPUT = sdl.SDL_TEXTINPUT;
pub const SDL_KEYDOWN = sdl.SDL_KEYDOWN;
pub const SDL_KEYUP = sdl.SDL_KEYUP;
pub const SDL_MOUSEMOTION = sdl.SDL_MOUSEMOTION;
pub const SDL_MOUSEBUTTONDOWN = sdl.SDL_MOUSEBUTTONDOWN;
pub const SDL_MOUSEBUTTONUP = sdl.SDL_MOUSEBUTTONUP;
pub const SDL_MOUSEWHEEL = sdl.SDL_MOUSEWHEEL;
pub const SDL_WINDOWPOS_UNDEFINED = sdl.SDL_WINDOWPOS_UNDEFINED;
pub const SDL_INIT_VIDEO = sdl.SDL_INIT_VIDEO;
pub const SDL_INIT_AUDIO = sdl.SDL_INIT_AUDIO;

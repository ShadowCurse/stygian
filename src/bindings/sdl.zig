const builtin = @import("builtin");

const sdl = if (builtin.os.tag == .emscripten)
    @cImport({
        @cInclude("SDL/SDL.h");
    })
else
    @cImport({
        @cInclude("SDL3/SDL.h");
    });

const SDL_VideoData = extern struct {
    _: u32,
    display: *anyopaque,
};
const SDL_WindowData = extern struct {
    window: *anyopaque,
    data: *SDL_VideoData,
    surface: *anyopaque,
};

const SDL_Rect = extern struct { x: u32, y: u32, w: u32, h: u32 };
const SDL_DisplayMode = extern struct {
    format: u32,
    w: u32,
    h: u32,
    refresh_rate: u32,
    driverdata: *anyopaque,
};
const SDL_HDROutputProperties = extern struct {
    SDR_white_level: f32,
    HDR_headroom: f32,
};

const SDL_WindowFlags = u64;
const SDL_DisplayID = u32;
const SDL_PropertiesID = u32;
pub const SDL_Window = extern struct {
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
    min_aspect: f32,
    max_aspect: f32,
    last_pixel_w: u32,
    last_pixel_h: u32,
    flags: SDL_WindowFlags,
    pending_flags: SDL_WindowFlags,
    display_scale: f32,

    external_graphics_context: u32,
    fullscreen_exclusive: u32,

    last_fullscreen_exclusive_display: SDL_DisplayID,
    last_displayID: SDL_DisplayID,

    windowed: SDL_Rect,
    floating: SDL_Rect,
    pending: SDL_Rect,

    titled: u32,
    undefined_x: u32,
    undefined_y: u32,

    requested_fullscreen_mode: SDL_DisplayMode,
    current_fullscreen_mode: SDL_DisplayMode,
    HDR: SDL_HDROutputProperties,

    opacity: f32,
    surface: *anyopaque,
    surface_valid: u32,

    is_hiding: u32,
    restore_on_show: u32,
    last_position_pending: u32,
    last_size_pending: u32,
    is_destroying: u32,
    is_dropping: u32,

    safe_inset_left: u32,
    safe_inset_right: u32,
    safe_inset_top: u32,
    safe_inset_bottom: u32,
    safe_rect: SDL_Rect,

    text_input_props: SDL_PropertiesID,
    text_input_active: u32,
    text_input_rect: SDL_Rect,
    text_input_cursor: u32,

    mouse_rect: SDL_Rect,

    hit_test: *anyopaque,
    hit_test_data: *anyopaque,

    props: SDL_PropertiesID,

    num_renderers: u32,
    renderers: *anyopaque,

    // TODO figure out where missing 8 bytes are
    __shoult_not_be_here: u64,
    internal: *SDL_WindowData,
};

pub const SDL_InitFlags = u32;
pub extern fn SDL_Init(flags: SDL_InitFlags) bool;
pub extern fn SDL_GetWindowSize(window: *SDL_Window, w: *i32, h: *i32) bool;
pub extern fn SDL_GetError() [*c]const u8;
pub extern fn SDL_CreateWindow(
    title: [*c]const u8,
    w: c_int,
    h: c_int,
    flags: SDL_WindowFlags,
) ?*SDL_Window;
pub extern fn SDL_ShowWindow(window: *SDL_Window) bool;
pub extern fn SDL_FlushEvents(minType: u32, maxType: u32) void;
pub extern fn SDL_PumpEvents() void;
pub extern fn SDL_PeepEvents(
    events: [*]SDL_Event,
    numevents: c_int,
    action: u32,
    minType: u32,
    maxType: u32,
) i32;
pub extern fn SDL_PollEvent(event: *SDL_Event) bool;

pub extern fn SDL_CreateRenderer(window: *SDL_Window, name: [*c]const u8) ?*SDL_Renderer;

pub const SDL_PixelFormat = u32;
pub const SDL_TextureAccess = u32;
pub extern fn SDL_CreateTexture(
    renderer: *SDL_Renderer,
    format: SDL_PixelFormat,
    access: SDL_TextureAccess,
    w: i32,
    h: i32,
) ?*SDL_Texture;
pub extern fn SDL_UpdateTexture(
    texture: *SDL_Texture,
    rect: ?*const SDL_Rect,
    pixels: ?*const anyopaque,
    pitch: i32,
) bool;
pub const SDL_FRect = sdl.SDL_FRect;
pub extern fn SDL_RenderTexture(
    renderer: *SDL_Renderer,
    texture: *SDL_Texture,
    srcrect: ?*const SDL_FRect,
    dstrect: ?*const SDL_FRect,
) bool;
pub extern fn SDL_RenderPresent(renderer: *SDL_Renderer) bool;
pub const SDL_TEXTUREACCESS_STREAMING = sdl.SDL_TEXTUREACCESS_STREAMING;

pub const SDL_AudioDeviceID = sdl.SDL_AudioDeviceID;
pub const SDL_AudioSpec = sdl.SDL_AudioSpec;
pub const SDL_AUDIO_S16 = sdl.SDL_AUDIO_S16;
pub const SDL_AudioStream = sdl.SDL_AudioStream;
pub const SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK = sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK;
pub const SDL_PutAudioStreamData = sdl.SDL_PutAudioStreamData;
pub const SDL_OpenAudioDeviceStream = sdl.SDL_OpenAudioDeviceStream;
pub const SDL_PauseAudioStreamDevice = sdl.SDL_PauseAudioStreamDevice;
pub const SDL_ResumeAudioStreamDevice = sdl.SDL_ResumeAudioStreamDevice;
pub const SDL_LoadWAV = sdl.SDL_LoadWAV;
pub const SDL_free = sdl.SDL_free;

pub const SDL_Renderer = sdl.SDL_Renderer;
pub const SDL_Texture = sdl.SDL_Texture;
pub const SDL_Event = sdl.SDL_Event;
pub const SDL_EVENT_FIRST = sdl.SDL_EVENT_FIRST;
pub const SDL_EVENT_LAST = sdl.SDL_EVENT_LAST;
pub const SDL_PEEKEVENT = sdl.SDL_PEEKEVENT;
pub const SDL_EVENT_QUIT = sdl.SDL_EVENT_QUIT;
pub const SDL_EVENT_TEXT_INPUT = sdl.SDL_EVENT_TEXT_INPUT;
pub const SDL_EVENT_KEY_DOWN = sdl.SDL_EVENT_KEY_DOWN;
pub const SDL_EVENT_KEY_UP = sdl.SDL_EVENT_KEY_UP;
pub const SDL_EVENT_MOUSE_MOTION = sdl.SDL_EVENT_MOUSE_MOTION;
pub const SDL_EVENT_MOUSE_BUTTON_DOWN = sdl.SDL_EVENT_MOUSE_BUTTON_DOWN;
pub const SDL_EVENT_MOUSE_BUTTON_UP = sdl.SDL_EVENT_MOUSE_BUTTON_UP;
pub const SDL_EVENT_MOUSE_WHEEL = sdl.SDL_EVENT_MOUSE_WHEEL;
pub const SDL_INIT_AUDIO = sdl.SDL_INIT_AUDIO;

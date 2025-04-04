const builtin = @import("builtin");

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
});

pub const SDL_WINDOW_VULKAN = sdl.SDL_WINDOW_VULKAN;
pub const SDL_Vulkan_CreateSurface = sdl.SDL_Vulkan_CreateSurface;
pub const SDL_Vulakn_GetInstanceExtensions = sdl.SDL_Vulkan_GetInstanceExtensions;

pub const SDL_INIT_VIDIO = sdl.SDL_INIT_VIDEO;
pub const SDL_INIT_AUDIO = sdl.SDL_INIT_AUDIO;
pub const SDL_Init = sdl.SDL_Init;
pub const SDL_GetError = sdl.SDL_GetError;

pub const SDL_Window = sdl.SDL_Window;
pub const SDL_CreateWindow = sdl.SDL_CreateWindow;
pub const SDL_GetWindowSize = sdl.SDL_GetWindowSize;
pub const SDL_ShowWindow = sdl.SDL_ShowWindow;

pub const SDL_FlushEvents = sdl.SDL_FlushEvents;
pub const SDL_PumpEvents = sdl.SDL_PumpEvents;
pub const SDL_PeepEvents = sdl.SDL_PeepEvents;
pub const SDL_PollEvent = sdl.SDL_PollEvent;
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

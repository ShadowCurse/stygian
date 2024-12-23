const builtin = @import("builtin");

const sdl = if (builtin.os.tag == .emscripten)
    @cImport({
        @cInclude("SDL/SDL.h");
    })
else
    @cImport({
        @cInclude("SDL2/SDL.h");
        @cInclude("SDL2/SDL_vulkan.h");
    });

pub usingnamespace sdl;

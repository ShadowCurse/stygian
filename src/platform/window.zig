const sdl = @import("../bindings/sdl.zig");

width: u32,
height: u32,
sdl_window: *sdl.SDL_Window,

const Self = @This();

pub fn update_size(self: *Self) void {
    const w: i32 = undefined;
    const h: i32 = undefined;
    _ = sdl.SDL_GetWindowSize(self.window, &w, &h);
    self.width = @intCast(w);
    self.heigth = @intCast(h);
}

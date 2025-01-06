const std = @import("std");
const log = @import("log.zig");
const stb = @import("bindings/stb.zig");
const platform = @import("platform/posix.zig");

const Textures = @import("textures.zig");
const Memory = @import("memory.zig");

const Self = @This();

size: f32 = 0,
char_info: []stb.stbtt_bakedchar = &.{},
texture_id: u32 = Textures.Texture.ID_DEBUG,

pub fn init(
    memory: *Memory,
    texture_store: *Textures.Store,
    path: [:0]const u8,
    font_size: f32,
) Self {
    if (texture_store.reserve()) |texture_id| {
        const texture = texture_store.get_texture_mut(texture_id);
        const game_alloc = memory.game_alloc();

        const fm = platform.FileMem.init(path) catch |e| {
            log.err(
                @src(),
                "Cannot get file memory for a font. Font path: {s} error: {}",
                .{ path, e },
            );
            return .{};
        };
        defer fm.deinit();

        var stb_font: stb.stbtt_fontinfo = undefined;
        _ = stb.stbtt_InitFont(
            &stb_font,
            fm.mem.ptr,
            stb.stbtt_GetFontOffsetForIndex(fm.mem.ptr, 0),
        );

        const char_info = game_alloc.alloc(
            stb.stbtt_bakedchar,
            @intCast(stb_font.numGlyphs),
        ) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a font char info. Font path: {s} error: {}",
                .{ path, e },
            );
            return .{};
        };
        errdefer game_alloc.free(char_info);

        const bitmap = game_alloc.alignedAlloc(u8, 4, 512 * 512) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a font bitmap. Font path: {s} error: {}",
                .{ path, e },
            );
            return .{};
        };
        errdefer game_alloc.free(bitmap);

        _ = stb.stbtt_BakeFontBitmap(
            fm.mem.ptr,
            0,
            font_size,
            bitmap.ptr,
            512,
            512,
            0,
            stb_font.numGlyphs,
            char_info.ptr,
        );

        texture.* = .{
            .data = bitmap,
            .width = 512,
            .height = 512,
            .channels = 1,
        };

        return .{
            .size = font_size,
            .char_info = char_info,
            .texture_id = texture_id,
        };
    } else {
        log.err(
            @src(),
            "Trying to load font from {s}, but there are no space in the texture store",
            .{path},
        );
        return .{};
    }
}

pub fn deinit(self: *const Self, memory: *Memory) void {
    const game_alloc = memory.game_alloc();
    game_alloc.free(self.char_info);
}

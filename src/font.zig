const std = @import("std");
const log = @import("log.zig");
const stb = @import("bindings/stb.zig");
const platform = @import("platform/posix.zig");

const Textures = @import("textures.zig");
const Memory = @import("memory.zig");

const Self = @This();

size: f32,
scale: f32 = 0.0,
char_info: []stb.stbtt_bakedchar = &.{},
kerning_table: []KerningInfo = &.{},
texture_id: u32 = Textures.Texture.ID_DEBUG,

pub const FIRST_CHAR = ' ';
pub const ALL_CHARS =
    " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

pub const KerningInfo = struct {
    char_1: u8 = 0,
    char_2: u8 = 0,
    kerning: i32 = 0,
};

pub const INVALID_CHAR_INFO: stb.stbtt_bakedchar = .{
    .x0 = 0,
    .x1 = Textures.Store.DEBUG_WIDTH,
    .y0 = 0,
    .y1 = Textures.Store.DEBUG_HEIGHT,
    .xoff = 0.0,
    .yoff = 0.0,
    .xadvance = Textures.Store.DEBUG_WIDTH,
};

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
            return .{
                .size = font_size,
            };
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
            return .{
                .size = font_size,
            };
        };
        errdefer game_alloc.free(char_info);

        const bitmap = game_alloc.alignedAlloc(u8, 4, 512 * 512) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a font bitmap. Font path: {s} error: {}",
                .{ path, e },
            );
            return .{
                .size = font_size,
            };
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

        const scale = stb.stbtt_ScaleForPixelHeight(&stb_font, font_size);
        const kerning_table = game_alloc.alloc(KerningInfo, ALL_CHARS.len * ALL_CHARS.len) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a font kerning table. Font path: {s} error: {}",
                .{ path, e },
            );
            return .{
                .size = font_size,
            };
        };
        errdefer game_alloc.free(kerning_table);

        var kerning_table_index: u32 = 0;
        for (ALL_CHARS) |c1| {
            for (ALL_CHARS) |c2| {
                const kerning = stb.stbtt_GetCodepointKernAdvance(&stb_font, c1, c2);
                kerning_table[kerning_table_index] = .{
                    .char_1 = c1,
                    .char_2 = c2,
                    .kerning = kerning,
                };
                kerning_table_index += 1;
            }
        }

        texture.* = .{
            .data = bitmap,
            .width = 512,
            .height = 512,
            .channels = 1,
        };

        return .{
            .size = font_size,
            .scale = scale,
            .char_info = char_info,
            .kerning_table = kerning_table,
            .texture_id = texture_id,
        };
    } else {
        log.err(
            @src(),
            "Trying to load font from {s}, but there are no space in the texture store",
            .{path},
        );
        return .{
            .size = font_size,
        };
    }
}

pub fn deinit(self: *const Self, memory: *Memory) void {
    const game_alloc = memory.game_alloc();
    game_alloc.free(self.char_info);
}

pub fn get_kerning(self: *const Self, char_1: u8, char_2: u8) i32 {
    const index = char_1 - FIRST_CHAR;
    const offset = char_2 - FIRST_CHAR;
    const info = self.kerning_table[index * ALL_CHARS.len + offset];
    log.assert(
        @src(),
        info.char_1 == char_1 and info.char_2 == char_2,
        "Tryingt to get a kerninig info for pair {c}/{c} but got one for pair {c}/{c}",
        .{ char_1, char_2, info.char_1, info.char_2 },
    );
    return info.kerning;
}

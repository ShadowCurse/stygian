const std = @import("std");
const stb = @import("bindings/stb.zig");
const platform = @import("platform/posix.zig");

const Image = @import("image.zig");
const Memory = @import("memory.zig");

pub const Font = struct {
    const Self = @This();

    size: f32,
    char_info: []stb.stbtt_bakedchar,
    image: Image,
    image_id: u32,

    pub fn init(memory: *Memory, path: [:0]const u8, font_size: f32) !Self {
        const game_alloc = memory.game_alloc();

        const fm = try platform.FileMem.init(path);
        defer fm.deinit();

        var stb_font: stb.stbtt_fontinfo = undefined;
        _ = stb.stbtt_InitFont(
            &stb_font,
            fm.mem.ptr,
            stb.stbtt_GetFontOffsetForIndex(fm.mem.ptr, 0),
        );

        const char_info = try game_alloc.alloc(stb.stbtt_bakedchar, @intCast(stb_font.numGlyphs));
        const bitmap = try game_alloc.alloc(u8, 512 * 512);

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

        const image = Image{
            .data = bitmap,
            .width = 512,
            .height = 512,
            .channels = 1,
        };

        return .{
            .size = font_size,
            .char_info = char_info,
            .image = image,
            .image_id = 0,
        };
    }

    pub fn deinit(self: *const Self, memory: *Memory) void {
        const game_alloc = memory.game_alloc();
        game_alloc.free(self.char_info);
    }
};

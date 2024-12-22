const std = @import("std");
const stb = @import("bindings/stb.zig");

const Image = @import("image.zig");
const Memory = @import("memory.zig");

pub const Font = struct {
    const Self = @This();

    size: f32,
    char_info: []stb.stbtt_bakedchar,
    image: Image,

    pub fn init(memory: *Memory, path: [:0]const u8, font_size: f32) !Self {
        const game_alloc = memory.game_alloc();

        const fd = try std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0);
        defer std.posix.close(fd);

        const stat = try std.posix.fstat(fd);
        const file_mem = try std.posix.mmap(
            null,
            @intCast(stat.size),
            std.posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            fd,
            0,
        );
        defer std.posix.munmap(file_mem);

        var stb_font: stb.stbtt_fontinfo = undefined;
        _ = stb.stbtt_InitFont(
            &stb_font,
            file_mem.ptr,
            stb.stbtt_GetFontOffsetForIndex(file_mem.ptr, 0),
        );

        const char_info = try game_alloc.alloc(stb.stbtt_bakedchar, @intCast(stb_font.numGlyphs));
        const bitmap = try game_alloc.alloc(u8, 512 * 512);

        _ = stb.stbtt_BakeFontBitmap(
            file_mem.ptr,
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
        };
    }

    pub fn deinit(self: *const Self, memory: *Memory) void {
        const game_alloc = memory.game_alloc();
        game_alloc.free(self.char_info);
    }
};

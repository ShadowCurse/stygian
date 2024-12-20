const std = @import("std");
const log = @import("log.zig");
const stb = @import("bindings/stb.zig");

const Memory = @import("memory.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;

const Image = @import("image.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const RenderUiQuadInfo = @import("vk_renderer/ui_quad.zig").RenderUiQuadInfo;

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

pub const UiText = struct {
    const Self = @This();

    screen_quads: RenderUiQuadInfo,
    max_text_len: u32,
    current_text_len: u32,

    pub fn init(renderer: *VkRenderer, max_text_len: u32) !Self {
        const screen_quads = try RenderUiQuadInfo.init(renderer, max_text_len);
        return .{
            .screen_quads = screen_quads,
            .max_text_len = max_text_len,
            .current_text_len = 0,
        };
    }

    pub fn set_text(
        self: *Self,
        font: *const Font,
        text: []const u8,
        screen_size: Vec2,
        pos: Vec2,
        // size: Vec2,
    ) void {
        if (self.max_text_len < text.len) {
            log.err(
                @src(),
                "trying to set ui text with len: {} which is bigger than max: {}",
                .{ text.len, self.max_text_len },
            );
            return;
        }
        self.current_text_len = @intCast(text.len);

        var x_offset: f32 = -font.size * @as(f32, @floatFromInt(text.len / 2));
        for (text, 0..) |c, i| {
            const char_info = font.char_info[c];
            self.screen_quads.set_instance_info(@intCast(i), .{
                .color = .{},
                .type = .Font,
                .pos = .{
                    .x = (pos.x + x_offset) / (screen_size.x / 2.0),
                    .y = pos.y / (screen_size.y / 2.0),
                },
                .scale = .{
                    .x = @as(f32, @floatFromInt(char_info.x1 - char_info.x0)) / screen_size.x,
                    .y = @as(f32, @floatFromInt(char_info.y1 - char_info.y0)) / screen_size.y,
                },
                .uv_pos = .{
                    .x = @as(f32, @floatFromInt(char_info.x0)) /
                        @as(f32, @floatFromInt(font.image.width)),
                    .y = @as(f32, @floatFromInt(char_info.y0)) /
                        @as(f32, @floatFromInt(font.image.height)),
                },
                .uv_scale = .{
                    .x = @as(f32, @floatFromInt((char_info.x1 - char_info.x0))) / @as(
                        f32,
                        @floatFromInt(font.image.width),
                    ),
                    .y = @as(f32, @floatFromInt((char_info.y1 - char_info.y0))) / @as(
                        f32,
                        @floatFromInt(font.image.height),
                    ),
                },
            });
            x_offset += char_info.xadvance;
        }
    }

    pub fn deinit(self: *const Self, renderer: *VkRenderer) void {
        self.screen_quads.deinit(renderer);
    }
};

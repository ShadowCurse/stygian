const std = @import("std");
const log = @import("log.zig");

const Memory = @import("memory.zig");
const Allocator = std.mem.Allocator;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;

const Image = @import("image.zig");
const GpuImage = @import("vk_renderer/gpu_image.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const RenderUiQuadInfo = @import("vk_renderer/ui_quad.zig").RenderUiQuadInfo;

pub const Font = struct {
    const Self = @This();

    image: Image,
    texture: GpuImage,

    pub fn init(renderer: *VkRenderer, path: [:0]const u8) !Self {
        const image = try Image.init(path);
        const texture = try renderer.create_texture(image.width, image.height);
        try renderer.upload_texture_image(&texture, &image);

        return .{
            .image = image,
            .texture = texture,
        };
    }

    pub fn deinit(self: *const Self, renderer: *VkRenderer) void {
        self.image.deinit();
        renderer.delete_texture(&self.texture);
    }
};

pub const FontInfo = struct {
    const Self = @This();

    const Char = struct {
        char: u8,

        pub fn jsonParse(
            allocator: Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !Char {
            _ = allocator;
            _ = options;
            return switch (try source.next()) {
                .string => |s| .{ .char = s[0] },
                else => error.UnexpectedToken,
            };
        }
    };

    const CharInfo = struct {
        char: Char,
        x: u16,
        y: u16,
        width: u16,
        height: u16,
        originX: u16,
        originY: u16,
        advance: u16,
    };

    name: []const u8,
    size: u8,
    bold: bool,
    italic: bool,
    width: u16,
    height: u16,
    characters: []const CharInfo,

    pub fn init(memory: *Memory, path: []const u8) !Self {
        const game_allocator = memory.game_alloc();
        const scratch_alloc = memory.scratch_alloc();

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_data = try file.readToEndAlloc(scratch_alloc, 1024 * 1024 * 1024);

        const font_info = try std.json.parseFromSlice(Self, scratch_alloc, file_data, .{});
        defer font_info.deinit();

        return .{
            .name = try game_allocator.dupe(u8, font_info.value.name),
            .size = font_info.value.size,
            .bold = font_info.value.bold,
            .italic = font_info.value.italic,
            .width = font_info.value.width,
            .height = font_info.value.height,
            .characters = try game_allocator.dupe(CharInfo, font_info.value.characters),
        };
    }

    pub fn deinit(self: *const Self, memory: *Memory) void {
        const game_allocator = memory.game_alloc();

        game_allocator.free(self.name);
        game_allocator.free(self.characters);
    }

    pub fn char_info(self: *const Self, char: u8) ?*const CharInfo {
        for (self.characters) |*c| {
            if (c.char.char == char) {
                return c;
            }
        }
        return null;
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

    pub fn set_text(self: *Self, font_info: *const FontInfo, text: []const u8, screen_size: Vec2, pos: Vec2, size: Vec2) void {
        if (self.max_text_len < text.len) {
            log.err(
                @src(),
                "trying to set ui text with len: {} which is bigger than max: {}",
                .{ text.len, self.max_text_len },
            );
            return;
        }
        self.current_text_len = @intCast(text.len);

        var x_offset: f32 = -size.x * @as(f32, @floatFromInt(text.len / 2));
        for (text, 0..) |c, i| {
            if (font_info.char_info(c)) |char_info| {
                self.screen_quads.set_instance_info(@intCast(i), .{
                    .color = .{},
                    .type = .Font,
                    .pos = .{
                        .x = (pos.x + x_offset) / (screen_size.x / 2.0),
                        .y = pos.y / (screen_size.y / 2.0),
                    },
                    .scale = .{
                        .x = size.x / screen_size.x,
                        .y = size.y / screen_size.y,
                    },
                    .uv_pos = .{
                        .x = @as(f32, @floatFromInt(char_info.x + char_info.originX)) /
                            @as(f32, @floatFromInt(font_info.width)),
                        .y = @as(f32, @floatFromInt(char_info.y + char_info.originY - font_info.size)) /
                            @as(f32, @floatFromInt(font_info.height)),
                    },
                    .uv_scale = .{
                        .x = @as(f32, @floatFromInt(char_info.advance)) / @as(f32, @floatFromInt(font_info.width)),
                        .y = @as(f32, @floatFromInt(font_info.size)) / @as(f32, @floatFromInt(font_info.height)),
                    },
                });
                x_offset += size.x;
            }
        }
    }

    pub fn deinit(self: *const Self, renderer: *VkRenderer) void {
        self.screen_quads.deinit(renderer);
    }
};

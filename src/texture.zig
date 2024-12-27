const std = @import("std");
const log = @import("log.zig");
const stb = @import("bindings/stb.zig");

const Color = @import("color.zig").Color;
const Memory = @import("memory.zig");

pub const TextureId = u32;
pub const TEXTURE_ID_VERT_COLOR = std.math.maxInt(u32);
pub const TEXTURE_ID_SOLID_COLOR = std.math.maxInt(u32) - 1;

pub const Texture = struct {
    width: u32,
    height: u32,
    channels: u32,
    data: []u8,

    const Self = @This();

    pub fn as_color_slice(self: Self) []Color {
        log.assert(
            @src(),
            self.channels == 4,
            "Trying to convert texture with {} channels to a slice of Color",
            .{self.channels},
        );
        var slice: []Color = undefined;
        slice.ptr = @alignCast(@ptrCast(self.data.ptr));
        slice.len = self.data.len / 4;
        return slice;
    }
};

// This type assumes it will never be moved
pub const TextureStore = struct {
    textures: []Texture,
    textures_num: u32,

    pub const DEBUG_TEXTURE_ID = 0;
    pub const DEBUG_WIDTH = 16;
    pub const DEBUG_HEIGHT = 16;
    pub const DEBUG_CHANNELS = 4;

    pub const MAX_TEXTURES = 8;
    const Self = @This();

    pub fn init(self: *Self, memory: *Memory) !void {
        const game_alloc = memory.game_alloc();

        self.textures = try game_alloc.alloc(Texture, MAX_TEXTURES);
        var debug_texture_data = try game_alloc.alloc(Color, DEBUG_WIDTH * DEBUG_HEIGHT);
        for (0..DEBUG_HEIGHT) |y| {
            for (0..DEBUG_WIDTH) |x| {
                debug_texture_data[y * DEBUG_WIDTH + x] = if ((x % 2) ^ (y % 2) != 0)
                    Color.MAGENTA
                else
                    Color.GREY;
            }
        }
        var data_u8: []u8 = undefined;
        data_u8.ptr = @ptrCast(debug_texture_data.ptr);
        data_u8.len = debug_texture_data.len * DEBUG_CHANNELS;

        self.textures[DEBUG_TEXTURE_ID] = .{
            .width = DEBUG_WIDTH,
            .height = DEBUG_HEIGHT,
            .channels = DEBUG_CHANNELS,
            .data = data_u8,
        };
        self.textures_num = 1;
    }

    pub fn reserve(self: *Self) ?TextureId {
        if (self.textures_num != self.textures.len) {
            const id = self.textures_num;
            self.textures_num += 1;
            return id;
        } else {
            return null;
        }
    }

    pub fn load(self: *Self, memory: *Memory, path: [:0]const u8) TextureId {
        const game_alloc = memory.game_alloc();

        if (self.textures_num == self.textures.len) {
            log.err(
                @src(),
                "Trying to load more textures than capacity: MAX_TEXTURES: {}, path: {s}",
                .{ @as(u32, MAX_TEXTURES), path },
            );
            return DEBUG_TEXTURE_ID;
        }

        var x: i32 = undefined;
        var y: i32 = undefined;
        var c: i32 = undefined;
        if (@as(?[*]u8, stb.stbi_load(path, &x, &y, &c, stb.STBI_rgb_alpha))) |image| {
            defer stb.stbi_image_free(image);

            const width: u32 = @intCast(x);
            const height: u32 = @intCast(y);
            const channels: u32 = @intCast(c);

            const bytes = game_alloc.alloc(u8, width * height * channels) catch |e| {
                log.err(
                    @src(),
                    "Cannot allocate memory for a texture. Texture path: {s} error: {}",
                    .{ path, e },
                );
                return DEBUG_TEXTURE_ID;
            };
            var data: []u8 = undefined;
            data.ptr = image;
            data.len = width * height * channels;
            @memcpy(bytes, data);

            self.textures[self.textures_num] = .{
                .width = width,
                .height = height,
                .channels = channels,
                .data = bytes,
            };
            const id = self.textures_num;
            log.info(
                @src(),
                "Loaded texture from the path: {s} width: {} height: {} channels: {} id: {}",
                .{ path, width, height, channels, id },
            );
            self.textures_num += 1;
            return id;
        } else {
            log.err(@src(), "Cannot load a texture from the path: {s} error: {s}", .{
                path,
                stb.stbi_failure_reason(),
            });
            return DEBUG_TEXTURE_ID;
        }
    }

    pub fn get(self: Self, texture_id: TextureId) *const Texture {
        log.assert(
            @src(),
            texture_id < self.textures_num,
            "Trying to get texture outside the range: {} available, {} requested",
            .{ self.textures_num, texture_id },
        );
        return &self.textures[texture_id];
    }

    pub fn get_mut(self: *Self, texture_id: TextureId) *Texture {
        log.assert(
            @src(),
            texture_id < self.textures_num,
            "Trying to get texture outside the range: {} available, {} requested",
            .{ self.textures_num, texture_id },
        );
        return &self.textures[texture_id];
    }
};

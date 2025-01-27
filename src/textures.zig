const std = @import("std");
const builtin = @import("builtin");
const log = @import("log.zig");
const stb = @import("bindings/stb.zig");

const platform = @import("platform/posix.zig");
const Color = @import("color.zig").Color;
const Memory = @import("memory.zig");

pub const Texture = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,
    palette_id: ?u16 = null,
    data: []align(4) u8 = &.{},

    pub const Id = u32;
    pub const ID_DEBUG = 0;
    pub const ID_VERT_COLOR = std.math.maxInt(u32);
    pub const ID_SOLID_COLOR = std.math.maxInt(u32) - 1;

    const Self = @This();

    pub fn as_color_slice(self: Self) []Color {
        log.assert(
            @src(),
            self.channels == 4 and self.data.len % 4 == 0,
            "Trying to convert texture with {} channels and {} bytes to a slice of Color",
            .{ self.channels, self.data.len },
        );
        var slice: []Color = undefined;
        slice.ptr = @alignCast(@ptrCast(self.data.ptr));
        slice.len = self.data.len / 4;
        return slice;
    }
};

pub const Palette = struct {
    data: []align(4) u8,

    pub const Id = u16;
    pub const ID_DEBUG = 0;

    const Self = @This();

    pub fn as_color_slice(self: Self) []Color {
        log.assert(
            @src(),
            self.data.len % 4 == 0,
            "Trying to convert color palette with {} bytes to a slice of Color",
            .{self.data.len},
        );
        var slice: []Color = undefined;
        slice.ptr = @alignCast(@ptrCast(self.data.ptr));
        slice.len = self.data.len / 4;
        return slice;
    }
};

// This type assumes it will never be moved
pub const Store = struct {
    textures: []Texture,
    textures_num: u32,

    paletts: []Palette,
    paletts_num: u16,

    pub const DEBUG_WIDTH = 16;
    pub const DEBUG_HEIGHT = 16;
    pub const DEBUG_CHANNELS = 4;

    pub const MAX_TEXTURES = 32;
    pub const MAX_PALETTS = 32;

    const Self = @This();

    pub fn init(self: *Self, memory: *Memory) !void {
        const game_alloc = memory.game_alloc();

        self.textures = try game_alloc.alloc(Texture, MAX_TEXTURES);
        var debug_texture_data = try game_alloc.alignedAlloc(Color, 4, DEBUG_WIDTH * DEBUG_HEIGHT);
        for (0..DEBUG_HEIGHT) |y| {
            for (0..DEBUG_WIDTH) |x| {
                debug_texture_data[y * DEBUG_WIDTH + x] = if ((x % 2) ^ (y % 2) != 0)
                    Color.MAGENTA
                else
                    Color.GREY;
            }
        }
        var data_u8: []align(4) u8 = undefined;
        data_u8.ptr = @ptrCast(debug_texture_data.ptr);
        data_u8.len = debug_texture_data.len * DEBUG_CHANNELS;

        self.textures[Texture.ID_DEBUG] = .{
            .width = DEBUG_WIDTH,
            .height = DEBUG_HEIGHT,
            .channels = DEBUG_CHANNELS,
            .data = data_u8,
        };
        self.textures_num = 1;

        self.paletts = try game_alloc.alloc(Palette, MAX_PALETTS);
        self.paletts[0].data = try game_alloc.alignedAlloc(u8, 4, 4 * 256);
        const debug_palette_colors = self.paletts[0].as_color_slice();
        for (debug_palette_colors) |*c| {
            c.* = Color.WHITE;
        }
        self.paletts_num = 1;
    }

    pub fn reserve(self: *Store) ?Texture.Id {
        if (self.textures_num != self.textures.len) {
            const id = self.textures_num;
            self.textures_num += 1;
            return id;
        } else {
            return null;
        }
    }

    pub fn copy_texture_id(self: *Store, texture_id: Texture.Id) Texture.Id {
        if (self.textures_num == self.textures.len) {
            log.err(
                @src(),
                "Trying to copy texture id, but hit the max capacity: MAX_TEXTURES: {}, texture id: {d}",
                .{ @as(u32, MAX_TEXTURES), texture_id },
            );
            return Texture.ID_DEBUG;
        }

        const new_id = self.textures_num;
        self.textures[new_id] = self.textures[texture_id];
        self.textures_num += 1;
        log.info(
            @src(),
            "Copied texture id: {d}. New id: {d}",
            .{ texture_id, new_id },
        );
        return new_id;
    }

    pub fn clone_palette(self: *Store, memory: *Memory, palette_id: Palette.Id) Palette.Id {
        const game_alloc = memory.game_alloc();

        if (self.paletts_num == self.paletts.len) {
            log.err(
                @src(),
                "Trying to copy palette, but hit the max capacity: MAX_PALETTS: {}, palette id: {d}",
                .{ @as(u32, MAX_PALETTS), palette_id },
            );
            return Palette.ID_DEBUG;
        }

        const palette = &self.paletts[palette_id];

        const new_id = self.paletts_num;
        const palette_bytes = game_alloc.alignedAlloc(u8, 4, palette.data.len) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a palette. Palette id: {d} error: {}",
                .{ palette_id, e },
            );
            return Texture.ID_DEBUG;
        };
        self.paletts[new_id].data = palette_bytes;
        @memcpy(palette_bytes, palette.data);
        self.paletts_num += 1;
        log.info(
            @src(),
            "Copied palette with id: {d}. New id: {d}",
            .{ palette_id, new_id },
        );
        return new_id;
    }

    pub fn load(self: *Store, memory: *Memory, path: [:0]const u8) Texture.Id {
        const game_alloc = memory.game_alloc();

        if (self.textures_num == self.textures.len) {
            log.err(
                @src(),
                "Trying to load more textures than capacity: MAX_TEXTURES: {}, path: {s}",
                .{ @as(u32, MAX_TEXTURES), path },
            );
            return Texture.ID_DEBUG;
        }

        var x: i32 = undefined;
        var y: i32 = undefined;
        var c: i32 = undefined;
        if (@as(?[*]u8, stb.stbi_load(path, &x, &y, &c, stb.STBI_rgb_alpha))) |image| {
            defer stb.stbi_image_free(image);

            const width: u32 = @intCast(x);
            const height: u32 = @intCast(y);
            const channels: u32 = @intCast(c);

            const bytes = game_alloc.alignedAlloc(u8, 4, width * height * channels) catch |e| {
                log.err(
                    @src(),
                    "Cannot allocate memory for a texture. Texture path: {s} error: {}",
                    .{ path, e },
                );
                return Texture.ID_DEBUG;
            };
            var data: []u8 = undefined;
            data.ptr = image;
            data.len = width * height * channels;

            // Convert ABGR -> ARGB
            if (builtin.os.tag != .emscripten and channels == 4) {
                var bytes_u32: []u32 = undefined;
                bytes_u32.ptr = @alignCast(@ptrCast(bytes));
                bytes_u32.len = width * height;

                var data_u32: []u32 = undefined;
                data_u32.ptr = @alignCast(@ptrCast(image));
                data_u32.len = width * height;
                for (0..width * height) |i| {
                    const color: u32 = @intCast(data_u32[i]);
                    const blue = (color & 0x00FF0000) >> 16;
                    const red = color & 0x000000FF;
                    const new_color = (color & 0xFF00FF00) | (red << 16) | blue;
                    bytes_u32[i] = new_color;
                }
            } else {
                @memcpy(bytes, data);
            }

            const id = self.textures_num;
            self.textures[id] = .{
                .width = width,
                .height = height,
                .channels = channels,
                .data = bytes,
            };
            self.textures_num += 1;
            log.info(
                @src(),
                "Loaded texture from the path: {s} width: {} height: {} channels: {} id: {}",
                .{ path, width, height, channels, id },
            );
            return id;
        } else {
            log.err(@src(), "Cannot load a texture from the path: {s} error: {s}", .{
                path,
                stb.stbi_failure_reason(),
            });
            return Texture.ID_DEBUG;
        }
    }

    pub fn load_bmp(self: *Self, memory: *Memory, path: [:0]const u8) Texture.Id {
        const game_alloc = memory.game_alloc();

        if (self.textures_num == self.textures.len) {
            log.err(
                @src(),
                "Trying to load more textures than capacity: MAX_TEXTURES: {}, path: {s}",
                .{ @as(u32, MAX_TEXTURES), path },
            );
            return Texture.ID_DEBUG;
        }

        const fm = platform.FileMem.init(path) catch |e| {
            log.err(
                @src(),
                "Cannot get file memory for a font. Font path: {s} error: {}",
                .{ path, e },
            );
            return Texture.ID_DEBUG;
        };
        defer fm.deinit();

        if (!std.mem.eql(u8, fm.mem[0..2], "BM")) {
            log.err(
                @src(),
                "Trying to load BMP but the magic value is incorrect. Path: {s}",
                .{path},
            );
            return Texture.ID_DEBUG;
        }

        const bm_offset_offset = 2 + 4 + 2 + 2;
        const bm_offset: u32 =
            @as(u32, @intCast(fm.mem[bm_offset_offset + 3])) << 24 |
            @as(u32, @intCast(fm.mem[bm_offset_offset + 2])) << 16 |
            @as(u32, @intCast(fm.mem[bm_offset_offset + 1])) << 8 |
            @as(u32, @intCast(fm.mem[bm_offset_offset + 0]));
        log.debug(@src(), "offset: {d}", .{bm_offset});

        const header_size_offset = bm_offset_offset + 4;
        const header_size: u32 =
            @as(u32, @intCast(fm.mem[header_size_offset + 3])) << 24 |
            @as(u32, @intCast(fm.mem[header_size_offset + 2])) << 16 |
            @as(u32, @intCast(fm.mem[header_size_offset + 1])) << 8 |
            @as(u32, @intCast(fm.mem[header_size_offset + 0]));
        log.debug(@src(), "header_size: {d}", .{header_size});

        if (header_size < 40) {
            log.err(@src(), "Trygin to load a BMP, but the header is too old. Path: {s}", .{path});
            return Texture.ID_DEBUG;
        }

        const width_offset = header_size_offset + 4;
        const width: u32 =
            @as(u32, @intCast(fm.mem[width_offset + 3])) << 24 |
            @as(u32, @intCast(fm.mem[width_offset + 2])) << 16 |
            @as(u32, @intCast(fm.mem[width_offset + 1])) << 8 |
            @as(u32, @intCast(fm.mem[width_offset + 0]));
        log.debug(@src(), "width: {d}", .{width});

        const height_offset = width_offset + 4;
        const height: u32 =
            @as(u32, @intCast(fm.mem[height_offset + 3])) << 24 |
            @as(u32, @intCast(fm.mem[height_offset + 2])) << 16 |
            @as(u32, @intCast(fm.mem[height_offset + 1])) << 8 |
            @as(u32, @intCast(fm.mem[height_offset + 0]));
        log.debug(@src(), "height: {d}", .{height});

        if (width == 0 or height == 0) {
            log.err(
                @src(),
                "Trygin to load a BMP, but the width or height is 0. Path: {s}",
                .{path},
            );
            return Texture.ID_DEBUG;
        }

        const bits_per_pixel_offset = height_offset + 4 + 2;
        const bits_per_pixel: u16 =
            @as(u16, @intCast(fm.mem[bits_per_pixel_offset + 1])) << 8 |
            @as(u16, @intCast(fm.mem[bits_per_pixel_offset + 0]));
        log.debug(@src(), "bits_per_pixel: {d}", .{bits_per_pixel});

        if (bits_per_pixel != 8) {
            log.err(
                @src(),
                "Trygin to load a BMP, but the bits_per_pixel is {} instead of 8. Path: {s}",
                .{ bits_per_pixel, path },
            );
            return Texture.ID_DEBUG;
        }

        const compression_offset = bits_per_pixel_offset + 2;
        const compression: u32 =
            @as(u32, @intCast(fm.mem[compression_offset + 3])) << 24 |
            @as(u32, @intCast(fm.mem[compression_offset + 2])) << 16 |
            @as(u32, @intCast(fm.mem[compression_offset + 1])) << 8 |
            @as(u32, @intCast(fm.mem[compression_offset + 0]));
        log.debug(@src(), "compression: {d}", .{compression});

        if (compression != 0) {
            log.err(@src(), "Trygin to load a BMP, but it is compressed. Path: {s}", .{path});
            return Texture.ID_DEBUG;
        }

        const colors_used_offset = compression_offset + 4 + 4 + 4 + 4;
        const colors_used: u32 =
            @as(u32, @intCast(fm.mem[colors_used_offset + 3])) << 24 |
            @as(u32, @intCast(fm.mem[colors_used_offset + 2])) << 16 |
            @as(u32, @intCast(fm.mem[colors_used_offset + 1])) << 8 |
            @as(u32, @intCast(fm.mem[colors_used_offset + 0]));
        log.debug(@src(), "colors_used: {d}", .{colors_used});

        const palette_offset = header_size + header_size_offset;

        const palette_id = self.paletts_num;
        self.paletts_num += 1;

        const palette_bytes = game_alloc.alignedAlloc(u8, 4, colors_used * 4) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a palette. Texture path: {s} error: {}",
                .{ path, e },
            );
            return Texture.ID_DEBUG;
        };
        self.paletts[palette_id].data = palette_bytes;

        const palette_colors = self.paletts[palette_id].as_color_slice();
        for (0..colors_used) |i| {
            const color: Color = .{
                .format = .{
                    .r = fm.mem[palette_offset + i * 4 + 2],
                    .g = fm.mem[palette_offset + i * 4 + 1],
                    .b = fm.mem[palette_offset + i * 4],
                    .a = 255,
                },
            };
            palette_colors[i] = color;
        }

        const texture_id = self.textures_num;
        self.textures_num += 1;

        const texture_bytes = game_alloc.alignedAlloc(u8, 4, width * height) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for a texture. Texture path: {s} error: {}",
                .{ path, e },
            );
            return Texture.ID_DEBUG;
        };
        self.textures[texture_id] = .{
            .width = width,
            .height = height,
            .channels = 1,
            .palette_id = palette_id,
            .data = texture_bytes,
        };
        @memcpy(self.textures[texture_id].data, fm.mem[bm_offset .. bm_offset + width * height]);

        log.info(
            @src(),
            "Loaded BMP texture from the path: {s} width: {} height: {} colors: {} texture_id: {} palette_id: {}",
            .{ path, width, height, colors_used, texture_id, palette_id },
        );

        return texture_id;
    }

    pub fn get_texture(self: Self, texture_id: Texture.Id) *const Texture {
        log.assert(
            @src(),
            texture_id < self.textures_num,
            "Trying to get texture outside the range: {} available, {} requested",
            .{ self.textures_num, texture_id },
        );
        return &self.textures[texture_id];
    }

    pub fn get_texture_mut(self: *Self, texture_id: Texture.Id) *Texture {
        log.assert(
            @src(),
            texture_id < self.textures_num,
            "Trying to get texture outside the range: {} available, {} requested",
            .{ self.textures_num, texture_id },
        );
        return &self.textures[texture_id];
    }

    pub fn get_palette(self: Self, palette_id: Palette.Id) *Palette {
        log.assert(
            @src(),
            palette_id < self.paletts_num,
            "Trying to get texture palette outside the range: {} available, {} requested",
            .{ self.textures_num, palette_id },
        );
        return &self.paletts[palette_id];
    }

    pub fn get_palette_mut(self: *Self, palette_id: Palette.Id) *const Palette {
        log.assert(
            @src(),
            palette_id < self.paletts_num,
            "Trying to get texture palette outside the range: {} available, {} requested",
            .{ self.textures_num, palette_id },
        );
        return &self.paletts[palette_id];
    }
};

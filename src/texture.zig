const std = @import("std");
const builtin = @import("builtin");
const log = @import("log.zig");
const stb = @import("bindings/stb.zig");

const Color = @import("color.zig").Color;
const Memory = @import("memory.zig");
const ScreenQuad = @import("screen_quads.zig").ScreenQuad;

pub const Id = u32;
pub const ID_DEBUG = 0;
pub const ID_VERT_COLOR = std.math.maxInt(u32);
pub const ID_SOLID_COLOR = std.math.maxInt(u32) - 1;

width: u32,
height: u32,
channels: u32,
data: []align(4) u8,

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

// This type assumes it will never be moved
pub const Store = struct {
    textures: []Self,
    textures_num: u32,

    pub const DEBUG_WIDTH = 16;
    pub const DEBUG_HEIGHT = 16;
    pub const DEBUG_CHANNELS = 4;

    pub const MAX_TEXTURES = 8;

    pub fn init(self: *Store, memory: *Memory) !void {
        const game_alloc = memory.game_alloc();

        self.textures = try game_alloc.alloc(Self, MAX_TEXTURES);
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

        self.textures[ID_DEBUG] = .{
            .width = DEBUG_WIDTH,
            .height = DEBUG_HEIGHT,
            .channels = DEBUG_CHANNELS,
            .data = data_u8,
        };
        self.textures_num = 1;
    }

    pub fn reserve(self: *Store) ?Id {
        if (self.textures_num != self.textures.len) {
            const id = self.textures_num;
            self.textures_num += 1;
            return id;
        } else {
            return null;
        }
    }

    pub fn load(self: *Store, memory: *Memory, path: [:0]const u8) Id {
        const game_alloc = memory.game_alloc();

        if (self.textures_num == self.textures.len) {
            log.err(
                @src(),
                "Trying to load more textures than capacity: MAX_TEXTURES: {}, path: {s}",
                .{ @as(u32, MAX_TEXTURES), path },
            );
            return ID_DEBUG;
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
                return ID_DEBUG;
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
            return ID_DEBUG;
        }
    }

    pub fn get(self: Store, texture_id: Id) *const Self {
        log.assert(
            @src(),
            texture_id < self.textures_num,
            "Trying to get texture outside the range: {} available, {} requested",
            .{ self.textures_num, texture_id },
        );
        return &self.textures[texture_id];
    }

    pub fn get_mut(self: *Store, texture_id: Id) *Self {
        log.assert(
            @src(),
            texture_id < self.textures_num,
            "Trying to get texture outside the range: {} available, {} requested",
            .{ self.textures_num, texture_id },
        );
        return &self.textures[texture_id];
    }
};

pub const FlipBook = struct {
    texture_id: Id,
    frames: u32,

    is_playing: bool = false,
    is_looping: bool = false,
    current_frame: u32 = 0,
    current_time: f32 = 0.0,
    seconds_per_frame: f32 = 0.0,

    pub fn init(texture_id: Id, frames: u32) FlipBook {
        log.assert(@src(), frames != 0, "Trying to create a FlipBook with 0 frames", .{});
        return .{
            .texture_id = texture_id,
            .frames = frames,
        };
    }

    pub fn start(self: *FlipBook, frames_per_second: f32, is_looping: bool) void {
        self.is_playing = true;
        self.is_looping = is_looping;
        self.seconds_per_frame = 1 / frames_per_second;
    }

    pub fn stop(self: *FlipBook) void {
        self.is_playing = false;
    }

    pub fn update(self: *FlipBook, texture_store: *const Store, screen_quad: *ScreenQuad, dt: f32) void {
        if (!self.is_playing) {
            return;
        }

        self.current_time += dt;
        if (self.seconds_per_frame < self.current_time) {
            self.current_frame += 1;
            self.current_time -= self.seconds_per_frame;
        }
        if (self.current_frame == self.frames - 1) {
            if (self.is_looping) {
                self.current_frame = 0;
            } else {
                self.stop();
                return;
            }
        }

        const texture = texture_store.get(self.texture_id);
        const frame_width = texture.width / self.frames;
        const frame_start = frame_width * self.current_frame;

        screen_quad.texture_id = self.texture_id;
        screen_quad.uv_offset = .{ .x = @floatFromInt(frame_start), .y = 0.0 };
        log.assert(@src(), 0 < frame_width, "Frame width must be not 0", .{});
        log.assert(@src(), 0 < texture.height, "Frame height must be not 0", .{});
        screen_quad.uv_size = .{
            .x = @floatFromInt(frame_width),
            .y = @floatFromInt(texture.height),
        };
    }
};

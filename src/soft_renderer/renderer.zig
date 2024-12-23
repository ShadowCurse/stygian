const sdl = @import("../bindings/sdl.zig");
const log = @import("../log.zig");

const Image = @import("../image.zig");

const _math = @import("../math.zig");
const Vec2 = _math.Vec2;

// Image rectangle with 0,0 at the top left
pub const ImageRect = struct {
    image: *const Image,
    position: Vec2,
    size: Vec2,

    pub fn to_aabb(self: ImageRect) AABB {
        return .{
            .min = .{
                .x = self.position.x,
                .y = self.position.y,
            },
            .max = .{
                .x = self.position.x + self.size.x,
                .y = self.position.y + self.size.y,
            },
        };
    }
};

pub const AABB = struct {
    min: Vec2,
    max: Vec2,

    pub fn is_empty(self: AABB) bool {
        return (self.max.x - self.min.x) == 0.0 and (self.max.y - self.min.y) == 0.0;
    }

    pub fn intersects(self: AABB, other: AABB) bool {
        return !(self.max.x < other.min.x or
            other.max.x < self.min.x or
            other.max.y < self.min.y or
            self.max.y < other.min.y);
    }

    pub fn intersection(self: AABB, other: AABB) AABB {
        return .{
            .min = .{
                .x = @max(self.min.x, other.min.x),
                .y = @max(self.min.y, other.min.y),
            },
            .max = .{
                .x = @min(self.max.x, other.max.x),
                .y = @min(self.max.y, other.max.y),
            },
        };
    }

    pub fn width(self: AABB) f32 {
        return self.max.x - self.min.x;
    }

    pub fn height(self: AABB) f32 {
        return self.max.y - self.min.y;
    }
};

window: *sdl.SDL_Window,
surface: *sdl.SDL_Surface,
image: Image,

const Self = @This();

pub fn init(
    window: *sdl.SDL_Window,
) Self {
    const surface = sdl.SDL_GetWindowSurface(window);
    var data: []u8 = undefined;
    data.ptr = @ptrCast(surface.*.pixels);
    data.len = @intCast(surface.*.w * surface.*.h * surface.*.format.*.BytesPerPixel);

    const image: Image = .{
        .width = @intCast(surface.*.w),
        .height = @intCast(surface.*.h),
        .channels = @intCast(surface.*.format.*.BytesPerPixel),
        .data = data,
    };

    return .{
        .window = window,
        .surface = surface,
        .image = image,
    };
}

pub fn start_rendering(self: *const Self) void {
    _ = sdl.SDL_FillRect(self.surface, 0, 0);
}

pub fn end_rendering(self: *const Self) void {
    _ = sdl.SDL_UpdateWindowSurface(self.window);
}

pub fn as_image_rect(self: *const Self) ImageRect {
    return .{
        .image = &self.image,
        .position = .{},
        .size = .{ .x = @floatFromInt(self.image.width), .y = @floatFromInt(self.image.height) },
    };
}

pub fn draw_image(self: *Self, position: Vec2, image_rect: ImageRect) void {
    const self_rect = self.as_image_rect();
    const self_aabb = self_rect.to_aabb();
    const dst_rect: ImageRect = .{
        .image = undefined,
        .position = position,
        .size = image_rect.size,
    };
    const dst_aabb = dst_rect.to_aabb();

    if (!self_aabb.intersects(dst_aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(dst_aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    const dst_pitch = self.image.width * self.image.channels;
    const src_pitch = image_rect.image.width * image_rect.image.channels;

    const dst_start_x: u32 = @intFromFloat(intersection.min.x);
    const dst_start_y: u32 = @intFromFloat(intersection.min.y);
    const src_start_x: u32 = @intFromFloat(image_rect.position.x);
    const src_start_y: u32 = @intFromFloat(image_rect.position.y);

    var dst_data_start = dst_start_x * self.image.channels + dst_start_y * dst_pitch;
    var dst_data_end = dst_data_start + width * self.image.channels;
    var src_data_start = src_start_x * image_rect.image.channels + src_start_y * src_pitch;
    var src_data_end = src_data_start + width * image_rect.image.channels;

    if (self.image.channels == image_rect.image.channels) {
        for (0..height) |_| {
            @memcpy(
                self.image.data[dst_data_start..dst_data_end],
                image_rect.image.data[src_data_start..src_data_end],
            );
            dst_data_start += dst_pitch;
            dst_data_end += dst_pitch;
            src_data_start += src_pitch;
            src_data_end += src_pitch;
        }
    } else if (self.image.channels == 4 and image_rect.image.channels == 1) {
        for (0..height) |_| {
            const dst = self.image.data[dst_data_start..dst_data_end];
            const src = image_rect.image.data[src_data_start..src_data_end];
            for (0..width) |x| {
                const byte = src[x];
                dst[x * 4] = byte;
                dst[x * 4 + 1] = byte;
                dst[x * 4 + 2] = byte;
                dst[x * 4 + 3] = 0xFF;
            }
            dst_data_start += dst_pitch;
            dst_data_end += dst_pitch;
            src_data_start += src_pitch;
            src_data_end += src_pitch;
        }
    } else {
        log.warn(
            @src(),
            "Skipping drawing image as channel numbers are incopatible: self: {}, image: {}",
            .{ self.image.channels, image_rect.image.channels },
        );
    }
}

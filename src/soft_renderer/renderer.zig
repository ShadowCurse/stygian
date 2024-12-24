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

pub fn draw_image_axis(
    self: *Self,
    position: Vec2,
    size: Vec2,
    rotation: f32,
    image_rect: ImageRect,
) void {
    const scale: Vec2 = .{
        .x = size.x / @as(f32, @floatFromInt(image_rect.image.width)),
        .y = size.y / @as(f32, @floatFromInt(image_rect.image.height)),
    };
    const c = @cos(rotation);
    const s = @sin(rotation);
    const x_axis = (Vec2{ .x = c, .y = s }).mul_f32(scale.x);
    const y_axis = (Vec2{ .x = s, .y = -c }).mul_f32(scale.x);

    const p_a = position.add(x_axis.mul_f32(-image_rect.size.x / 2.0))
        .add(y_axis.mul_f32(-image_rect.size.y / 2.0));
    const p_b = position.add(x_axis.mul_f32(image_rect.size.x / 2.0))
        .add(y_axis.mul_f32(-image_rect.size.y / 2.0));
    const p_c = position.add(x_axis.mul_f32(-image_rect.size.x / 2.0))
        .add(y_axis.mul_f32(image_rect.size.y / 2.0));
    const p_d = position.add(x_axis.mul_f32(image_rect.size.x / 2.0))
        .add(y_axis.mul_f32(image_rect.size.y / 2.0));

    const dst_aabb = AABB{
        .min = .{
            .x = @min(@min(p_a.x, p_b.x), @min(p_c.x, p_d.x)),
            .y = @min(@min(p_a.y, p_b.y), @min(p_c.y, p_d.y)),
        },
        .max = .{
            .x = @max(@max(p_a.x, p_b.x), @max(p_c.x, p_d.x)),
            .y = @max(@max(p_a.y, p_b.y), @max(p_c.y, p_d.y)),
        },
    };

    const self_rect = self.as_image_rect();
    const self_aabb = self_rect.to_aabb();

    if (!self_aabb.intersects(dst_aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(dst_aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    const dst_pitch = self.image.width * self.image.channels;
    const src_pitch = image_rect.image.width * image_rect.image.channels;

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));
    const src_start_x: u32 = @intFromFloat(@round(image_rect.position.x));
    const src_start_y: u32 = @intFromFloat(@round(image_rect.position.y));

    var dst_data_start = dst_start_x * self.image.channels + dst_start_y * dst_pitch;
    var dst_data_end = dst_data_start + width * self.image.channels;
    const src_data_start = src_start_x * image_rect.image.channels + src_start_y * src_pitch;

    const ab = p_b.sub(p_a);
    const bd = p_d.sub(p_b);
    const dc = p_c.sub(p_d);
    const ca = p_a.sub(p_c);

    for (0..height) |y| {
        for (0..width) |x| {
            const p: Vec2 = .{
                .x = intersection.min.x + @as(f32, @floatFromInt(x)),
                .y = intersection.min.y + @as(f32, @floatFromInt(y)),
            };
            const ap = p.sub(p_a);
            const bp = p.sub(p_b);
            const dp = p.sub(p_d);
            const cp = p.sub(p_c);

            const ab_test = ab.perp().dot(ap);
            const bd_test = bd.perp().dot(bp);
            const dc_test = dc.perp().dot(dp);
            const ca_test = ca.perp().dot(cp);

            if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis) / x_axis.len_squared()));
                var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis) / y_axis.len_squared()));
                u_i32 = @min(@max(0, u_i32), image_rect.image.width - 1);
                v_i32 = @min(@max(0, v_i32), image_rect.image.height - 1);

                const u: u32 = @intCast(u_i32);
                const v: u32 = @intCast(v_i32);

                const color_0 = image_rect.image.data[
                    src_data_start +
                        u * image_rect.image.channels +
                        v * src_pitch + 0
                ];
                const color_1 = image_rect.image.data[
                    src_data_start +
                        u * image_rect.image.channels +
                        v * src_pitch + 1
                ];
                const color_2 = image_rect.image.data[
                    src_data_start +
                        u * image_rect.image.channels +
                        v * src_pitch + 2
                ];
                const color_3 = image_rect.image.data[
                    src_data_start +
                        u * image_rect.image.channels +
                        v * src_pitch + 3
                ];
                self.image.data[dst_data_start + x * 4 + 0] = color_0;
                self.image.data[dst_data_start + x * 4 + 1] = color_1;
                self.image.data[dst_data_start + x * 4 + 2] = color_2;
                self.image.data[dst_data_start + x * 4 + 3] = color_3;
            } else {
                self.image.data[dst_data_start + x * 4 + 0] = 0xF0;
                self.image.data[dst_data_start + x * 4 + 1] = 0xF0;
                self.image.data[dst_data_start + x * 4 + 2] = 0x00;
                self.image.data[dst_data_start + x * 4 + 3] = 0xF0;
            }
        }
        dst_data_start += dst_pitch;
        dst_data_end += dst_pitch;
    }
}

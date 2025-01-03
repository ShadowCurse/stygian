const sdl = @import("../bindings/sdl.zig");
const log = @import("../log.zig");

const Perf = @import("../performance.zig");
const Texture = @import("../texture.zig");
const Color = @import("../color.zig").Color;

const _math = @import("../math.zig");
const Vec2 = _math.Vec2;

pub const perf = Perf.Measurements(struct {
    start_rendering: Perf.Fn,
    end_rendering: Perf.Fn,
    draw_line: Perf.Fn,
    draw_aabb: Perf.Fn,
    draw_texture: Perf.Fn,
    draw_texture_with_size_and_rotation: Perf.Fn,
    draw_color_rect: Perf.Fn,
    draw_color_rect_with_size_and_rotation: Perf.Fn,
});

// Texture rectangle with 0,0 at the top left
pub const TextureRect = struct {
    texture: *const Texture,
    position: Vec2,
    size: Vec2,

    pub fn to_aabb(self: TextureRect) AABB {
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
surface_texture: Texture,

const Self = @This();

pub fn init(
    window: *sdl.SDL_Window,
) Self {
    const surface = sdl.SDL_GetWindowSurface(window);
    log.info(
        @src(),
        "Surface has format: {s}({d} bytes), A mask: {x}, R mask: {x}, G mask: {x}, B mask: {x}",
        .{
            sdl.SDL_GetPixelFormatName(surface.*.format.*.format),
            surface.*.format.*.BytesPerPixel,
            surface.*.format.*.Amask,
            surface.*.format.*.Rmask,
            surface.*.format.*.Gmask,
            surface.*.format.*.Bmask,
        },
    );

    var data: []align(4) u8 = undefined;
    data.ptr = @alignCast(@ptrCast(surface.*.pixels));
    data.len = @intCast(surface.*.w * surface.*.h * surface.*.format.*.BytesPerPixel);

    const surface_texture: Texture = .{
        .width = @intCast(surface.*.w),
        .height = @intCast(surface.*.h),
        .channels = @intCast(surface.*.format.*.BytesPerPixel),
        .data = data,
    };

    return .{
        .window = window,
        .surface = surface,
        .surface_texture = surface_texture,
    };
}

pub fn start_rendering(self: *const Self) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);
    _ = sdl.SDL_FillRect(self.surface, 0, 0);
}

pub fn end_rendering(self: *const Self) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);
    _ = sdl.SDL_UpdateWindowSurface(self.window);
}

pub fn as_texture_rect(self: *const Self) TextureRect {
    return .{
        .texture = &self.surface_texture,
        .position = .{},
        .size = .{
            .x = @floatFromInt(self.surface_texture.width),
            .y = @floatFromInt(self.surface_texture.height),
        },
    };
}

pub fn draw_line(self: *Self, point_a: Vec2, point_b: Vec2, color: Color) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const steps = @max(@abs(point_a.x - point_b.x), @abs(point_a.y - point_b.y));
    const steps_u32: u32 = @intFromFloat(steps);

    const delta = point_b.sub(point_a).div_f32(steps);

    const dst_pitch = self.surface_texture.width;
    const dst_data_color = self.surface_texture.as_color_slice();

    const surface_width = @as(f32, @floatFromInt(self.surface_texture.width)) - 1;
    const surface_height = @as(f32, @floatFromInt(self.surface_texture.height)) - 1;

    for (0..steps_u32) |s| {
        const point = point_a.add(delta.mul_f32(@floatFromInt(s)));

        if (point.x < 0.0 or
            surface_width < point.x or
            point.y < 0.0 or
            surface_height < point.y)
        {
            continue;
        }

        const point_x: u32 = @intFromFloat(@floor(point.x));
        const point_y: u32 = @intFromFloat(@floor(point.y));
        dst_data_color[point_x + point_y * dst_pitch] = color;
    }
}

pub fn draw_aabb(self: *Self, aabb: AABB, color: Color) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const self_rect = self.as_texture_rect();
    const self_aabb = self_rect.to_aabb();

    if (!self_aabb.intersects(aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    if (height == 0 or width == 0) {
        return;
    }

    const draw_top = intersection.max.y <= aabb.max.y;
    const draw_bot = aabb.max.y <= intersection.max.y;
    const draw_left = intersection.min.x <= aabb.min.x;
    const draw_right = aabb.max.x <= intersection.max.x;

    const dst_pitch = self.surface_texture.width;
    const dst_start_x: u32 = @intFromFloat(intersection.min.x);
    const dst_start_y: u32 = @intFromFloat(intersection.min.y);
    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
    const dst_data_color = self.surface_texture.as_color_slice();

    if (draw_top)
        @memset(
            dst_data_color[dst_data_start .. dst_data_start + width],
            color,
        );
    if (draw_bot) {
        const dst_start = dst_data_start + (height - 1) * dst_pitch;
        @memset(
            dst_data_color[dst_start .. dst_start + width],
            color,
        );
    }

    for (0..height) |_| {
        if (draw_left)
            dst_data_color[dst_data_start] = color;
        if (draw_right)
            dst_data_color[dst_data_start + width - 1] = color;
        dst_data_start += dst_pitch;
    }
}

// TODO add an option to skip alpha blend and do a simple memcopy instead.
pub fn draw_texture(self: *Self, position: Vec2, texture_rect: TextureRect) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const self_rect = self.as_texture_rect();
    const self_aabb = self_rect.to_aabb();
    // Positon is the center of the destination
    const dst_rect: TextureRect = .{
        .texture = undefined,
        .position = position.sub(texture_rect.size.mul_f32(0.5)),
        .size = texture_rect.size,
    };
    const dst_aabb = dst_rect.to_aabb();

    if (!self_aabb.intersects(dst_aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(dst_aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    if (texture_rect.texture.channels == 4) {
        const dst_pitch = self.surface_texture.width;
        const src_pitch = texture_rect.texture.width;

        const dst_start_x: u32 = @intFromFloat(intersection.min.x);
        const dst_start_y: u32 = @intFromFloat(intersection.min.y);
        const src_start_x: u32 = @intFromFloat(texture_rect.position.x);
        const src_start_y: u32 = @intFromFloat(texture_rect.position.y);

        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
        var src_data_start = src_start_x + src_start_y * src_pitch;

        const dst_data_color = self.surface_texture.as_color_slice();
        const src_data_color = texture_rect.texture.as_color_slice();
        for (0..height) |_| {
            for (0..width) |x| {
                const src = src_data_color[src_data_start + x];
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = src.mix(dst.*);
            }
            dst_data_start += dst_pitch;
            src_data_start += src_pitch;
        }
    } else if (texture_rect.texture.channels == 1) {
        const dst_pitch = self.surface_texture.width;
        const src_pitch = texture_rect.texture.width * texture_rect.texture.channels;

        const dst_start_x: u32 = @intFromFloat(intersection.min.x);
        const dst_start_y: u32 = @intFromFloat(intersection.min.y);
        const src_start_x: u32 = @intFromFloat(texture_rect.position.x);
        const src_start_y: u32 = @intFromFloat(texture_rect.position.y);

        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
        var src_data_start = src_start_x * texture_rect.texture.channels + src_start_y * src_pitch;

        const dst_data_color = self.surface_texture.as_color_slice();
        const src_data_u8 = texture_rect.texture.data;
        for (0..height) |_| {
            for (0..width) |x| {
                const src_u8 = src_data_u8[src_data_start + x];
                const src: Color = .{ .format = .{ .r = src_u8, .g = src_u8, .b = src_u8, .a = src_u8 } };
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = src.mix(dst.*);
            }
            dst_data_start += dst_pitch;
            src_data_start += src_pitch;
        }
    } else {
        log.warn(
            @src(),
            "Skipping drawing texture as channel numbers are incopatible: self: {}, texture: {}",
            .{ self.surface_texture.channels, texture_rect.texture.channels },
        );
    }
}

// Draws a texture into a target rect with center at `position` with `size`.
pub fn draw_texture_with_size_and_rotation(
    self: *Self,
    position: Vec2,
    size: Vec2,
    rotation: f32,
    rotation_offset: Vec2,
    texture_rect: TextureRect,
) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const c = @cos(-rotation);
    const s = @sin(-rotation);
    const new_position = position.add(rotation_offset).add(
        Vec2{
            .x = c * -rotation_offset.x - s * -rotation_offset.y,
            .y = s * -rotation_offset.x + c * -rotation_offset.y,
        },
    );
    const x_axis = (Vec2{ .x = c, .y = s });
    const y_axis = (Vec2{ .x = s, .y = -c });

    const half_x = size.x / 2.0;
    const half_y = size.y / 2.0;
    const x_offset = x_axis.mul_f32(half_x);
    const y_offset = y_axis.mul_f32(half_y);
    const p_a = new_position.add(x_offset.neg()).add(y_offset.neg());
    const p_b = new_position.add(x_offset).add(y_offset.neg());
    const p_c = new_position.add(x_offset.neg()).add(y_offset);
    const p_d = new_position.add(x_offset).add(y_offset);

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

    const self_rect = self.as_texture_rect();
    const self_aabb = self_rect.to_aabb();

    if (!self_aabb.intersects(dst_aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(dst_aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    if (height == 0 or width == 0) {
        return;
    }

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));
    const src_start_x: u32 = @intFromFloat(@round(texture_rect.position.x));
    const src_start_y: u32 = @intFromFloat(@round(texture_rect.position.y));

    const ab = p_b.sub(p_a);
    const bd = p_d.sub(p_b);
    const dc = p_c.sub(p_d);
    const ca = p_a.sub(p_c);

    const scale: Vec2 = texture_rect.size.div(size);
    const texture_width: i32 = @intFromFloat(@floor(texture_rect.size.x));
    const texture_height: i32 = @intFromFloat(@floor(texture_rect.size.y));

    const dst_pitch = self.surface_texture.width;
    const src_pitch = texture_rect.texture.width;
    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
    const src_data_start = src_start_x + src_start_y * src_pitch;

    if (texture_rect.texture.channels == 4) {
        const dst_data_u32 = self.surface_texture.as_color_slice();
        const src_data_u32 = texture_rect.texture.as_color_slice();

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
                    var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis)) * scale.x);
                    var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis)) * scale.y);
                    u_i32 = @min(@max(0, u_i32), texture_width - 1);
                    v_i32 = @min(@max(0, v_i32), texture_height - 1);

                    const u: u32 = @intCast(u_i32);
                    const v: u32 = @as(u32, @intCast(texture_height - 1)) -
                        @as(u32, @intCast(v_i32));

                    const src = src_data_u32[
                        src_data_start +
                            u +
                            v * src_pitch
                    ];
                    const dst = &dst_data_u32[dst_data_start + x];
                    dst.* = src.mix(dst.*);
                }
            }
            dst_data_start += dst_pitch;
        }
    } else if (texture_rect.texture.channels == 1) {
        const dst_data_color = self.surface_texture.as_color_slice();
        const src_data_u8 = texture_rect.texture.data;

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
                    var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis)) * scale.x);
                    var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis)) * scale.y);
                    u_i32 = @min(@max(0, u_i32), texture_width - 1);
                    v_i32 = @min(@max(0, v_i32), texture_height - 1);

                    const u: u32 = @intCast(u_i32);
                    const v: u32 = @as(u32, @intCast(texture_height - 1)) -
                        @as(u32, @intCast(v_i32));

                    const src_u8 = src_data_u8[
                        src_data_start +
                            u +
                            v * src_pitch
                    ];
                    const src: Color = .{ .format = .{ .r = src_u8, .g = src_u8, .b = src_u8, .a = src_u8 } };
                    const dst = &dst_data_color[dst_data_start + x];
                    dst.* = src.mix(dst.*);
                }
            }
            dst_data_start += dst_pitch;
        }
    } else {
        log.warn(
            @src(),
            "Skipping drawing texture as channel numbers are incopatible: self: {}, texture: {}",
            .{ self.surface_texture.channels, texture_rect.texture.channels },
        );
    }
}

pub fn draw_color_rect(
    self: *Self,
    position: Vec2,
    size: Vec2,
    color: Color,
) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const x_axis = Vec2.X.mul_f32(size.x / 2.0);
    const y_axis = Vec2.NEG_Y.mul_f32(size.y / 2.0);

    const p_a = position.add(x_axis.neg()).add(y_axis.neg());
    const p_b = position.add(x_axis).add(y_axis.neg());
    const p_c = position.add(x_axis.neg()).add(y_axis);
    const p_d = position.add(x_axis).add(y_axis);

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

    const self_rect = self.as_texture_rect();
    const self_aabb = self_rect.to_aabb();

    if (!self_aabb.intersects(dst_aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(dst_aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    if (height == 0 or width == 0) {
        return;
    }

    const dst_pitch = self.surface_texture.width;

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));

    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;

    const dst_data_color = self.surface_texture.as_color_slice();
    for (0..height) |_| {
        for (0..width) |x| {
            const dst = &dst_data_color[dst_data_start + x];
            dst.* = color.mix(dst.*);
        }
        dst_data_start += dst_pitch;
    }
}

pub fn draw_color_rect_with_size_and_rotation(
    self: *Self,
    position: Vec2,
    size: Vec2,
    rotation: f32,
    rotation_offset: Vec2,
    color: Color,
) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const c = @cos(-rotation);
    const s = @sin(-rotation);
    const new_position = position.add(rotation_offset).add(
        Vec2{
            .x = c * -rotation_offset.x - s * -rotation_offset.y,
            .y = s * -rotation_offset.x + c * -rotation_offset.y,
        },
    );
    const x_axis = (Vec2{ .x = c, .y = s }).mul_f32(size.x / 2.0);
    const y_axis = (Vec2{ .x = s, .y = -c }).mul_f32(size.y / 2.0);

    const p_a = new_position.add(x_axis.neg()).add(y_axis.neg());
    const p_b = new_position.add(x_axis).add(y_axis.neg());
    const p_c = new_position.add(x_axis.neg()).add(y_axis);
    const p_d = new_position.add(x_axis).add(y_axis);

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

    const self_rect = self.as_texture_rect();
    const self_aabb = self_rect.to_aabb();

    if (!self_aabb.intersects(dst_aabb)) {
        return;
    }

    const intersection = self_aabb.intersection(dst_aabb);
    const width: u32 = @intFromFloat(intersection.width());
    const height: u32 = @intFromFloat(intersection.height());

    if (height == 0 or width == 0) {
        return;
    }

    const dst_pitch = self.surface_texture.width;

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));

    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;

    const ab = p_b.sub(p_a);
    const bd = p_d.sub(p_b);
    const dc = p_c.sub(p_d);
    const ca = p_a.sub(p_c);

    const dst_data_color = self.surface_texture.as_color_slice();
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
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = color.mix(dst.*);
            }
        }
        dst_data_start += dst_pitch;
    }
}

const buildin = @import("builtin");
const sdl = @import("../bindings/sdl.zig");
const log = @import("../log.zig");

const platform = @import("../platform/root.zig");
const Window = platform.Window;

const Tracing = @import("../tracing.zig");
const Textures = @import("../textures.zig");
const Color = @import("../color.zig").Color;
const Memory = @import("../memory.zig");

const _math = @import("../math.zig");
const Vec2 = _math.Vec2;

pub const trace = Tracing.Measurements(struct {
    start_rendering: Tracing.Counter,
    end_rendering: Tracing.Counter,
    draw_line: Tracing.Counter,
    draw_aabb: Tracing.Counter,
    draw_texture: Tracing.Counter,
    draw_texture_with_size_and_rotation: Tracing.Counter,
    draw_color_rect: Tracing.Counter,
    draw_color_rect_with_size_and_rotation: Tracing.Counter,
});

// Texture rectangle with 0,0 at the top left
pub const TextureRect = struct {
    texture: *const Textures.Texture,
    palette: ?*const Textures.Palette,
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

sdl_renderer: *sdl.SDL_Renderer,
sdl_texture: *sdl.SDL_Texture,
surface_texture: Textures.Texture,

const Self = @This();

pub fn init(
    memory: *Memory,
    window: *Window,
) Self {
    const game_alloc = memory.game_alloc();

    const sdl_renderer = sdl.SDL_CreateRenderer(window.sdl_window, null);
    const texture_data = game_alloc.alignedAlloc(u8, 4, window.width * window.height * 4) catch {
        @panic("Cannot allocate memory for software renderer surface texture");
    };

    const surface_texture: Textures.Texture = .{
        .width = window.width,
        .height = window.height,
        .channels = 4,
        .data = texture_data,
    };

    const format = if (buildin.os.tag == .emscripten)
        // sdl.SDL_PIXELFORMAT_BGR888
        374740996
    else
        // sdl.SDL_PIXELFORMAT_RGB888
        370546692;

    const sdl_texture = sdl.SDL_CreateTexture(
        sdl_renderer.?,
        format,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        @intCast(window.width),
        @intCast(window.height),
    );

    return .{
        .sdl_renderer = sdl_renderer.?,
        .sdl_texture = sdl_texture.?,
        .surface_texture = surface_texture,
    };
}

pub fn start_rendering(self: *const Self) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    @memset(self.surface_texture.data, 0);
}

pub fn end_rendering(self: *const Self) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    _ = sdl.SDL_UpdateTexture(
        self.sdl_texture,
        null,
        self.surface_texture.data.ptr,
        @intCast(self.surface_texture.width * self.surface_texture.channels),
    );
    _ = sdl.SDL_RenderTexture(self.sdl_renderer, self.sdl_texture, null, null);
    _ = sdl.SDL_RenderPresent(self.sdl_renderer);
}

pub fn as_texture_rect(self: *const Self) TextureRect {
    return .{
        .texture = &self.surface_texture,
        .palette = null,
        .position = .{},
        .size = .{
            .x = @floatFromInt(self.surface_texture.width),
            .y = @floatFromInt(self.surface_texture.height),
        },
    };
}

pub fn draw_line(self: *Self, point_a: Vec2, point_b: Vec2, color: Color) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

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
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

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

pub fn draw_texture(
    self: *Self,
    position: Vec2,
    texture_rect: TextureRect,
    tint: ?Color,
    no_alpha_blend: bool,
    draw_aabb_outline: bool,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);
    if (texture_rect.texture.channels == 4) {
        if (tint) |t| {
            const SrcData = struct {
                color: []const Color,
                tint: Color,
                pub fn get_src(this: @This(), offset: u32) Color {
                    return this.tint.mix(this.color[offset], .dst);
                }
            };
            const src_data: SrcData = .{
                .color = texture_rect.texture.as_color_slice(),
                .tint = t,
            };
            self.draw_texture_inner(
                position,
                texture_rect,
                no_alpha_blend,
                draw_aabb_outline,
                src_data,
            );
        } else {
            const SrcData = struct {
                color: []const Color,
                pub fn get_src(this: @This(), offset: u32) Color {
                    return this.color[offset];
                }
            };
            const src_data: SrcData = .{
                .color = texture_rect.texture.as_color_slice(),
            };
            self.draw_texture_inner(
                position,
                texture_rect,
                no_alpha_blend,
                draw_aabb_outline,
                src_data,
            );
        }
    } else if (texture_rect.texture.channels == 1) {
        if (tint) |t| {
            const SrcData = struct {
                bytes: []const u8,
                tint: Color,
                pub fn get_src(this: @This(), offset: u32) Color {
                    const b = this.bytes[offset];
                    return this.tint.mix(
                        .{ .format = .{ .r = b, .g = b, .b = b, .a = b } },
                        .dst,
                    );
                }
            };
            const src_data: SrcData = .{
                .bytes = texture_rect.texture.data,
                .tint = t,
            };
            self.draw_texture_inner(
                position,
                texture_rect,
                no_alpha_blend,
                draw_aabb_outline,
                src_data,
            );
        } else {
            const SrcData = struct {
                bytes: []const u8,
                pub fn get_src(this: @This(), offset: u32) Color {
                    const b = this.bytes[offset];
                    return .{ .format = .{ .r = b, .g = b, .b = b, .a = b } };
                }
            };
            const src_data: SrcData = .{
                .bytes = texture_rect.texture.data,
            };
            self.draw_texture_inner(
                position,
                texture_rect,
                no_alpha_blend,
                draw_aabb_outline,
                src_data,
            );
        }
    } else {
        log.warn(
            @src(),
            "Skipping drawing texture as channel numbers are incopatible: self: {}, texture: {}",
            .{ self.surface_texture.channels, texture_rect.texture.channels },
        );
    }
}

fn draw_texture_inner(
    self: *Self,
    position: Vec2,
    texture_rect: TextureRect,
    no_alpha_blend: bool,
    draw_aabb_outline: bool,
    src_data: anytype,
) void {
    const self_rect = self.as_texture_rect();
    const self_aabb = self_rect.to_aabb();
    // Positon is the center of the destination
    const dst_rect: TextureRect = .{
        .texture = undefined,
        .palette = null,
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

    if (height == 0 or width == 0) {
        return;
    }

    if (draw_aabb_outline)
        self.draw_aabb(intersection, Color.RED);

    const dst_pitch = self.surface_texture.width;
    const src_pitch = texture_rect.texture.width;

    const dst_start_x: u32 = @intFromFloat(intersection.min.x);
    const dst_start_y: u32 = @intFromFloat(intersection.min.y);
    const src_start_x: u32 =
        @intFromFloat(texture_rect.position.x + intersection.min.x - dst_aabb.min.x);
    const src_start_y: u32 =
        @intFromFloat(texture_rect.position.y + intersection.min.y - dst_aabb.min.y);

    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
    var src_data_start = src_start_x + src_start_y * src_pitch;

    const dst_data_color = self.surface_texture.as_color_slice();
    if (no_alpha_blend) {
        for (0..height) |_| {
            for (0..width) |x| {
                const src = src_data.get_src(src_data_start + @as(u32, @intCast(x)));
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = src;
            }
            dst_data_start += dst_pitch;
            src_data_start += src_pitch;
        }
    } else {
        for (0..height) |_| {
            for (0..width) |x| {
                const src = src_data.get_src(src_data_start + @as(u32, @intCast(x)));
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = src.mix(dst.*, .dst);
            }
            dst_data_start += dst_pitch;
            src_data_start += src_pitch;
        }
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
    tint: ?Color,
    no_alpha_blend: bool,
    draw_aabb_outline: bool,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    if (texture_rect.texture.channels == 4) {
        if (tint) |t| {
            const SrcData = struct {
                color: []const Color,
                tint: Color,
                pub fn get_src(this: @This(), offset: u32) Color {
                    return this.tint.mix(this.color[offset], .dst);
                }
            };
            const src_data: SrcData = .{
                .color = texture_rect.texture.as_color_slice(),
                .tint = t,
            };
            self.draw_texture_with_size_and_rotation_inner(
                position,
                size,
                rotation,
                rotation_offset,
                texture_rect,
                no_alpha_blend,
                draw_aabb_outline,
                src_data,
            );
        } else {
            const SrcData = struct {
                color: []const Color,
                pub fn get_src(this: @This(), offset: u32) Color {
                    return this.color[offset];
                }
            };
            const src_data: SrcData = .{
                .color = texture_rect.texture.as_color_slice(),
            };
            self.draw_texture_with_size_and_rotation_inner(
                position,
                size,
                rotation,
                rotation_offset,
                texture_rect,
                no_alpha_blend,
                draw_aabb_outline,
                src_data,
            );
        }
    } else if (texture_rect.texture.channels == 1) {
        if (texture_rect.palette) |palette| {
            if (tint) |t| {
                const SrcData = struct {
                    bytes: []const u8,
                    palette: []const Color,
                    tint: Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const index = this.bytes[offset];
                        return this.tint.mix(this.palette[index], .dst);
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                    .palette = palette.as_color_slice(),
                    .tint = t,
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            } else {
                const SrcData = struct {
                    bytes: []const u8,
                    palette: []const Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const index = this.bytes[offset];
                        return this.palette[index];
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                    .palette = palette.as_color_slice(),
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            }
        } else {
            if (tint) |t| {
                const SrcData = struct {
                    bytes: []const u8,
                    tint: Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const b = this.bytes[offset];
                        return this.tint.mix(
                            .{ .format = .{ .r = b, .g = b, .b = b, .a = b } },
                            .dst,
                        );
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                    .tint = t,
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            } else {
                const SrcData = struct {
                    bytes: []const u8,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const b = this.bytes[offset];
                        return .{ .format = .{ .r = b, .g = b, .b = b, .a = b } };
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            }
        }
    } else {
        log.warn(
            @src(),
            "Skipping drawing texture as channel numbers are incopatible: self: {}, texture: {}",
            .{ self.surface_texture.channels, texture_rect.texture.channels },
        );
    }
}

fn draw_texture_with_size_and_rotation_inner(
    self: *Self,
    position: Vec2,
    size: Vec2,
    rotation: f32,
    rotation_offset: Vec2,
    texture_rect: TextureRect,
    no_alpha_blend: bool,
    draw_aabb_outline: bool,
    src_data: anytype,
) void {
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

    if (draw_aabb_outline)
        self.draw_aabb(intersection, Color.RED);

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));
    const src_start_x: u32 = @intFromFloat(@round(texture_rect.position.x));
    const src_start_y: u32 = @intFromFloat(@round(texture_rect.position.y));

    const ab = p_b.sub(p_a).perp();
    const bd = p_d.sub(p_b).perp();
    const dc = p_c.sub(p_d).perp();
    const ca = p_a.sub(p_c).perp();

    const scale: Vec2 = texture_rect.size.div(size);
    const texture_width: i32 = @intFromFloat(@floor(texture_rect.size.x));
    const texture_height: i32 = @intFromFloat(@floor(texture_rect.size.y));

    const dst_pitch = self.surface_texture.width;
    const src_pitch = texture_rect.texture.width;
    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
    const src_data_start = src_start_x + src_start_y * src_pitch;

    const dst_data_u32 = self.surface_texture.as_color_slice();

    if (no_alpha_blend) {
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

                const ab_test = ab.dot(ap);
                const bd_test = bd.dot(bp);
                const dc_test = dc.dot(dp);
                const ca_test = ca.dot(cp);

                if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                    var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis)) * scale.x);
                    var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis)) * scale.y);
                    u_i32 = @min(@max(0, u_i32), texture_width - 1);
                    v_i32 = @min(@max(0, v_i32), texture_height - 1);

                    const u: u32 = @intCast(u_i32);
                    const v: u32 = @as(u32, @intCast(texture_height - 1)) -
                        @as(u32, @intCast(v_i32));

                    const src = src_data.get_src(src_data_start +
                        u +
                        v * src_pitch);
                    const dst = &dst_data_u32[dst_data_start + x];
                    dst.* = src;
                }
            }
            dst_data_start += dst_pitch;
        }
    } else {
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

                const ab_test = ab.dot(ap);
                const bd_test = bd.dot(bp);
                const dc_test = dc.dot(dp);
                const ca_test = ca.dot(cp);

                if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                    var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis)) * scale.x);
                    var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis)) * scale.y);
                    u_i32 = @min(@max(0, u_i32), texture_width - 1);
                    v_i32 = @min(@max(0, v_i32), texture_height - 1);

                    const u: u32 = @intCast(u_i32);
                    const v: u32 = @as(u32, @intCast(texture_height - 1)) -
                        @as(u32, @intCast(v_i32));

                    const src = src_data.get_src(src_data_start +
                        u +
                        v * src_pitch);
                    const dst = &dst_data_u32[dst_data_start + x];
                    dst.* = src.mix(dst.*, .dst);
                }
            }
            dst_data_start += dst_pitch;
        }
    }
}

pub fn draw_color_rect(
    self: *Self,
    position: Vec2,
    size: Vec2,
    color: Color,
    no_alpha_blend: bool,
    draw_aabb_outline: bool,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

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

    if (draw_aabb_outline)
        self.draw_aabb(intersection, Color.RED);

    const dst_pitch = self.surface_texture.width;

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));

    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;

    const dst_data_color = self.surface_texture.as_color_slice();
    if (color.format.a == 255 or no_alpha_blend) {
        for (0..height) |_| {
            const data_slice = dst_data_color[dst_data_start .. dst_data_start + width];
            @memset(data_slice, color);
            dst_data_start += dst_pitch;
        }
    } else {
        for (0..height) |_| {
            for (0..width) |x| {
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = color.mix(dst.*, .dst);
            }
            dst_data_start += dst_pitch;
        }
    }
}

pub fn draw_color_rect_with_size_and_rotation(
    self: *Self,
    position: Vec2,
    size: Vec2,
    rotation: f32,
    rotation_offset: Vec2,
    color: Color,
    no_alpha_blend: bool,
    draw_aabb_outline: bool,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    if (color.format.a == 255 or no_alpha_blend) {
        const SrcData = struct {
            color: Color,
            pub fn get_src(this: @This(), dst: Color) Color {
                _ = dst;
                return this.color;
            }
        };
        const src_data: SrcData = .{
            .color = color,
        };
        self.draw_color_rect_with_size_and_rotation_inner(
            position,
            size,
            rotation,
            rotation_offset,
            draw_aabb_outline,
            src_data,
        );
    } else {
        const SrcData = struct {
            color: Color,
            pub fn get_src(this: @This(), dst: Color) Color {
                return this.color.mix(dst, .dst);
            }
        };
        const src_data: SrcData = .{
            .color = color,
        };
        self.draw_color_rect_with_size_and_rotation_inner(
            position,
            size,
            rotation,
            rotation_offset,
            draw_aabb_outline,
            src_data,
        );
    }
}

fn draw_color_rect_with_size_and_rotation_inner(
    self: *Self,
    position: Vec2,
    size: Vec2,
    rotation: f32,
    rotation_offset: Vec2,
    draw_aabb_outline: bool,
    src_data: anytype,
) void {
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

    if (draw_aabb_outline)
        self.draw_aabb(intersection, Color.RED);

    const dst_pitch = self.surface_texture.width;

    const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
    const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));

    var dst_data_start = dst_start_x + dst_start_y * dst_pitch;

    const ab = p_b.sub(p_a).perp();
    const bd = p_d.sub(p_b).perp();
    const dc = p_c.sub(p_d).perp();
    const ca = p_a.sub(p_c).perp();

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

            const ab_test = ab.dot(ap);
            const bd_test = bd.dot(bp);
            const dc_test = dc.dot(dp);
            const ca_test = ca.dot(cp);

            if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                const dst = &dst_data_color[dst_data_start + x];
                dst.* = src_data.get_src(dst.*);
            }
        }
        dst_data_start += dst_pitch;
    }
}

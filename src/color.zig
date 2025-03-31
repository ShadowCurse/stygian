const std = @import("std");
const builtin = @import("builtin");

const _math = @import("math.zig");
const Vec3 = _math.Vec3;
const Vec4 = _math.Vec4;

pub const ColorU32 = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    const Self = @This();

    pub const NONE = Self{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const BLACK = Self{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const WHITE = Self{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const RED = Self{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const GREEN = Self{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const GREY = Self{ .r = 69, .g = 69, .b = 69, .a = 255 };
    pub const MAGENTA = Self{ .r = 255, .g = 0, .b = 255, .a = 255 };
    pub const ORANGE = Self{ .r = 237, .g = 91, .b = 18, .a = 255 };
    pub const BLUE = Self{ .r = 0, .g = 0, .b = 255, .a = 255 };

    pub fn init(r: u8, g: u8, b: u8, a: u8) Self {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn from_vec4_unchecked(vec4: Vec4) Self {
        return .{
            .r = @intFromFloat(vec4.x),
            .g = @intFromFloat(vec4.y),
            .b = @intFromFloat(vec4.z),
            .a = @intFromFloat(vec4.w),
        };
    }

    pub fn from_vec4(vec4: Vec4) Self {
        return .{
            .r = @intFromFloat(std.math.clamp(vec4.x, 0.0, 255.0)),
            .g = @intFromFloat(std.math.clamp(vec4.y, 0.0, 255.0)),
            .b = @intFromFloat(std.math.clamp(vec4.z, 0.0, 255.0)),
            .a = @intFromFloat(std.math.clamp(vec4.w, 0.0, 255.0)),
        };
    }

    pub fn from_vec4_norm(vec4: Vec4) Self {
        return .{
            .r = @intFromFloat(std.math.clamp(vec4.x * 255.0, 0.0, 255.0)),
            .g = @intFromFloat(std.math.clamp(vec4.y * 255.0, 0.0, 255.0)),
            .b = @intFromFloat(std.math.clamp(vec4.z * 255.0, 0.0, 255.0)),
            .a = @intFromFloat(std.math.clamp(vec4.w * 255.0, 0.0, 255.0)),
        };
    }

    pub fn to_vec3(self: *const Self) Vec3 {
        return .{
            .x = @as(f32, @floatFromInt(self.r)),
            .y = @as(f32, @floatFromInt(self.g)),
            .z = @as(f32, @floatFromInt(self.b)),
        };
    }

    pub fn to_vec4(self: *const Self) Vec4 {
        return .{
            .x = @as(f32, @floatFromInt(self.r)),
            .y = @as(f32, @floatFromInt(self.g)),
            .z = @as(f32, @floatFromInt(self.b)),
            .w = @as(f32, @floatFromInt(self.a)),
        };
    }

    pub fn to_vec4_norm(self: *const Self) Vec4 {
        return .{
            .x = @as(f32, @floatFromInt(self.r)) / 255.0,
            .y = @as(f32, @floatFromInt(self.g)) / 255.0,
            .z = @as(f32, @floatFromInt(self.b)) / 255.0,
            .w = @as(f32, @floatFromInt(self.a)) / 255.0,
        };
    }

    pub fn swap_rgba_bgra(self: Self) Self {
        return .{ .r = self.b, .g = self.g, .b = self.r, .a = self.a };
    }

    // Mix colors based on the alpha channel. Assumes the RGBA.
    pub fn mix(
        src: Self,
        dst: Self,
        comptime returned_alpha: enum {
            src,
            dst,
            mul,
        },
    ) Self {
        const src_a_f32 = @as(f32, @floatFromInt(src.a)) / 255.0;
        const c1 = src_a_f32;
        const c2 = 1.0 - src_a_f32;

        const s_r: f32 = @floatFromInt(src.r);
        const s_g: f32 = @floatFromInt(src.g);
        const s_b: f32 = @floatFromInt(src.b);

        const d_r: f32 = @floatFromInt(dst.r);
        const d_g: f32 = @floatFromInt(dst.g);
        const d_b: f32 = @floatFromInt(dst.b);

        const r = s_r * c1 + d_r * c2;
        const g = s_g * c1 + d_g * c2;
        const b = s_b * c1 + d_b * c2;

        const r_u8 = @as(u8, @intFromFloat(r));
        const g_u8 = @as(u8, @intFromFloat(g));
        const b_u8 = @as(u8, @intFromFloat(b));

        switch (returned_alpha) {
            .src => {
                return .{
                    .r = r_u8,
                    .g = g_u8,
                    .b = b_u8,
                    .a = src.a,
                };
            },
            .dst => {
                return .{
                    .r = r_u8,
                    .g = g_u8,
                    .b = b_u8,
                    .a = dst.a,
                };
            },
            .mul => {
                const dst_a_f32 = @as(f32, @floatFromInt(dst.a)) / 255.0;
                const mul_alpha: u8 = @intFromFloat(src_a_f32 * dst_a_f32 * 255.0);
                return .{
                    .r = r_u8,
                    .g = g_u8,
                    .b = b_u8,
                    .a = mul_alpha,
                };
            },
        }
    }
};

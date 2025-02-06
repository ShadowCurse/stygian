const std = @import("std");
const builtin = @import("builtin");

const _math = @import("math.zig");
const Vec3 = _math.Vec3;
const Vec4 = _math.Vec4;

// On web the surface format is ABGR
pub const Format = if (builtin.os.tag == .emscripten)
    extern struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 0,
    }
else
    // On descktop it is ARGB
    extern struct {
        b: u8 = 0,
        g: u8 = 0,
        r: u8 = 0,
        a: u8 = 0,
    };

pub const Color = extern struct {
    format: Format = .{},

    const Self = @This();

    pub const NONE = Self{ .format = .{ .r = 0, .g = 0, .b = 0, .a = 0 } };
    pub const BLACK = Self{ .format = .{ .r = 0, .g = 0, .b = 0, .a = 255 } };
    pub const WHITE = Self{ .format = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    pub const RED = Self{ .format = .{ .r = 255, .g = 0, .b = 0, .a = 255 } };
    pub const GREEN = Self{ .format = .{ .r = 0, .g = 255, .b = 0, .a = 255 } };
    pub const GREY = Self{ .format = .{ .r = 69, .g = 69, .b = 69, .a = 255 } };
    pub const MAGENTA = Self{ .format = .{ .r = 255, .g = 0, .b = 255, .a = 255 } };
    pub const ORANGE = Self{ .format = .{ .r = 237, .g = 91, .b = 18, .a = 255 } };
    pub const BLUE = Self{ .format = .{ .r = 0, .g = 0, .b = 255, .a = 255 } };

    pub fn from_parts(r: u8, g: u8, b: u8, a: u8) Self {
        return .{
            .format = .{
                .r = r,
                .g = g,
                .b = b,
                .a = a,
            },
        };
    }

    pub fn from_vec4_unchecked(vec4: Vec4) Self {
        return .{
            .format = .{
                .r = @intFromFloat(vec4.x),
                .g = @intFromFloat(vec4.y),
                .b = @intFromFloat(vec4.z),
                .a = @intFromFloat(vec4.w),
            },
        };
    }

    pub fn from_vec4(vec4: Vec4) Self {
        return .{
            .format = .{
                .r = @intFromFloat(std.math.clamp(vec4.x, 0.0, 255.0)),
                .g = @intFromFloat(std.math.clamp(vec4.y, 0.0, 255.0)),
                .b = @intFromFloat(std.math.clamp(vec4.z, 0.0, 255.0)),
                .a = @intFromFloat(std.math.clamp(vec4.w, 0.0, 255.0)),
            },
        };
    }

    pub fn from_vec4_norm(vec4: Vec4) Self {
        return .{
            .format = .{
                .r = @intFromFloat(std.math.clamp(vec4.x * 255.0, 0.0, 255.0)),
                .g = @intFromFloat(std.math.clamp(vec4.y * 255.0, 0.0, 255.0)),
                .b = @intFromFloat(std.math.clamp(vec4.z * 255.0, 0.0, 255.0)),
                .a = @intFromFloat(std.math.clamp(vec4.w * 255.0, 0.0, 255.0)),
            },
        };
    }

    pub fn to_vec3(self: *const Self) Vec3 {
        return .{
            .x = @as(f32, @floatFromInt(self.format.r)),
            .y = @as(f32, @floatFromInt(self.format.g)),
            .z = @as(f32, @floatFromInt(self.format.b)),
        };
    }

    pub fn to_vec4(self: *const Self) Vec4 {
        return .{
            .x = @as(f32, @floatFromInt(self.format.r)),
            .y = @as(f32, @floatFromInt(self.format.g)),
            .z = @as(f32, @floatFromInt(self.format.b)),
            .w = @as(f32, @floatFromInt(self.format.a)),
        };
    }

    pub fn to_vec4_norm(self: *const Self) Vec4 {
        return .{
            .x = @as(f32, @floatFromInt(self.format.r)) / 255.0,
            .y = @as(f32, @floatFromInt(self.format.g)) / 255.0,
            .z = @as(f32, @floatFromInt(self.format.b)) / 255.0,
            .w = @as(f32, @floatFromInt(self.format.a)) / 255.0,
        };
    }

    pub fn abgr_to_argb(self: *Self) void {
        std.mem.swap(u8, &self.format.r, &self.format.b);
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
        const src_a_f32 = @as(f32, @floatFromInt(src.format.a)) / 255.0;
        const c1 = src_a_f32;
        const c2 = 1.0 - src_a_f32;

        const s_r: f32 = @floatFromInt(src.format.r);
        const s_g: f32 = @floatFromInt(src.format.g);
        const s_b: f32 = @floatFromInt(src.format.b);

        const d_r: f32 = @floatFromInt(dst.format.r);
        const d_g: f32 = @floatFromInt(dst.format.g);
        const d_b: f32 = @floatFromInt(dst.format.b);

        const r = s_r * c1 + d_r * c2;
        const g = s_g * c1 + d_g * c2;
        const b = s_b * c1 + d_b * c2;

        const r_u8 = @as(u8, @intFromFloat(r));
        const g_u8 = @as(u8, @intFromFloat(g));
        const b_u8 = @as(u8, @intFromFloat(b));

        switch (returned_alpha) {
            .src => {
                return .{
                    .format = .{
                        .r = r_u8,
                        .g = g_u8,
                        .b = b_u8,
                        .a = src.format.a,
                    },
                };
            },
            .dst => {
                return .{
                    .format = .{
                        .r = r_u8,
                        .g = g_u8,
                        .b = b_u8,
                        .a = dst.format.a,
                    },
                };
            },
            .mul => {
                const dst_a_f32 = @as(f32, @floatFromInt(dst.format.a)) / 255.0;
                const mul_alpha: u8 = @intFromFloat(src_a_f32 * dst_a_f32 * 255.0);
                return .{
                    .format = .{
                        .r = r_u8,
                        .g = g_u8,
                        .b = b_u8,
                        .a = mul_alpha,
                    },
                };
            },
        }
    }
};

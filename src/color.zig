const _math = @import("math.zig");
const Vec3 = _math.Vec3;

// TODO figure out what to do with different color
// schemes.
pub const Color = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    const Self = @This();

    pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const WHITE = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const GREY = Color{ .r = 69, .g = 69, .b = 69, .a = 255 };
    pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
    pub const ORAGE = Color{ .b = 237, .g = 91, .r = 18, .a = 255 };

    pub fn to_vec3(self: *const Self) Vec3 {
        return .{
            .x = @as(f32, @floatFromInt(self.r)) / 255.0,
            .y = @as(f32, @floatFromInt(self.g)) / 255.0,
            .z = @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }

    // Mix colors based on the alpha channel. Assumes the RGBA.
    pub fn mix_colors(src: Self, dst: Self) Self {
        const src_a_f32 = @as(f32, @floatFromInt(src.a)) / 255.0;

        const r = @as(f32, @floatFromInt(src.r)) * src_a_f32 +
            @as(f32, @floatFromInt(dst.r)) * (1.0 - src_a_f32);
        const g = @as(f32, @floatFromInt(src.g)) * src_a_f32 +
            @as(f32, @floatFromInt(dst.g)) * (1.0 - src_a_f32);
        const b = @as(f32, @floatFromInt(src.b)) * src_a_f32 +
            @as(f32, @floatFromInt(dst.b)) * (1.0 - src_a_f32);

        const r_u8 = @as(u8, @intFromFloat(r));
        const g_u8 = @as(u8, @intFromFloat(g));
        const b_u8 = @as(u8, @intFromFloat(b));

        return .{
            .r = r_u8,
            .g = g_u8,
            .b = b_u8,
            .a = dst.a,
        };
    }
};

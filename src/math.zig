const std = @import("std");
const log = @import("log.zig");

pub const Vec2 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub const X: Vec2 = .{ .x = 1.0, .y = 0.0 };
    pub const NEG_X: Vec2 = .{ .x = -1.0, .y = 0.0 };
    pub const Y: Vec2 = .{ .x = 0.0, .y = 1.0 };
    pub const NEG_Y: Vec2 = .{ .x = 0.0, .y = -1.0 };

    pub inline fn eq(self: Vec2, other: Vec2) bool {
        return self.x == other.x and
            self.y == other.y;
    }

    pub inline fn extend(self: Vec2, z: f32) Vec3 {
        return .{
            .x = self.x,
            .y = self.y,
            .z = z,
        };
    }

    pub inline fn add(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub inline fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub inline fn len_squared(self: Vec2) f32 {
        return self.dot(self);
    }

    pub inline fn len(self: Vec2) f32 {
        return @sqrt(self.dot(self));
    }

    pub inline fn normalize(self: Vec2) Vec2 {
        return self.div_f32(self.len());
    }

    pub inline fn is_valid(self: Vec2) bool {
        return !std.math.isNan(self.x) and !std.math.isNan(self.y);
    }

    pub inline fn neg(self: Vec2) Vec2 {
        return .{
            .x = -self.x,
            .y = -self.y,
        };
    }

    pub inline fn mul(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x * other.x,
            .y = self.y * other.y,
        };
    }

    pub inline fn mul_f32(self: Vec2, v: f32) Vec2 {
        return .{
            .x = self.x * v,
            .y = self.y * v,
        };
    }

    pub inline fn div(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x / other.x,
            .y = self.y / other.y,
        };
    }

    pub inline fn div_f32(self: Vec2, v: f32) Vec2 {
        return .{
            .x = self.x / v,
            .y = self.y / v,
        };
    }

    pub inline fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub inline fn perp(self: Vec2) Vec2 {
        return .{
            .x = -self.y,
            .y = self.x,
        };
    }
};

// Calculate lines a-b and c-d intersection if any
pub fn line_intersection(
    point_a: Vec2,
    point_b: Vec2,
    point_c: Vec2,
    point_d: Vec2,
) ?Vec2 {
    const ab = point_b.sub(point_a);
    const cd = point_d.sub(point_c);
    const perp_dot = ab.x * cd.y - ab.y * cd.x;

    if (perp_dot == 0) {
        return null;
    }

    const ac = point_c.sub(point_a);
    const t = (ac.x * cd.y - ac.y * cd.x) / perp_dot;
    if (t < 0 or t > 1) {
        return null;
    }

    const u = (ac.x * ab.y - ac.y * ab.x) / perp_dot;
    if (u < 0 or u > 1) {
        return null;
    }

    return point_a.add(ab.mul_f32(t));
}

pub const Vec3 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub const X: Vec3 = .{ .x = 1.0 };
    pub const NEG_X: Vec3 = .{ .x = -1.0 };
    pub const Y: Vec3 = .{ .y = 1.0 };
    pub const NEG_Y: Vec3 = .{ .y = -1.0 };
    pub const Z: Vec3 = .{ .z = 1.0 };
    pub const NEG_Z: Vec3 = .{ .z = -1.0 };

    pub inline fn eq(self: Vec3, other: Vec3) bool {
        return self.x == other.x and
            self.y == other.y and
            self.z == other.z;
    }

    pub inline fn xy(self: Vec3) Vec2 {
        return .{ .x = self.x, .y = self.y };
    }

    pub inline fn extend(self: Vec3, w: f32) Vec4 {
        return .{ .x = self.x, .y = self.y, .z = self.z, .w = w };
    }

    pub inline fn add(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub inline fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub inline fn len_squared(self: Vec3) f32 {
        return self.dot(self);
    }

    pub inline fn mul_f32(self: Vec3, n: f32) Vec3 {
        return .{
            .x = self.x * n,
            .y = self.y * n,
            .z = self.z * n,
        };
    }

    pub inline fn div(self: Vec3, n: f32) Vec3 {
        return .{
            .x = self.x / n,
            .y = self.y / n,
            .z = self.z / n,
        };
    }

    pub inline fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub inline fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }
};

pub const Vec4 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    pub inline fn eq(self: Vec4, other: Vec4) bool {
        return self.x == other.x and
            self.y == other.y and
            self.z == other.z and
            self.w == other.w;
    }

    pub inline fn shrink(self: Vec4) Vec3 {
        return .{
            .x = self.x,
            .y = self.y,
            .z = self.z,
        };
    }

    pub inline fn add(self: Vec4, other: Vec4) Vec4 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
            .w = self.w + other.w,
        };
    }

    pub inline fn mul_f32(self: Vec4, v: f32) Vec4 {
        return .{
            .x = self.x * v,
            .y = self.y * v,
            .z = self.z * v,
            .w = self.w * v,
        };
    }

    pub inline fn dot(self: Vec4, other: Vec4) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
    }

    pub inline fn mul_mat4(self: Vec4, m: Mat4) Vec4 {
        return .{
            .x = m.i.dot(self),
            .y = m.j.dot(self),
            .z = m.k.dot(self),
            .w = m.t.dot(self),
        };
    }
};

pub const Quat = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    pub inline fn from_axis_angle(axis: Vec3, angle: f32) Quat {
        const s = @sin(angle / 2.0);
        const c = @cos(angle / 2.0);
        return .{
            .x = axis.x * s,
            .y = axis.y * s,
            .z = axis.z * s,
            .w = c,
        };
    }

    pub inline fn from_rotation_axis(x_axis: Vec3, y_axis: Vec3, z_axis: Vec3) Quat {
        const m00 = x_axis.x;
        const m01 = x_axis.y;
        const m02 = x_axis.z;

        const m10 = y_axis.x;
        const m11 = y_axis.y;
        const m12 = y_axis.z;

        const m20 = z_axis.x;
        const m21 = z_axis.y;
        const m22 = z_axis.z;

        if (m22 <= 0.0) {
            const d = m11 - m00;
            const n = 1.0 - m22;
            if (d <= 0.0) {
                const f = n - d;
                const inv = 0.5 / @sqrt(f);
                return .{
                    .x = f * inv,
                    .y = (m01 + m10) * inv,
                    .z = (m02 + m20) * inv,
                    .w = (m12 - m21) * inv,
                };
            } else {
                const f = n + d;
                const inv = 0.5 / @sqrt(f);
                return .{
                    .x = (m01 + m10) * inv,
                    .y = f * inv,
                    .z = (m12 + m21) * inv,
                    .w = (m20 - m02) * inv,
                };
            }
        } else {
            const d = m11 + m00;
            const n = 1.0 + m22;
            if (d <= 0.0) {
                const f = n - d;
                const inv = 0.5 / @sqrt(f);
                return .{
                    .x = (m02 + m20) * inv,
                    .y = (m12 + m21) * inv,
                    .z = f * inv,
                    .w = (m01 - m10) * inv,
                };
            } else {
                const f = n + d;
                const inv = 0.5 / @sqrt(f);
                return .{
                    .z = (m12 - m21) * inv,
                    .w = (m20 - m02) * inv,
                    .x = (m01 - m10) * inv,
                    .y = f * inv,
                };
            }
        }
    }

    pub inline fn vec3(self: Quat) Vec3 {
        return .{ .x = self.x, .y = self.y, .z = self.z };
    }

    pub inline fn len_squared(self: Quat) f32 {
        const v3 = self.vec3();
        return v3.dot(v3) + self.w * self.w;
    }

    pub inline fn add(self: Quat, other: Quat) Quat {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
            .w = self.w + other.w,
        };
    }

    pub inline fn sub(self: Quat, other: Quat) Quat {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
            .w = self.w - other.w,
        };
    }

    pub inline fn mul_f32(self: Quat, v: f32) Quat {
        return .{
            .x = self.x * v,
            .y = self.y * v,
            .z = self.z * v,
            .w = self.w * v,
        };
    }

    pub inline fn mul(self: Quat, other: Quat) Quat {
        return .{
            .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
            .y = self.w * other.y - self.x * other.z + self.y * other.w + self.z * other.x,
            .z = self.w * other.z + self.x * other.y - self.y * other.x + self.z * other.w,
            .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
        };
    }

    pub inline fn rotate_vec3(self: Quat, v3: Vec3) Vec3 {
        const self_v3 = self.vec3();
        const self_v3_len_sq = self_v3.len_squared();
        return v3.mul_f32(self.w * self.w - self_v3_len_sq)
            .add(self_v3.mul_f32(2.0 * v3.dot(self_v3)))
            .add(2.0 * self.w * self_v3.cross(v3));
    }

    pub inline fn to_mat4(self: Quat) Mat4 {
        const x2 = self.x * self.x;
        const y2 = self.y * self.y;
        const z2 = self.z * self.z;
        const xy = self.x * self.y;
        const xz = self.x * self.z;
        const yz = self.y * self.z;
        const wx = self.w * self.x;
        const wy = self.w * self.y;
        const wz = self.w * self.z;
        return .{
            .i = .{ .x = 1.0 - 2.0 * (y2 + z2), .y = 2.0 * (xy + wz), .z = 2.0 * (xz - wy), .w = 0.0 },
            .j = .{ .x = 2.0 * (xy - wz), .y = 1.0 - 2.0 * (x2 + z2), .z = 2.0 * (yz + wx), .w = 0.0 },
            .k = .{ .x = 2.0 * (xz + wy), .y = 2.0 * (yz - wx), .z = 1.0 - 2.0 * (x2 + y2), .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
    }
};

// Column based 4x4 matrix:
//  i   j   k   t
// |i.x|j.x|k.x|t.x|
// |i.y|j.y|k.y|t.y|
// |i.z|j.z|k.z|t.z|
// |i.w|j.w|k.w|t.w|
pub const Mat4 = extern struct {
    i: Vec4 = .{},
    j: Vec4 = .{},
    k: Vec4 = .{},
    t: Vec4 = .{},

    pub const IDENDITY = Mat4{
        .i = Vec4{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        .j = Vec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
        .k = Vec4{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
        .t = Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
    };

    pub inline fn eq(self: Mat4, other: Mat4) bool {
        return self.i.eq(other.i) and
            self.j.eq(other.j) and
            self.k.eq(other.k) and
            self.t.eq(other.t);
    }

    pub inline fn translate(self: Mat4, v: Vec3) Mat4 {
        var tmp = self;
        tmp.t = tmp.t.add(v.extend(0.0));
        return tmp;
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const g = 1.0 / @tan(fovy / 2.0);
        const k = near / (near - far);
        return .{
            .i = .{ .x = g / aspect },
            .j = .{ .y = g },
            .k = .{ .z = k, .w = 1.0 },
            .t = .{ .z = -far * k },
        };
    }

    pub fn rotation_x(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .i = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            .j = .{ .x = 0.0, .y = c, .z = s, .w = 0.0 },
            .k = .{ .x = 0.0, .y = -s, .z = c, .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
    }

    pub fn rotation_y(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .i = .{ .x = c, .y = 0.0, .z = -s, .w = 0.0 },
            .j = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
            .k = .{ .x = s, .y = 0.0, .z = c, .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
    }

    pub fn rotation_z(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .i = .{ .x = c, .y = s, .z = 0.0, .w = 0.0 },
            .j = .{ .x = -s, .y = c, .z = 0.0, .w = 0.0 },
            .k = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
    }

    // Assume axis is normalized
    pub fn rotation(axis: Vec3, angle: f32) Mat4 {
        log.assert(
            @src(),
            axis.len_squared() == 1.0,
            "Using not normalized axis for rotation matrix",
            .{},
        );
        const c = @cos(angle);
        const s = @sin(angle);
        const d = 1.0 - c;

        const x = axis.x;
        const y = axis.y;
        const z = axis.z;

        return .{
            .i = .{ .x = x * x * d + c, .y = y * x * d + z * s, .z = z * x * d - y * s, .w = 0.0 },
            .j = .{ .x = x * y * d - z * s, .y = y * y * d + c, .z = z * y * d + x * s, .w = 0.0 },
            .k = .{ .x = x * z * d + y * s, .y = y * z * d - x * s, .z = z * z * d + c, .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
    }

    pub inline fn mul_f32(self: Mat4, v: f32) Mat4 {
        return .{
            .i = self.i.mul(v),
            .j = self.j.mul(v),
            .k = self.k.mul(v),
            .t = self.t.mul(v),
        };
    }

    pub inline fn mul_vec4(self: Mat4, v4: Vec4) Vec4 {
        return .{
            .x = self.i.x * v4.x + self.j.x * v4.y + self.k.x * v4.z + self.t.x * v4.w,
            .y = self.i.y * v4.x + self.j.y * v4.y + self.k.y * v4.z + self.t.y * v4.w,
            .z = self.i.z * v4.x + self.j.z * v4.y + self.k.z * v4.z + self.t.z * v4.w,
            .w = self.i.w * v4.x + self.j.w * v4.y + self.k.w * v4.z + self.t.w * v4.w,
        };
    }

    // Self * Other in this order
    pub fn mul(self: Mat4, other: Mat4) Mat4 {
        return .{
            .i = .{
                .x = other.i.x * self.i.x + other.i.y * self.j.x + other.i.z * self.k.x + other.i.w * self.t.x,
                .y = other.i.x * self.i.y + other.i.y * self.j.y + other.i.z * self.k.y + other.i.w * self.t.y,
                .z = other.i.x * self.i.z + other.i.y * self.j.z + other.i.z * self.k.z + other.i.w * self.t.z,
                .w = other.i.x * self.i.w + other.i.y * self.j.w + other.i.z * self.k.w + other.i.w * self.t.w,
            },
            .j = .{
                .x = other.j.x * self.i.x + other.j.y * self.j.x + other.j.z * self.k.x + other.j.w * self.t.x,
                .y = other.j.x * self.i.y + other.j.y * self.j.y + other.j.z * self.k.y + other.j.w * self.t.y,
                .z = other.j.x * self.i.z + other.j.y * self.j.z + other.j.z * self.k.z + other.j.w * self.t.z,
                .w = other.j.x * self.i.w + other.j.y * self.j.w + other.j.z * self.k.w + other.j.w * self.t.w,
            },
            .k = .{
                .x = other.k.x * self.i.x + other.k.y * self.j.x + other.k.z * self.k.x + other.k.w * self.t.x,
                .y = other.k.x * self.i.y + other.k.y * self.j.y + other.k.z * self.k.y + other.k.w * self.t.y,
                .z = other.k.x * self.i.z + other.k.y * self.j.z + other.k.z * self.k.z + other.k.w * self.t.z,
                .w = other.k.x * self.i.w + other.k.y * self.j.w + other.k.z * self.k.w + other.k.w * self.t.w,
            },
            .t = .{
                .x = other.t.x * self.i.x + other.t.y * self.j.x + other.t.z * self.k.x + other.t.w * self.t.x,
                .y = other.t.x * self.i.y + other.t.y * self.j.y + other.t.z * self.k.y + other.t.w * self.t.y,
                .z = other.t.x * self.i.z + other.t.y * self.j.z + other.t.z * self.k.z + other.t.w * self.t.z,
                .w = other.t.x * self.i.w + other.t.y * self.j.w + other.t.z * self.k.w + other.t.w * self.t.w,
            },
        };
    }

    // Assuming last row is 0,0,0,1
    pub inline fn inverse(self: Mat4) Mat4 {
        const a = self.i.shrink();
        const b = self.j.shrink();
        const c = self.k.shrink();
        const d = self.t.shrink();

        const x = self.i.w;
        const y = self.j.w;
        const z = self.k.w;
        const w = self.t.w;

        var s = a.cross(b);
        var t = c.cross(d);
        var u = a.mul_f32(y).sub(b.mul_f32(x));
        var v = c.mul_f32(w).sub(d.mul_f32(z));

        const det = s.dot(v) + t.dot(u);
        log.assert(
            @src(),
            det != 0.0,
            "Cannot create an inverse matrix as determinant is 0.0",
            .{},
        );

        const inv_det = 1.0 / det;
        s = s.mul_f32(inv_det);
        t = t.mul_f32(inv_det);
        u = u.mul_f32(inv_det);
        v = v.mul_f32(inv_det);

        const r0 = b.cross(v).add(t.mul_f32(y));
        const r1 = v.cross(a).sub(t.mul_f32(x));
        const r2 = d.cross(u).add(s.mul_f32(w));
        const r3 = u.cross(c).sub(s.mul_f32(z));

        return .{
            .i = .{ .x = r0.x, .y = r1.x, .z = r2.x, .w = r3.x },
            .j = .{ .x = r0.y, .y = r1.y, .z = r2.y, .w = r3.y },
            .k = .{ .x = r0.z, .y = r1.z, .z = r2.z, .w = r3.z },
            .t = .{ .x = -b.dot(t), .y = a.dot(t), .z = -d.dot(s), .w = c.dot(s) },
        };
    }
};

test "mat4_mul" {
    {
        const mat_1 = Mat4.IDENDITY;
        const mat_2 = Mat4.IDENDITY;
        const m = mat_1.mul(mat_2);
        std.debug.assert(m.eq(Mat4.IDENDITY));
    }

    {
        const mat_1 = Mat4{
            .i = .{ .x = 17.0, .y = 18.0, .z = 19.0, .w = 20.0 },
            .j = .{ .x = 21.0, .y = 22.0, .z = 23.0, .w = 24.0 },
            .k = .{ .x = 25.0, .y = 26.0, .z = 27.0, .w = 28.0 },
            .t = .{ .x = 29.0, .y = 30.0, .z = 31.0, .w = 32.0 },
        };
        const mat_2 = Mat4{
            .i = .{ .x = 1.0, .y = 2.0, .z = 3.0, .w = 4.0 },
            .j = .{ .x = 5.0, .y = 6.0, .z = 7.0, .w = 8.0 },
            .k = .{ .x = 9.0, .y = 10.0, .z = 11.0, .w = 12.0 },
            .t = .{ .x = 13.0, .y = 14.0, .z = 15.0, .w = 16.0 },
        };
        const m = mat_1.mul(mat_2);
        const expected: Mat4 = .{
            .i = .{ .x = 250.0, .y = 260.0, .z = 270.0, .w = 280.0 },
            .j = .{ .x = 618.0, .y = 644.0, .z = 670.0, .w = 696.0 },
            .k = .{ .x = 986.0, .y = 1028.0, .z = 1070.0, .w = 1112.0 },
            .t = .{ .x = 1354.0, .y = 1412.0, .z = 1470.0, .w = 1528.0 },
        };
        std.debug.assert(m.eq(expected));
    }
}

test "mat4_inverse" {
    {
        const mat = Mat4.IDENDITY;
        const m = mat.inverse();
        std.debug.assert(m.eq(Mat4.IDENDITY));
    }

    {
        const mat = Mat4{
            .i = .{ .x = 2.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            .j = .{ .x = 0.0, .y = 2.0, .z = 0.0, .w = 0.0 },
            .k = .{ .x = 0.0, .y = 0.0, .z = 2.0, .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
        const m = mat.inverse();
        const expected = Mat4{
            .i = .{ .x = 1.0 / 2.0, .y = 0.0, .z = 0.0, .w = 0.0 },
            .j = .{ .x = 0.0, .y = 1.0 / 2.0, .z = 0.0, .w = 0.0 },
            .k = .{ .x = 0.0, .y = 0.0, .z = 1.0 / 2.0, .w = 0.0 },
            .t = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
        };
        std.debug.assert(m.eq(expected));
    }
}

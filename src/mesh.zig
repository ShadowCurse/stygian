const _math = @import("math.zig");
const Vec3 = _math.Vec3;
const Vec4 = _math.Vec4;

pub const DefaultVertex = extern struct {
    position: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    uv_x: f32 = 0.0,
    normal: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    uv_y: f32 = 0.0,
    color: Vec4 = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
};

pub const CubeMesh = struct {
    pub var indices = [_]u32{
        1,
        15,
        20,
        1,
        20,
        7,
        10,
        6,
        19,
        10,
        19,
        23,
        21,
        18,
        12,
        21,
        12,
        15,
        16,
        3,
        9,
        16,
        9,
        22,
        5,
        2,
        8,
        5,
        8,
        11,
        17,
        13,
        0,
        17,
        0,
        4,
    };
    pub var vertices = [_]DefaultVertex{
        .{
            .position = Vec3{ .x = 1e0, .y = 1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = -1e0 },
            .uv_x = 6.25e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = -1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = 1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = 1e0, .z = -0e0 },
            .uv_x = 6.25e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 0e0, .y = 1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = 1e0, .z = -1e0 },
            .normal = Vec3{ .x = 1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 6.25e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = -1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = -1e0, .z = -0e0 },
            .uv_x = 3.75e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 0e0, .y = -1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = -1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = -1e0 },
            .uv_x = 3.75e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = -1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = -1e0, .z = -1e0 },
            .normal = Vec3{ .x = 1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 3.75e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = 1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = 1e0 },
            .uv_x = 6.25e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = 1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = 1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = 1e0, .z = -0e0 },
            .uv_x = 6.25e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 0e0, .y = 1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = 1e0, .z = 1e0 },
            .normal = Vec3{ .x = 1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 6.25e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = -1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = -1e0, .z = -0e0 },
            .uv_x = 3.75e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 0e0, .y = -1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = -1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = 1e0 },
            .uv_x = 3.75e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = 1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = 1e0, .y = -1e0, .z = 1e0 },
            .normal = Vec3{ .x = 1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 3.75e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = 1e0, .z = -1e0 },
            .normal = Vec3{ .x = -1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 6.25e-1,
            .uv_y = 7.5e-1,
            .color = Vec4{ .x = -1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = 1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = -1e0 },
            .uv_x = 6.25e-1,
            .uv_y = 7.5e-1,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = -1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = 1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = 1e0, .z = -0e0 },
            .uv_x = 8.75e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 0e0, .y = 1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = -1e0, .z = -1e0 },
            .normal = Vec3{ .x = -1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 3.75e-1,
            .uv_y = 7.5e-1,
            .color = Vec4{ .x = -1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = -1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = -1e0, .z = -0e0 },
            .uv_x = 1.25e-1,
            .uv_y = 5e-1,
            .color = Vec4{ .x = 0e0, .y = -1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = -1e0, .z = -1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = -1e0 },
            .uv_x = 3.75e-1,
            .uv_y = 7.5e-1,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = -1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = 1e0, .z = 1e0 },
            .normal = Vec3{ .x = -1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 6.25e-1,
            .uv_y = 1e0,
            .color = Vec4{ .x = -1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = 1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = 1e0 },
            .uv_x = 6.25e-1,
            .uv_y = 0e0,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = 1e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = 1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = 1e0, .z = -0e0 },
            .uv_x = 8.75e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 0e0, .y = 1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = -1e0, .z = 1e0 },
            .normal = Vec3{ .x = -1e0, .y = 0e0, .z = -0e0 },
            .uv_x = 3.75e-1,
            .uv_y = 1e0,
            .color = Vec4{ .x = -1e0, .y = 0e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = -1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = -1e0, .z = -0e0 },
            .uv_x = 1.25e-1,
            .uv_y = 2.5e-1,
            .color = Vec4{ .x = 0e0, .y = -1e0, .z = -0e0, .w = 1e0 },
        },

        .{
            .position = Vec3{ .x = -1e0, .y = -1e0, .z = 1e0 },
            .normal = Vec3{ .x = 0e0, .y = 0e0, .z = 1e0 },
            .uv_x = 3.75e-1,
            .uv_y = 0e0,
            .color = Vec4{ .x = 0e0, .y = 0e0, .z = 1e0, .w = 1e0 },
        },
    };
};

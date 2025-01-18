const std = @import("std");
const _math = @import("math.zig");
const Vec2 = _math.Vec2;

pub const Circle = struct {
    position: Vec2 = .{},
    radius: f32 = 0.0,
};

pub const Rectangle = struct {
    position: Vec2 = .{},
    size: Vec2 = .{},
    rotation: f32 = 0.0,
};

pub const CollisionPoint = struct {
    position: Vec2,
    normal: Vec2,
};

// Assuming that it is the circle_1 who is trying to collide with circle_2. If they collide
// the collision point will be on the circle_2 surface.
pub fn circle_circle_collision(circle_1: Circle, circle_2: Circle) ?CollisionPoint {
    const to_circle_2 = circle_2.position.sub(circle_1.position);
    const to_circle_2_len = to_circle_2.len();
    if (to_circle_2_len < circle_1.radius + circle_2.radius) {
        const to_collision_len = to_circle_2_len - circle_2.radius;
        const to_circle_2_normalized = to_circle_2.normalize();
        const collision_position = circle_1.position
            .add(to_circle_2_normalized.mul_f32(to_collision_len));
        const collision_normal = to_circle_2_normalized.neg();
        return .{
            .position = collision_position,
            .normal = collision_normal,
        };
    } else {
        return null;
    }
}

// Assuming that it is the circle who is tryign to collide with rectangle. If they collide
// the collision point will be on the rectangle surface.
pub fn circle_rectangle_collision(circle: Circle, rectangle: Rectangle) ?CollisionPoint {
    const angle = rectangle.rotation;
    const rectangle_x_axis = Vec2{ .x = @cos(angle), .y = @sin(angle) };
    const rectangle_y_axis = Vec2{ .x = -@sin(angle), .y = @cos(angle) };
    const circle_x = circle.position.sub(rectangle.position).dot(rectangle_x_axis);
    const circle_y = circle.position.sub(rectangle.position).dot(rectangle_y_axis);

    const circle_v2: Vec2 = .{ .x = circle_x, .y = circle_y };
    const half_width = rectangle.size.x / 2.0;
    const half_height = rectangle.size.y / 2.0;

    const px: Vec2 = .{
        .x = @min(@max(circle_x, -half_width), half_width),
        .y = @min(@max(circle_y, -half_height), half_height),
    };

    const px_to_circle_v2 = circle_v2.sub(px);
    if (px_to_circle_v2.len_squared() < circle.radius * circle.radius) {
        const collision_position = rectangle.position.add(px);
        const collision_normal = circle.position.sub(collision_position).normalize();
        return .{
            .position = collision_position,
            .normal = collision_normal,
        };
    } else {
        return null;
    }
}

const expect = std.testing.expect;
test "test_circle_circle_collision" {
    {
        const c1: Circle = .{ .position = .{ .x = -2.0 }, .radius = 1.0 };
        const c2: Circle = .{ .position = .{}, .radius = 1.0 };
        const collision = circle_circle_collision(c1, c2);
        try expect(collision == null);
    }
    {
        const c1: Circle = .{ .position = .{ .x = -2.0 }, .radius = 1.5 };
        const c2: Circle = .{ .position = .{}, .radius = 1.0 };
        const collision = circle_circle_collision(c1, c2).?;
        try expect(collision.position.eq(Vec2{ .x = -1.0, .y = 0.0 }));
        try expect(collision.normal.eq(Vec2{ .x = -1.0, .y = 0.0 }));
    }
}

test "test_circle_rectangle_collision" {
    // no rotation
    // no collision
    // left
    {
        const c: Circle = .{ .position = .{ .x = -2.0 }, .radius = 1.0 };
        const r: Rectangle = .{ .position = .{}, .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const collision = circle_rectangle_collision(c, r);
        try expect(collision == null);
    }
    // right
    {
        const c: Circle = .{ .position = .{ .x = 2.0 }, .radius = 1.0 };
        const r: Rectangle = .{ .position = .{}, .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const collision = circle_rectangle_collision(c, r);
        try expect(collision == null);
    }
    // bottom
    {
        const c: Circle = .{ .position = .{ .y = -2.0 }, .radius = 1.0 };
        const r: Rectangle = .{ .position = .{}, .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const collision = circle_rectangle_collision(c, r);
        try expect(collision == null);
    }
    // top
    {
        const c: Circle = .{ .position = .{ .y = 2.0 }, .radius = 1.0 };
        const r: Rectangle = .{ .position = .{}, .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const collision = circle_rectangle_collision(c, r);
        try expect(collision == null);
    }
    // collision
    // left
    {
        const c: Circle = .{ .position = .{ .x = -2.0 }, .radius = 1.5 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = -1.0, .y = 0.0 }));
        try expect(collision.normal.eq(Vec2{ .x = -1.0, .y = 0.0 }));
    }
    // right
    {
        const c: Circle = .{ .position = .{ .x = 2.0 }, .radius = 1.5 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = 1.0, .y = 0.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 1.0, .y = 0.0 }));
    }
    // bottom
    {
        const c: Circle = .{ .position = .{ .y = -2.0 }, .radius = 1.5 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = 0.0, .y = -1.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = -1.0 }));
    }
    // top
    {
        const c: Circle = .{ .position = .{ .y = 2.0 }, .radius = 1.5 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = 0.0, .y = 1.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = 1.0 }));
    }
    // collision rect not in the center
    // left
    {
        const c: Circle = .{ .position = .{ .y = 2.0 }, .radius = 1.5 };
        const r: Rectangle = .{
            .position = .{
                .x = 2.0,
                .y = 2.0,
            },
            .size = .{ .x = 2.0, .y = 2.0 },
        };
        const collision = circle_rectangle_collision(c, r).?;
        std.debug.print("{d}:{d}\n", .{ collision.position.x, collision.position.y });
        try expect(collision.position.eq(Vec2{ .x = 1.0, .y = 2.0 }));
        try expect(collision.normal.eq(Vec2{ .x = -1.0, .y = 0.0 }));
    }
    // right
    {
        const c: Circle = .{ .position = .{ .x = 4.0, .y = 2.0 }, .radius = 1.5 };
        const r: Rectangle = .{
            .position = .{
                .x = 2.0,
                .y = 2.0,
            },
            .size = .{ .x = 2.0, .y = 2.0 },
        };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = 3.0, .y = 2.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 1.0, .y = 0.0 }));
    }
    // bottom
    {
        const c: Circle = .{ .position = .{ .x = 2.0, .y = 0.0 }, .radius = 1.5 };
        const r: Rectangle = .{
            .position = .{
                .x = 2.0,
                .y = 2.0,
            },
            .size = .{ .x = 2.0, .y = 2.0 },
        };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = 2.0, .y = 1.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = -1.0 }));
    }
    // top
    {
        const c: Circle = .{ .position = .{ .x = 2.0, .y = 4.0 }, .radius = 1.5 };
        const r: Rectangle = .{
            .position = .{
                .x = 2.0,
                .y = 2.0,
            },
            .size = .{ .x = 2.0, .y = 2.0 },
        };
        const collision = circle_rectangle_collision(c, r).?;
        try expect(collision.position.eq(Vec2{ .x = 2.0, .y = 3.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = 1.0 }));
    }
}

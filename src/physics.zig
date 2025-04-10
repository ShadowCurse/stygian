const std = @import("std");
const log = @import("log.zig");

const Tracing = @import("tracing.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;

pub const trace = Tracing.Measurements(struct {
    apply_collision_impulse: Tracing.Counter,
    point_circle_intersect: Tracing.Counter,
    line_circle_intersect: Tracing.Counter,
    ray_circle_intersect: Tracing.Counter,
    ray_ray_intersection: Tracing.Counter,
    ray_rectangle_intersection: Tracing.Counter,
    point_rectangle_intersect: Tracing.Counter,
    point_rectangle_closest_collision_point: Tracing.Counter,
    circle_circle_collision: Tracing.Counter,
    circle_rectangle_collision: Tracing.Counter,
});

pub const Body = struct {
    position: Vec2 = .{},
    velocity: Vec2 = .{},
    acceleration: Vec2 = .{},
    restitution: f32 = 1.0,
    friction: f32 = 0.0,
    inv_mass: f32 = 0.0,
};

pub const Circle = struct {
    radius: f32 = 0.0,
};

pub const Rectangle = struct {
    size: Vec2 = .{},
    rotation: f32 = 0.0,
};

pub const Line = struct {
    a: Vec2,
    b: Vec2,

    const Self = @This();

    pub fn a_to_b(self: *const Self) Vec2 {
        return self.b.sub(self.a);
    }
};

pub const CollisionPoint = struct {
    position: Vec2,
    normal: Vec2,
};

// Calculate lines intersection
pub fn line_line_intersection(
    line_1: Line,
    line_2: Line,
) ?Vec2 {
    // line_1: a, b
    // line_2: c, d
    const ab = line_1.a_to_b();
    const cd = line_2.a_to_b();
    const perp_dot = ab.x * cd.y - ab.y * cd.x;

    if (perp_dot == 0) {
        return null;
    }

    const ac = line_2.a.sub(line_1.a);
    const t = (ac.x * cd.y - ac.y * cd.x) / perp_dot;
    if (t < 0 or t > 1) {
        return null;
    }

    const u = (ac.x * ab.y - ac.y * ab.x) / perp_dot;
    if (u < 0 or u > 1) {
        return null;
    }

    return line_1.a.add(ab.mul_f32(t));
}

pub fn apply_collision_impulse(
    noalias body_1: *Body,
    noalias body_2: *Body,
    collision_point: CollisionPoint,
) void {
    log.assert(@src(), body_1.velocity.is_valid(), "velocity is not valid", .{});
    log.assert(@src(), body_2.velocity.is_valid(), "velocity is not valid", .{});
    log.assert(
        @src(),
        collision_point.normal.is_valid(),
        "collision_point.normal is not valid",
        .{},
    );

    const relative_velocity = body_1.velocity.sub(body_2.velocity);
    const contact_velocity = relative_velocity.dot(collision_point.normal);
    // If velocities are already in opposite directions,
    // do nothing
    if (0 < contact_velocity)
        return;

    const min_restitution = @min(body_1.restitution, body_2.restitution);
    const impulse_magnitude =
        -(1.0 + min_restitution) * contact_velocity /
        (body_1.inv_mass + body_2.inv_mass);
    const impulse = collision_point.normal.mul_f32(impulse_magnitude);

    log.assert(@src(), impulse.is_valid(), "impulse is not valid", .{});
    log.debug(
        @src(),
        "appying impulse {d}/{d} with magnitude: {d}",
        .{ impulse.x, impulse.y, impulse_magnitude },
    );

    body_1.velocity = body_1.velocity.add(impulse.mul_f32(body_1.inv_mass));
    body_2.velocity = body_2.velocity.add(impulse.neg().mul_f32(body_2.inv_mass));
    log.assert(@src(), body_1.velocity.is_valid(), "velocity is not valid", .{});
    log.assert(@src(), body_2.velocity.is_valid(), "velocity is not valid", .{});
}

pub fn apply_collision_impulse_static(
    noalias body: *Body,
    noalias static_body: *const Body,
    collision_point: CollisionPoint,
) void {
    log.assert(@src(), body.velocity.is_valid(), "velocity is not valid", .{});
    log.assert(@src(), static_body.velocity.eq(.{}), "static body velocity is not zero", .{});
    log.assert(
        @src(),
        collision_point.normal.is_valid(),
        "collision_point.normal is not valid",
        .{},
    );

    const relative_velocity = body.velocity.sub(static_body.velocity);
    const contact_velocity = relative_velocity.dot(collision_point.normal);
    // If velocities are already in opposite directions,
    // do nothing
    if (0 < contact_velocity)
        return;

    const min_restitution = @min(body.restitution, static_body.restitution);
    const impulse_magnitude =
        -(1.0 + min_restitution) * contact_velocity /
        (body.inv_mass + static_body.inv_mass);
    const impulse = collision_point.normal.mul_f32(impulse_magnitude);

    log.assert(@src(), impulse.is_valid(), "impulse is not valid", .{});
    log.debug(
        @src(),
        "appying impulse {d}/{d} with magnitude: {d}",
        .{ impulse.x, impulse.y, impulse_magnitude },
    );

    body.velocity = body.velocity.add(impulse.mul_f32(body.inv_mass));
    log.assert(@src(), body.velocity.is_valid(), "velocity is not valid", .{});
}

pub fn point_circle_intersect(point: Vec2, circle: Circle, circle_position: Vec2) bool {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    return circle_position.sub(point).len_squared() < circle.radius * circle.radius;
}

pub fn line_circle_intersect(
    line_p1: Vec2,
    line_p2: Vec2,
    circle: Circle,
    circle_position: Vec2,
) bool {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    // Move circle at the center of coord
    const line_p1_c = line_p1.sub(circle_position);
    const line_p2_c = line_p2.sub(circle_position);
    const dir = line_p2_c.sub(line_p1_c);
    const dir_len = dir.len();
    const p1_p2_cross = line_p1_c.cross(line_p2_c);
    const d = dir_len * dir_len * circle.radius * circle.radius - p1_p2_cross * p1_p2_cross;
    return 0.0 < d;
}

pub fn ray_circle_intersect(
    ray_origin: Vec2,
    ray_direction: Vec2,
    circle: Circle,
    circle_position: Vec2,
) bool {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const to_circle = circle_position.sub(ray_origin);
    const to_circle_proj_on_dir = to_circle.dot(ray_direction);
    if (to_circle_proj_on_dir < 0.0)
        return false;

    const closest_point_on_ray = ray_origin.add(ray_direction.mul_f32(to_circle_proj_on_dir));
    const circle_to_point = closest_point_on_ray.sub(circle_position);
    const ctp_len = circle_to_point.len();
    return ctp_len < circle.radius;
}

pub fn ray_ray_intersection(
    ray_1_origin: Vec2,
    ray_1_direction: Vec2,
    ray_2_origin: Vec2,
    ray_2_direction: Vec2,
) ?Vec2 {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const c = ray_1_direction.cross(ray_2_direction);
    if (c == 0)
        return null;
    const t = ray_2_origin.sub(ray_1_origin).cross(ray_2_direction.mul_f32(1.0 / c));
    if (t < 0)
        return null;
    return ray_1_origin.add(ray_1_direction.mul_f32(t));
}

pub fn ray_line_intersection(
    ray_origin: Vec2,
    ray_direction: Vec2,
    line_p1: Vec2,
    line_p2: Vec2,
) ?Vec2 {
    const ray_to_p1 = ray_origin.sub(line_p1);
    const p2_to_p1 = line_p2.sub(line_p1);
    const perp_dir = ray_direction.perp();

    const d = p2_to_p1.dot(perp_dir);
    if (d == 0)
        return null;
    const ray_t = p2_to_p1.cross(ray_to_p1) / d;
    const line_t = ray_to_p1.dot(perp_dir) / d;
    if (0.0 <= ray_t and (0.0 <= line_t and line_t <= 1.0))
        return ray_origin.add(ray_direction.mul_f32(ray_t));
    return null;
}

pub fn ray_rectangle_intersection(
    ray_origin: Vec2,
    ray_direction: Vec2,
    rectangle: Rectangle,
    rectangle_position: Vec2,
) ?Vec2 {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const half_width = rectangle.size.x / 2.0;
    const half_heigth = rectangle.size.y / 2.0;
    const left = rectangle_position.x - half_width;
    const right = rectangle_position.x + half_width;
    const bot = rectangle_position.y - half_heigth;
    const top = rectangle_position.y + half_heigth;

    if (ray_line_intersection(
        ray_origin,
        ray_direction,
        .{ .x = left, .y = top },
        .{ .x = right, .y = top },
    )) |i|
        return i;
    if (ray_line_intersection(
        ray_origin,
        ray_direction,
        .{ .x = right, .y = top },
        .{ .x = right, .y = bot },
    )) |i|
        return i;
    if (ray_line_intersection(
        ray_origin,
        ray_direction,
        .{ .x = right, .y = bot },
        .{ .x = left, .y = bot },
    )) |i|
        return i;
    if (ray_line_intersection(
        ray_origin,
        ray_direction,
        .{ .x = left, .y = bot },
        .{ .x = left, .y = top },
    )) |i|
        return i;

    return null;
}

// This one ignores the rectangle rotation
// TODO maybe split rectangle into 2 version: one with rotation and another without
pub fn point_rectangle_intersect(
    point: Vec2,
    rectangle: Rectangle,
    rectangle_position: Vec2,
) bool {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const half_width = rectangle.size.x / 2.0;
    const half_heigth = rectangle.size.y / 2.0;
    const left = rectangle_position.x - half_width;
    const right = rectangle_position.x + half_width;
    const bot = rectangle_position.y - half_heigth;
    const top = rectangle_position.y + half_heigth;
    return left < point.x and point.x < right and bot < point.y and point.y < top;
}

pub fn point_rectangle_closest_collision_point(
    point: Vec2,
    rectangle: Rectangle,
    rectangle_position: Vec2,
) CollisionPoint {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const angle = rectangle.rotation;
    const rectangle_x_axis = Vec2{ .x = @cos(angle), .y = @sin(angle) };
    const rectangle_y_axis = Vec2{ .x = -@sin(angle), .y = @cos(angle) };
    const circle_x = point.sub(rectangle_position).dot(rectangle_x_axis);
    const circle_y = point.sub(rectangle_position).dot(rectangle_y_axis);

    const half_width = rectangle.size.x / 2.0;
    const half_height = rectangle.size.y / 2.0;

    const px: Vec2 = .{
        .x = @min(@max(circle_x, -half_width), half_width),
        .y = @min(@max(circle_y, -half_height), half_height),
    };

    const collision_position = rectangle_position.add(px);
    const collision_normal = point.sub(collision_position).normalize();
    return .{
        .position = collision_position,
        .normal = collision_normal,
    };
}

// Assuming that it is the circle_1 who is trying to collide with circle_2. If they collide
// the collision point will be on the circle_2 surface.
pub fn circle_circle_collision(
    circle_1: Circle,
    circle_1_position: Vec2,
    circle_2: Circle,
    circle_2_position: Vec2,
) ?CollisionPoint {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const to_circle_2 = circle_2_position.sub(circle_1_position);
    const to_circle_2_len = to_circle_2.len();
    if (to_circle_2_len < circle_1.radius + circle_2.radius) {
        const to_collision_len = to_circle_2_len - circle_2.radius;
        const to_circle_2_normalized = to_circle_2.normalize();
        const collision_position = circle_1_position
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
pub fn circle_rectangle_collision(
    circle: Circle,
    circle_position: Vec2,
    rectangle: Rectangle,
    rectangle_position: Vec2,
) ?CollisionPoint {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const angle = rectangle.rotation;
    const rectangle_x_axis = Vec2{ .x = @cos(angle), .y = @sin(angle) };
    const rectangle_y_axis = Vec2{ .x = -@sin(angle), .y = @cos(angle) };
    const circle_x = circle_position.sub(rectangle_position).dot(rectangle_x_axis);
    const circle_y = circle_position.sub(rectangle_position).dot(rectangle_y_axis);

    const circle_v2: Vec2 = .{ .x = circle_x, .y = circle_y };
    const half_width = rectangle.size.x / 2.0;
    const half_height = rectangle.size.y / 2.0;

    const px: Vec2 = .{
        .x = @min(@max(circle_x, -half_width), half_width),
        .y = @min(@max(circle_y, -half_height), half_height),
    };

    const px_to_circle_v2 = circle_v2.sub(px);
    if (px_to_circle_v2.len_squared() < circle.radius * circle.radius) {
        const collision_position = rectangle_position.add(px);
        const collision_normal = circle_position.sub(collision_position).normalize();
        return .{
            .position = collision_position,
            .normal = collision_normal,
        };
    } else {
        return null;
    }
}

const expect = std.testing.expect;

test "test_line_line_intersection" {
    {
        const line_1 = Line{
            .a = .{ .x = -1.0, .y = 0.0 },
            .b = .{ .x = 1.0, .y = 0.0 },
        };
        const line_2 = Line{
            .a = .{ .x = -1.0, .y = 1.0 },
            .b = .{ .x = 1.0, .y = 1.0 },
        };
        const int = line_line_intersection(line_1, line_2);
        try expect(int == null);
    }
    {
        const line_1 = Line{
            .a = .{ .x = -1.0, .y = 0.0 },
            .b = .{ .x = 1.0, .y = 0.0 },
        };
        const line_2 = Line{
            .a = .{ .x = 0.0, .y = -1.0 },
            .b = .{ .x = 0.0, .y = 1.0 },
        };
        const int = line_line_intersection(line_1, line_2).?;
        try expect(int.eq(.{ .x = 0.0, .y = 0.0 }));
    }
}

test "test_circle_circle_collision" {
    {
        const c1: Circle = .{ .radius = 1.0 };
        const c1_position: Vec2 = .{ .x = -2.0 };
        const c2: Circle = .{ .radius = 1.0 };
        const c2_position: Vec2 = .{};
        const collision = circle_circle_collision(c1, c1_position, c2, c2_position);
        try expect(collision == null);
    }
    {
        const c1: Circle = .{ .radius = 1.5 };
        const c1_position: Vec2 = .{ .x = -2.0 };
        const c2: Circle = .{ .radius = 1.0 };
        const c2_position: Vec2 = .{};
        const collision = circle_circle_collision(c1, c1_position, c2, c2_position).?;
        try expect(collision.position.eq(Vec2{ .x = -1.0, .y = 0.0 }));
        try expect(collision.normal.eq(Vec2{ .x = -1.0, .y = 0.0 }));
    }
}

test "test_circle_rectangle_collision" {
    // no rotation
    // no collision
    // left
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: Vec2 = .{ .x = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // right
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: Vec2 = .{ .x = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // bottom
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: Vec2 = .{ .y = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // top
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: Vec2 = .{ .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 1.0, .y = 1.0 }, .rotation = 0.0 };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position);
        try expect(collision == null);
    }
    // collision
    // inside
    {
        const c: Circle = .{ .radius = 1.0 };
        const c_position: Vec2 = .{ .x = 1.0 };
        const r: Rectangle = .{ .size = .{ .x = 4.0, .y = 4.0 } };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 1.0, .y = 0.0 }));
        try expect(!collision.normal.is_valid());
    }
    // left
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .x = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = -1.0, .y = 0.0 }));
        try expect(collision.normal.eq(Vec2{ .x = -1.0, .y = 0.0 }));
    }
    // right
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .x = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 1.0, .y = 0.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 1.0, .y = 0.0 }));
    }
    // bottom
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .y = -2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 0.0, .y = -1.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = -1.0 }));
    }
    // top
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{};
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 0.0, .y = 1.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = 1.0 }));
    }
    // collision rect not in the center
    // left
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 1.0, .y = 2.0 }));
        try expect(collision.normal.eq(Vec2{ .x = -1.0, .y = 0.0 }));
    }
    // right
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .x = 4.0, .y = 2.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 3.0, .y = 2.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 1.0, .y = 0.0 }));
    }
    // bottom
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .x = 2.0, .y = 0.0 };
        const r: Rectangle = .{ .size = .{ .x = 2.0, .y = 2.0 } };
        const r_position: Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 2.0, .y = 1.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = -1.0 }));
    }
    // top
    {
        const c: Circle = .{ .radius = 1.5 };
        const c_position: Vec2 = .{ .x = 2.0, .y = 4.0 };
        const r: Rectangle = .{
            .size = .{ .x = 2.0, .y = 2.0 },
        };
        const r_position: Vec2 = .{ .x = 2.0, .y = 2.0 };
        const collision = circle_rectangle_collision(c, c_position, r, r_position).?;
        try expect(collision.position.eq(Vec2{ .x = 2.0, .y = 3.0 }));
        try expect(collision.normal.eq(Vec2{ .x = 0.0, .y = 1.0 }));
    }
}

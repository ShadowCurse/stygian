const std = @import("std");
const log = @import("log.zig");

const DefaultPrng = std.Random.DefaultPrng;

const Tracing = @import("tracing.zig");
const Color = @import("color.zig").Color;
const Memory = @import("memory.zig");
const Objects = @import("objects.zig");
const Textures = @import("textures.zig");
const ScreenQuads = @import("screen_quads.zig");

const _camera = @import("camera.zig");
const CameraController2d = _camera.CameraController2d;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;

pub const trace = Tracing.Measurements(struct {
    update: Tracing.Counter,
    to_screen_quad: Tracing.Counter,
});

pub const Particle = struct {
    object: Objects.Object2d,
    // 0..1 value
    lifespan: f32,
    alive: bool,
};

pub const UpdateFn = *const fn (
    data: *anyopaque,
    particle_index: u32,
    particle: *Particle,
    rng: *DefaultPrng,
    dt: f32,
) void;

active_particles: []Particle = &.{},
original_particles: []Particle = &.{},
lifespan_per_second: f32 = 0.0,
one_shot: bool = false,
rng: DefaultPrng = undefined,

const Self = @This();

pub fn init(
    memory: *Memory,
    particle_num: u32,
    @"type": Objects.Object2dType,
    original_position: Vec3,
    original_size: Vec2,
    original_rotation: f32,
    lifespan: f32,
    one_shot: bool,
) Self {
    const game_alloc = memory.game_alloc();

    const active_particles = game_alloc.alloc(Particle, particle_num) catch |e| {
        log.warn(@src(), "Cannot allocate memory for particles. Error: {}", .{e});
        return .{};
    };
    const original_particles = game_alloc.alloc(Particle, particle_num) catch |e| {
        log.warn(@src(), "Cannot allocate memory for particles. Error: {}", .{e});
        return .{};
    };

    const rng = DefaultPrng.init(0);

    for (original_particles, active_particles) |*origina_particle, *active_particle| {
        origina_particle.* = .{
            .object = .{
                .type = @"type",
                .transform = .{
                    .position = original_position,
                    .rotation = original_rotation,
                },
                .size = original_size,
            },
            .lifespan = 0.0,
            .alive = true,
        };
        active_particle.* = origina_particle.*;
    }

    return .{
        .active_particles = active_particles,
        .original_particles = original_particles,
        .lifespan_per_second = 1.0 / lifespan,
        .one_shot = one_shot,
        .rng = rng,
    };
}

pub fn update(
    self: *Self,
    data: *anyopaque,
    update_fn: UpdateFn,
    dt: f32,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    for (self.active_particles, 0..) |*p, i| {
        if (!p.alive) {
            continue;
        }
        update_fn(data, @intCast(i), p, &self.rng, dt);
        p.lifespan += self.lifespan_per_second * dt;
        if (1.0 <= p.lifespan) {
            if (!self.one_shot) {
                p.* = self.original_particles[i];
            } else {
                p.alive = false;
            }
        }
    }
}

pub fn to_screen_quad(
    self: Self,
    camera_controller: *const CameraController2d,
    texture_store: *const Textures.Store,
    screen_quads: *ScreenQuads,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    for (self.active_particles) |*p| {
        if (!p.alive) {
            continue;
        }
        p.object.to_screen_quad(camera_controller, texture_store, screen_quads);
    }
}

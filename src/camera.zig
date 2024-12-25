const std = @import("std");
const sdl = @import("bindings/sdl.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Quaterion = _math.Quat;
const Mat4 = _math.Mat4;

pub const CameraController2d = struct {
    velocity: Vec3 = .{},
    speed: f32 = 10.0,
    position: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    screen_size: Vec2 = .{},
    rotation: f32 = 0.0,
    sensitivity: f32 = 20.0,
    near: f32 = 1.0,
    active: bool = false,

    const Self = @This();

    pub fn init(width: u32, height: u32) Self {
        var self: Self = .{};
        self.position.x -= @floatFromInt(width / 2);
        self.position.y -= @floatFromInt(height / 2);
        self.position.z = 2.0;
        self.screen_size = .{ .x = @floatFromInt(width), .y = @floatFromInt(height) };
        return self;
    }

    pub fn process_input(self: *Self, event: *sdl.SDL_Event, dt: f32) void {
        if (event.type == sdl.SDL_KEYDOWN) {
            switch (event.key.keysym.sym) {
                sdl.SDLK_w => self.velocity.y = -1.0,
                sdl.SDLK_s => self.velocity.y = 1.0,
                sdl.SDLK_a => self.velocity.x = -1.0,
                sdl.SDLK_d => self.velocity.x = 1.0,
                sdl.SDLK_SPACE => self.velocity.z = 1.0,
                sdl.SDLK_LCTRL => self.velocity.z = -1.0,
                else => {},
            }
        }

        if (event.type == sdl.SDL_KEYUP) {
            switch (event.key.keysym.sym) {
                sdl.SDLK_w => self.velocity.y = 0,
                sdl.SDLK_s => self.velocity.y = 0,
                sdl.SDLK_a => self.velocity.x = 0,
                sdl.SDLK_d => self.velocity.x = 0,
                sdl.SDLK_SPACE => self.velocity.z = 0,
                sdl.SDLK_LCTRL => self.velocity.z = 0,
                else => {},
            }
        }

        if (event.type == sdl.SDL_MOUSEBUTTONDOWN) {
            self.active = true;
        }
        if (event.type == sdl.SDL_MOUSEBUTTONUP) {
            self.active = false;
        }

        if (self.active and event.type == sdl.SDL_MOUSEMOTION) {
            self.position.x -= @as(f32, @floatFromInt(event.motion.xrel)) * self.sensitivity * dt;
            self.position.y -= @as(f32, @floatFromInt(event.motion.yrel)) * self.sensitivity * dt;
        }
    }

    pub fn update(self: *Self, dt: f32) void {
        self.position = self.position.add(self.velocity.mul_f32(self.speed * dt));
    }

    pub fn transform(self: Self, point: Vec3) Vec3 {
        const z_diff = self.position.z - point.z;
        const scale = self.near / z_diff;
        const half_screen = self.screen_size.mul_f32(0.5);
        const position =
            point.xy()
            .sub(self.position.xy())
            .sub(half_screen)
            .mul(.{ .x = scale, .y = scale })
            .add(half_screen);
        return position.extend(scale);
    }
};

pub const CameraController3d = struct {
    velocity: Vec3 = .{},
    speed: f32 = 5.0,
    position: Vec3 = .{ .x = 0.0, .y = -15.0, .z = 0.0 },

    pitch: f32 = 0.0,
    yaw: f32 = 0.0,
    sensitivity: f32 = 0.5,
    rotation: Quaterion = Quaterion.from_rotation_axis(Vec3.X, Vec3.NEG_Z, Vec3.Y),

    active: bool = false,

    const FORWARD = Vec3.Z;
    const RIGHT = Vec3.X;
    const UP = Vec3.NEG_Y;

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn process_input(self: *Self, event: *sdl.SDL_Event, dt: f32) void {
        if (event.type == sdl.SDL_KEYDOWN) {
            switch (event.key.keysym.sym) {
                sdl.SDLK_w => self.velocity.z = 1.0,
                sdl.SDLK_s => self.velocity.z = -1.0,
                sdl.SDLK_a => self.velocity.x = -1.0,
                sdl.SDLK_d => self.velocity.x = 1.0,
                sdl.SDLK_SPACE => self.velocity.y = -1.0,
                sdl.SDLK_LCTRL => self.velocity.y = 1.0,
                else => {},
            }
        }

        if (event.type == sdl.SDL_KEYUP) {
            switch (event.key.keysym.sym) {
                sdl.SDLK_w => self.velocity.z = 0,
                sdl.SDLK_s => self.velocity.z = 0,
                sdl.SDLK_a => self.velocity.x = 0,
                sdl.SDLK_d => self.velocity.x = 0,
                sdl.SDLK_SPACE => self.velocity.y = 0,
                sdl.SDLK_LCTRL => self.velocity.y = 0,
                else => {},
            }
        }

        if (event.type == sdl.SDL_MOUSEBUTTONDOWN) {
            self.active = true;
        }
        if (event.type == sdl.SDL_MOUSEBUTTONUP) {
            self.active = false;
        }

        if (self.active and event.type == sdl.SDL_MOUSEMOTION) {
            self.yaw -= @as(f32, @floatFromInt(event.motion.xrel)) * self.sensitivity * dt;
            self.pitch -= @as(f32, @floatFromInt(event.motion.yrel)) * self.sensitivity * dt;
            if (std.math.pi / 2.0 < self.pitch) {
                self.pitch = std.math.pi / 2.0;
            }
            if (self.pitch < -std.math.pi / 2.0) {
                self.pitch = -std.math.pi / 2.0;
            }
        }
    }

    pub fn update(self: *Self, dt: f32) void {
        const rotation = self.rotation_matrix();
        const velocity = self.velocity.mul_f32(self.speed * dt).extend(1.0);
        const delta = rotation.mul_vec4(velocity);
        self.position = self.position.add(delta.shrink());
    }

    pub fn transform(self: Self) Mat4 {
        return self.rotation_matrix().translate(self.position);
    }

    pub fn rotation_matrix(self: Self) Mat4 {
        const r_yaw = Quaterion.from_axis_angle(Vec3.Z, self.yaw);
        const r_pitch = Quaterion.from_axis_angle(Vec3.X, self.pitch);
        return r_yaw.mul(r_pitch).mul(self.rotation).to_mat4();
    }
};

const sdl = @import("sdl.zig");

const _math = @import("math.zig");
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const CameraController = struct {
    velocity: Vec3 = .{},
    position: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    pitch: f32 = 0.0,
    yaw: f32 = 0.0,
    active: bool = false,

    pub fn process_input(self: *CameraController, event: *sdl.SDL_Event, dt: f32) void {
        if (event.type == sdl.SDL_KEYDOWN) {
            switch (event.key.keysym.sym) {
                sdl.SDLK_w => self.velocity.z = 1.0,
                sdl.SDLK_s => self.velocity.z = -1.0,
                sdl.SDLK_a => self.velocity.x = 1.0,
                sdl.SDLK_d => self.velocity.x = -1.0,
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
            self.yaw += @as(f32, @floatFromInt(event.motion.xrel)) * dt;
            self.pitch -= @as(f32, @floatFromInt(event.motion.yrel)) * dt;
        }
    }

    pub fn update(self: *CameraController, dt: f32) void {
        const rotation = self.rotation_matrix();
        const delta = rotation.mul_vec4(self.velocity.mul(dt).extend(1.0));
        self.position = self.position.add(delta.shrink());
    }

    pub fn view_matrix(self: *const CameraController) Mat4 {
        const translation = Mat4.IDENDITY.translate(self.position);
        const rotation = self.rotation_matrix();
        return translation.mul(rotation);
    }

    pub fn rotation_matrix(self: *const CameraController) Mat4 {
        return Mat4.rotation(Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 }, self.yaw)
            .mul(Mat4.rotation(Vec3{ .x = -1.0, .y = 0.0, .z = 0.0 }, self.pitch));
    }
};

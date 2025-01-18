const log = @import("log.zig");

const Textures = @import("textures.zig");
const ScreenQuads = @import("screen_quads.zig");

texture_id: Textures.Texture.Id,
frames: u32,

is_playing: bool = false,
is_looping: bool = false,
current_frame: u32 = 0,
current_time: f32 = 0.0,
seconds_per_frame: f32 = 0.0,

const Self = @This();

pub fn init(texture_id: Textures.Texture.Id, frames: u32) Self {
    log.assert(@src(), frames != 0, "Trying to create a FlipBook with 0 frames", .{});
    return .{
        .texture_id = texture_id,
        .frames = frames,
    };
}

pub fn start(self: *Self, frames_per_second: f32, is_looping: bool) void {
    self.is_playing = true;
    self.is_looping = is_looping;
    self.seconds_per_frame = 1 / frames_per_second;
}

pub fn stop(self: *Self) void {
    self.is_playing = false;
}

pub fn update(self: *Self, texture_store: *const Textures.Store, screen_quad: *ScreenQuads.Quad, dt: f32) void {
    if (!self.is_playing) {
        return;
    }

    self.current_time += dt;
    if (self.seconds_per_frame < self.current_time) {
        self.current_frame += 1;
        self.current_time -= self.seconds_per_frame;
    }
    if (self.current_frame == self.frames - 1) {
        if (self.is_looping) {
            self.current_frame = 0;
        } else {
            self.stop();
            return;
        }
    }

    const texture = texture_store.get_texture(self.texture_id);
    const frame_width = texture.width / self.frames;
    const frame_start = frame_width * self.current_frame;

    screen_quad.texture_id = self.texture_id;
    screen_quad.uv_offset = .{ .x = @floatFromInt(frame_start), .y = 0.0 };
    log.assert(@src(), 0 < frame_width, "Frame width must be not 0", .{});
    log.assert(@src(), 0 < texture.height, "Frame height must be not 0", .{});
    screen_quad.uv_size = .{
        .x = @floatFromInt(frame_width),
        .y = @floatFromInt(texture.height),
    };
}

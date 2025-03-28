const std = @import("std");
const log = @import("log.zig");

const Tracing = @import("tracing.zig");
const Textures = @import("textures.zig");
const Memory = @import("memory.zig");
const Color = @import("color.zig").Color;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;

pub const trace = Tracing.Measurements(struct {
    add_quad: Tracing.Counter,
    add_text: Tracing.Counter,
    render: Tracing.Counter,
});

pub const Options = packed struct(u32) {
    clip: bool = true,
    with_tint: bool = false,
    no_scale_rotate: bool = false,
    no_alpha_blend: bool = false,
    draw_aabb: bool = false,
    _: u27 = 0,
};

pub const Quad = extern struct {
    // position in pixels
    position: Vec3 = .{},
    // padding because Vec3 is treated as Vec4
    // in GLSL
    __reserved0: f32 = 0.0,
    // size in pixels
    size: Vec2 = .{},
    // rotation_offset in pixels
    rotation_offset: Vec2 = .{},
    // offset into the texture in pixels
    uv_offset: Vec2 = .{},
    // size of the area to fetch from a texture
    uv_size: Vec2 = .{},

    rotation: f32 = 0.0,
    color: Color = Color.WHITE,
    texture_id: Textures.Texture.Id = Textures.Texture.ID_DEBUG,
    options: Options = .{},
};

quads: []Quad,
used_quads: u32,

const Self = @This();

pub fn init(memory: *Memory, num_quads: u32) !Self {
    const game_alloc = memory.game_alloc();
    return .{
        .quads = try game_alloc.alloc(Quad, num_quads),
        .used_quads = 0,
    };
}

pub fn deinit(self: Self, memory: *Memory) void {
    const game_alloc = memory.game_alloc();
    game_alloc.free(self.quads);
}

pub fn reset(self: *Self) void {
    self.used_quads = 0;
}

pub fn slice(self: *Self) []Quad {
    log.assert(
        @src(),
        self.used_quads <= self.quads.len,
        "Trying to get slice of quads bigger than actual buffer size: {} < {}",
        .{ self.quads.len, self.used_quads },
    );
    return self.quads[0..self.used_quads];
}

pub fn add_quad(self: *Self, quad: Quad) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const remaining_quads = self.quads.len - @as(usize, @intCast(self.used_quads));
    if (remaining_quads < 1) {
        log.warn(
            @src(),
            "Trying to overflow the screen quads. Trying to add {} quads while only {} are available.",
            .{ @as(u32, 1), remaining_quads },
        );
        return;
    }

    defer self.used_quads += 1;
    self.quads[self.used_quads] = quad;
}

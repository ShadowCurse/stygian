const std = @import("std");
const log = @import("log.zig");

const Tracing = @import("tracing.zig");
const Textures = @import("textures.zig");
const Font = @import("font.zig");
const Memory = @import("memory.zig");
const Color = @import("color.zig").Color;
const SoftRenderer = @import("soft_renderer/renderer.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const trace = Tracing.Measurements(struct {
    add_quad: Tracing.Counter,
    add_text: Tracing.Counter,
    render: Tracing.Counter,
});

pub const ScreenQuadOptions = packed struct(u32) {
    clip: bool = true,
    no_scale_rotate: bool = false,
    draw_aabb: bool = false,
    _: u29 = 0,
};

pub const ScreenQuad = extern struct {
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
    options: ScreenQuadOptions = .{},
};

quads: []ScreenQuad,
used_quads: u32,

const Self = @This();

pub fn init(memory: *Memory, num_quads: u32) !Self {
    const game_alloc = memory.game_alloc();
    return .{
        .quads = try game_alloc.alloc(ScreenQuad, num_quads),
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

pub fn slice(self: *Self) []ScreenQuad {
    log.assert(
        @src(),
        self.used_quads <= self.quads.len,
        "Trying to get slice of quads bigger than actual buffer size: {} < {}",
        .{ self.quads.len, self.used_quads },
    );
    return self.quads[0..self.used_quads];
}

pub fn add_quad(self: *Self, quad: ScreenQuad) void {
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

pub fn render(
    self: *Self,
    soft_renderer: *SoftRenderer,
    clip_z: f32,
    texture_store: *const Textures.Store,
) void {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const quads = self.slice();
    const Compare = struct {
        pub fn inner(_: void, a: ScreenQuad, b: ScreenQuad) bool {
            return a.position.z < b.position.z;
        }
    };
    std.mem.sort(ScreenQuad, quads, {}, Compare.inner);
    for (quads) |quad| {
        if (quad.options.clip and clip_z < quad.position.z) {
            continue;
        }

        switch (quad.texture_id) {
            Textures.Texture.ID_VERT_COLOR => {},
            Textures.Texture.ID_SOLID_COLOR => {
                if (quad.options.no_scale_rotate) {
                    soft_renderer.draw_color_rect(
                        quad.position.xy(),
                        quad.size,
                        quad.color,
                        quad.options.draw_aabb,
                    );
                } else {
                    soft_renderer.draw_color_rect_with_size_and_rotation(
                        quad.position.xy(),
                        quad.size,
                        quad.rotation,
                        quad.rotation_offset,
                        quad.color,
                        quad.options.draw_aabb,
                    );
                }
            },
            else => |texture_id| {
                const texture = texture_store.get_texture(texture_id);
                const palette = if (texture.palette_id) |pid|
                    texture_store.get_palette(pid)
                else
                    null;

                if (quad.options.no_scale_rotate) {
                    soft_renderer.draw_texture(
                        quad.position.xy(),
                        .{
                            .texture = texture,
                            .palette = palette,
                            .position = quad.uv_offset,
                            .size = quad.uv_size,
                        },
                        quad.options.draw_aabb,
                    );
                } else {
                    soft_renderer.draw_texture_with_size_and_rotation(
                        quad.position.xy(),
                        quad.size,
                        quad.rotation,
                        quad.rotation_offset,
                        .{
                            .texture = texture,
                            .palette = palette,
                            .position = quad.uv_offset,
                            .size = quad.uv_size,
                        },
                        quad.options.draw_aabb,
                    );
                }
            },
        }
    }
}

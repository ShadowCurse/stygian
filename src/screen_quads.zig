const std = @import("std");
const log = @import("log.zig");

const Perf = @import("performance.zig");
const Texture = @import("texture.zig");
const Font = @import("font.zig").Font;
const Memory = @import("memory.zig");
const Color = @import("color.zig").Color;
const SoftRenderer = @import("soft_renderer/renderer.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const perf = Perf.Measurements(struct {
    add_quad: Perf.Fn,
    add_text: Perf.Fn,
    render: Perf.Fn,
});

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
    texture_id: Texture.Id = Texture.ID_DEBUG,
    __reserved1: f32 = 0.0,
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
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const remaining_quads = self.quads.len - @as(usize, @intCast(self.used_quads));
    if (remaining_quads < 1) {
        log.warn(
            @src(),
            "Trying to overflow the screen quads. Trying to add {} quads while only {} are available.",
            .{ @as(u32, 1), remaining_quads },
        );
        return;
    }

    if (quad.texture_id != Texture.ID_SOLID_COLOR) {
        log.assert(@src(), 0 < quad.uv_size.x, "Quad texture width must be not 0", .{});
        log.assert(@src(), 0 < quad.uv_size.x, "Quad texture height must be not 0", .{});
    }

    defer self.used_quads += 1;
    self.quads[self.used_quads] = quad;
}

pub fn add_text(
    self: *Self,
    font: *const Font,
    text: []const u8,
    size: f32,
    position: Vec3,
    center: bool,
    rotation: f32,
    rotation_offset: Vec2,
) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const remaining_quads = self.quads.len - @as(usize, @intCast(self.used_quads));
    if (remaining_quads < text.len) {
        log.warn(
            @src(),
            "Trying to overflow the screen quads. Trying to add {} quads while only {} are available.",
            .{ text.len, remaining_quads },
        );
        return;
    }
    defer self.used_quads += @intCast(text.len);

    var x_offset: f32 = if (center)
        -font.size * @as(f32, @floatFromInt(text.len / 2))
    else
        0.0;
    const rotation_center = position.xy().add(rotation_offset);
    const scale = size / font.size;
    for (self.quads[self.used_quads .. self.used_quads + text.len], text) |*quad, c| {
        const char_info = font.char_info[c];
        const char_width = @as(f32, @floatFromInt(char_info.x1 - char_info.x0));
        const char_height = @as(f32, @floatFromInt(char_info.y1 - char_info.y0));
        const char_position: Vec3 = .{
            .x = position.x + x_offset + char_info.xoff,
            .y = position.y + char_info.yoff + char_height * 0.5,
            .z = position.z,
        };
        quad.* = .{
            .color = .{},
            .texture_id = font.texture_id,
            .position = char_position,
            .size = .{
                .x = char_width * scale,
                .y = char_height * scale,
            },
            .rotation = rotation,
            .rotation_offset = rotation_center.sub(char_position.xy()),
            .uv_offset = .{
                .x = @as(f32, @floatFromInt(char_info.x0)),
                .y = @as(f32, @floatFromInt(char_info.y0)),
            },
            .uv_size = .{
                .x = char_width,
                .y = char_height,
            },
        };
        x_offset += char_info.xadvance * scale;
    }
}

pub fn render(
    self: *Self,
    soft_renderer: *SoftRenderer,
    texture_store: *const Texture.Store,
) void {
    const perf_start = perf.start();
    defer perf.end(@src(), perf_start);

    const quads = self.slice();
    const Compare = struct {
        pub fn inner(_: void, a: ScreenQuad, b: ScreenQuad) bool {
            return a.position.z < b.position.z;
        }
    };
    std.mem.sort(ScreenQuad, quads, {}, Compare.inner);
    for (quads) |quad| {
        switch (quad.texture_id) {
            Texture.ID_VERT_COLOR => {},
            Texture.ID_SOLID_COLOR => {
                if (quad.rotation == 0.0) {
                    soft_renderer.draw_color_rect(
                        quad.position.xy(),
                        quad.size,
                        quad.color,
                    );
                } else {
                    soft_renderer.draw_color_rect_with_size_and_rotation(
                        quad.position.xy(),
                        quad.size,
                        quad.rotation,
                        quad.rotation_offset,
                        quad.color,
                    );
                }
            },
            else => |texture_id| {
                const texture = texture_store.get(texture_id);
                soft_renderer.draw_texture_with_size_and_rotation(
                    quad.position.xy(),
                    quad.size,
                    quad.rotation,
                    quad.rotation_offset,
                    .{
                        .texture = texture,
                        .position = quad.uv_offset,
                        .size = quad.uv_size,
                    },
                );
                // }
            },
        }
    }
}

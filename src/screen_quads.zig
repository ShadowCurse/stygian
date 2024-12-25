const std = @import("std");
const log = @import("log.zig");

const Image = @import("image.zig");
const Font = @import("font.zig").Font;
const Memory = @import("memory.zig");
const Color = @import("color.zig").Color;
const SoftRenderer = @import("soft_renderer/renderer.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

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
    texture_id: u32,
    __reserved1: f32 = 0.0,
};

pub const TextureIdVertColor = std.math.maxInt(u32);
pub const TextureIdSolidColor = std.math.maxInt(u32) - 1;

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
    return self.quads[0..self.used_quads];
}

pub fn add_quad(self: *Self, quad: ScreenQuad) void {
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

pub fn add_text(
    self: *Self,
    font: *const Font,
    text: []const u8,
    position: Vec3,
) void {
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

    var x_offset: f32 = -font.size * @as(f32, @floatFromInt(text.len / 2));
    for (self.quads[self.used_quads .. self.used_quads + text.len], text) |*tile, c| {
        const char_info = font.char_info[c];
        tile.* = .{
            .color = .{},
            .texture_id = font.image_id,
            .position = .{
                .x = position.x + x_offset,
                .y = position.y,
                .z = position.z,
            },
            .size = .{
                .x = @as(f32, @floatFromInt(char_info.x1 - char_info.x0)),
                .y = @as(f32, @floatFromInt(char_info.y1 - char_info.y0)),
            },
            .uv_offset = .{
                .x = @as(f32, @floatFromInt(char_info.x0)),
                .y = @as(f32, @floatFromInt(char_info.y0)),
            },
            .uv_size = .{
                .x = @as(f32, @floatFromInt(char_info.x1 - char_info.x0)),
                .y = @as(f32, @floatFromInt(char_info.y1 - char_info.y0)),
            },
        };
        x_offset += char_info.xadvance;
    }
}

pub fn render(
    self: *Self,
    soft_renderer: *SoftRenderer,
    images: []const Image,
) void {
    const quads = self.slice();
    const Compare = struct {
        pub fn inner(_: void, a: ScreenQuad, b: ScreenQuad) bool {
            return a.position.z < b.position.z;
        }
    };
    std.mem.sort(ScreenQuad, quads, {}, Compare.inner);
    for (quads) |quad| {
        switch (quad.texture_id) {
            TextureIdVertColor => {},
            TextureIdSolidColor => {
                if (quad.rotation == 0.0) {
                    soft_renderer.draw_color_rect(
                        quad.position.xy(),
                        quad.size,
                        quad.color,
                    );
                } else {
                    soft_renderer.draw_color_rect_with_rotation(
                        quad.position.xy(),
                        quad.size,
                        quad.rotation,
                        quad.rotation_offset,
                        quad.color,
                    );
                }
            },
            else => |texture_id| {
                const image = &images[texture_id];
                if (quad.rotation == 0.0) {
                    soft_renderer.draw_image(
                        quad.position.xy(),
                        .{
                            .image = image,
                            .position = quad.uv_offset,
                            .size = quad.uv_size,
                        },
                    );
                } else {
                    soft_renderer.draw_image_with_scale_and_rotation(
                        quad.position.xy(),
                        quad.size,
                        quad.rotation,
                        quad.rotation_offset,
                        .{
                            .image = image,
                            .position = quad.uv_offset,
                            .size = quad.uv_size,
                        },
                    );
                }
            },
        }
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");
const Font = @import("font.zig");
const Camera = @import("camera.zig");
const ScreenQuads = @import("screen_quads.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;

pub const MAX_NEW_LINES = 32;
pub const Options = packed struct {
    center: bool = true,
    dont_clip: bool = false,
};

font: *const Font,
text: []const u8,
size: f32,
position: Vec3,
rotation: f32,
rotation_offset: Vec2,
options: Options,

const Self = @This();

pub fn init(
    font: *const Font,
    text: []const u8,
    size: f32,
    position: Vec3,
    rotation: f32,
    rotation_offset: Vec2,
    options: Options,
) Self {
    return .{
        .font = font,
        .text = text,
        .size = size,
        .position = position,
        .rotation = rotation,
        .rotation_offset = rotation_offset,
        .options = options,
    };
}

pub fn to_screen_quads(
    self: Self,
    allocator: Allocator,
    screen_quads: *ScreenQuads,
) void {
    const r = self.to_screen_quads_raw(allocator);
    for (r.quad_lines) |quad_line| {
        for (quad_line) |quad| {
            screen_quads.add_quad(quad);
        }
    }
}

pub fn to_screen_quads_world_space(
    self: Self,
    allocator: Allocator,
    camera_controller: *const Camera.CameraController2d,
    screen_quads: *ScreenQuads,
) void {
    const r = self.to_screen_quads_world_space_raw(allocator, camera_controller);
    for (r.quad_lines) |quad_line| {
        for (quad_line) |quad| {
            screen_quads.add_quad(quad);
        }
    }
}

pub const RawTextQuads = struct {
    quad_lines: [][]ScreenQuads.Quad,
    max_width: f32,
};
pub fn to_screen_quads_raw(
    self: Self,
    allocator: Allocator,
) RawTextQuads {
    return self.to_screen_quads_raw_impl(allocator, self.position.xy().extend(1.0));
}

pub fn to_screen_quads_world_space_raw(
    self: Self,
    allocator: Allocator,
    camera_controller: *const Camera.CameraController2d,
) RawTextQuads {
    const world_position = camera_controller.transform(self.position);
    return self.to_screen_quads_raw_impl(allocator, world_position);
}

pub fn quad_lines_for_text(allocator: Allocator, text: []const u8) [][]ScreenQuads.Quad {
    var quad_lines = allocator.alloc([]ScreenQuads.Quad, MAX_NEW_LINES) catch unreachable;
    var quad_lines_n: u32 = 0;

    var char_index: u32 = 0;
    var last_line_start: u32 = 0;
    while (true) : (char_index += 1) {
        if (char_index == text.len) {
            const length = char_index - last_line_start;
            quad_lines[quad_lines_n] =
                allocator.alloc(ScreenQuads.Quad, length) catch unreachable;
            quad_lines_n += 1;
            break;
        } else {
            const c = text[char_index];
            if (c == '\n') {
                if (quad_lines_n == MAX_NEW_LINES) {
                    log.err(
                        @src(),
                        "Trying to process text string with more new lines than allowed. Max is {d}. Text: {s}",
                        .{ @as(u32, MAX_NEW_LINES), text },
                    );
                    return &.{};
                }

                const length = char_index - last_line_start;
                quad_lines[quad_lines_n] =
                    allocator.alloc(ScreenQuads.Quad, length) catch unreachable;
                quad_lines_n += 1;
                last_line_start = char_index + 1;
            }
        }
    }
    return quad_lines[0..quad_lines_n];
}

pub fn to_screen_quads_raw_impl(
    self: Self,
    allocator: Allocator,
    position: Vec3,
) RawTextQuads {
    const scale = self.size / self.font.size * position.z;
    const rotation_center = position.xy().add(self.rotation_offset);
    var offset: Vec3 = .{};
    var max_width: f32 = 0.0;

    const quad_lines = quad_lines_for_text(allocator, self.text);

    var line_start: u32 = 0;
    for (quad_lines) |quad_line| {
        const line_end: u32 = line_start + @as(u32, @intCast(quad_line.len));
        defer line_start = line_end + 1;

        for (quad_line, self.text[line_start..line_end]) |*quad, c| {
            const char_info = if (self.font.char_info.len <= c)
                &Font.INVALID_CHAR_INFO
            else
                &self.font.char_info[c];
            const char_width = @as(f32, @floatFromInt(char_info.x1 - char_info.x0));
            const char_height = @as(f32, @floatFromInt(char_info.y1 - char_info.y0));
            const char_origin: Vec3 = position.add(offset);
            const char_offset = Vec3{
                .x = char_info.xoff,
                .y = char_info.yoff + char_height * 0.5,
                .z = 0.0,
            };
            const char_position = char_origin.add(char_offset.mul_f32(scale));
            quad.* = .{
                .color = .{},
                .texture_id = self.font.texture_id,
                .position = char_position,
                .size = .{
                    .x = char_width * scale,
                    .y = char_height * scale,
                },
                .rotation = self.rotation,
                .rotation_offset = rotation_center.sub(char_origin.xy()),
                .uv_offset = .{
                    .x = @as(f32, @floatFromInt(char_info.x0)),
                    .y = @as(f32, @floatFromInt(char_info.y0)),
                },
                .uv_size = .{
                    .x = char_width,
                    .y = char_height,
                },
                .options = .{ .clip = !self.options.dont_clip },
            };
            offset.x += char_info.xadvance * scale;
        }

        if (self.options.center) {
            const text_half_len = offset.x / 2.0;
            for (quad_line) |*quad| {
                quad.position.x -= text_half_len;
            }
        }
        max_width = @max(max_width, offset.x);
        offset.x = 0;
        offset.y += self.size;
    }
    return .{
        .quad_lines = quad_lines,
        .max_width = max_width,
    };
}

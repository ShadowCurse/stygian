const Font = @import("font.zig");
const Camera = @import("camera.zig");
const ScreenQuads = @import("screen_quads.zig");
const ScreenQuadTag = ScreenQuads.ScreenQuadTag;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;

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

pub fn to_screen_quads_world_space(
    self: Self,
    camera_controller: *const Camera.CameraController2d,
    screen_quads: *ScreenQuads,
) void {
    const world_position = camera_controller.transform(self.position);

    const scale = self.size / self.font.size * world_position.z;
    var x_offset: f32 = if (self.options.center)
        -self.font.size * scale * @as(f32, @floatFromInt(self.text.len / 2))
    else
        0.0;

    const rotation_center = world_position.xy().add(self.rotation_offset);
    for (self.text) |c| {
        const char_info = if (self.font.char_info.len <= c)
            &Font.INVALID_CHAR_INFO
        else
            &self.font.char_info[c];
        const char_width = @as(f32, @floatFromInt(char_info.x1 - char_info.x0));
        const char_height = @as(f32, @floatFromInt(char_info.y1 - char_info.y0));
        const char_origin: Vec3 = world_position.add(.{ .x = x_offset });
        const char_offset = Vec3{
            .x = char_info.xoff,
            .y = char_info.yoff + char_height * 0.5,
            .z = 0.0,
        };
        const char_position = char_origin.add(char_offset.mul_f32(scale));
        screen_quads.add_quad(.{
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
        });
        x_offset += char_info.xadvance * scale;
    }
}

pub fn to_screen_quads(
    self: Self,
    screen_quads: *ScreenQuads,
) void {
    const scale = self.size / self.font.size;
    var x_offset: f32 = if (self.options.center)
        -self.font.size * scale * @as(f32, @floatFromInt(self.text.len / 2))
    else
        0.0;

    const rotation_center = self.position.xy().add(self.rotation_offset);
    for (self.text) |c| {
        const char_info = if (self.font.char_info.len <= c)
            &Font.INVALID_CHAR_INFO
        else
            &self.font.char_info[c];
        const char_width = @as(f32, @floatFromInt(char_info.x1 - char_info.x0));
        const char_height = @as(f32, @floatFromInt(char_info.y1 - char_info.y0));
        const char_origin: Vec3 = self.position.add(.{ .x = x_offset });
        const char_offset = Vec3{
            .x = char_info.xoff,
            .y = char_info.yoff + char_height * 0.5,
            .z = 0.0,
        };
        const char_position = char_origin.add(char_offset.mul_f32(scale));
        screen_quads.add_quad(.{
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
        });
        x_offset += char_info.xadvance * scale;
    }
}

const _camera = @import("camera.zig");
const CameraController2d = _camera.CameraController2d;

const ScreenQuads = @import("screen_quads.zig");

const Image = @import("image.zig");

const _color = @import("color.zig");
const Color = _color.Color;

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;
const Quat = _math.Quat;

pub const Transform2d = struct {
    position: Vec3 = .{},
    rotation: f32 = 0.0,
    rotation_offset: Vec2 = .{},
};

pub const Object2dType = union(enum) {
    Color: Color,
    TextureId: u32,
};

pub const Object2d = struct {
    type: Object2dType,
    transform: Transform2d,
    size: Vec2 = .{},

    const Self = @This();

    pub fn to_screen_quad(
        self: Self,
        camera_controller: *const CameraController2d,
        images: []const Image,
        screen_quads: *ScreenQuads,
    ) void {
        const position = camera_controller.transform(self.transform.position);
        switch (self.type) {
            .Color => |color| {
                screen_quads.add_quad(.{
                    .color = color,
                    .texture_id = ScreenQuads.TextureIdSolidColor,
                    .position = position.xy().extend(self.transform.position.z),
                    .size = self.size.mul_f32(position.z),
                    .rotation = self.transform.rotation,
                    .rotation_offset = self.transform.rotation_offset,
                });
            },
            .TextureId => |texture_id| {
                const image = &images[texture_id];
                const image_size = Vec2{
                    .x = @as(f32, @floatFromInt(image.width)),
                    .y = @as(f32, @floatFromInt(image.height)),
                };
                screen_quads.add_quad(.{
                    .texture_id = texture_id,
                    .position = position.xy().extend(self.transform.position.z),
                    .size = self.size.mul_f32(position.z),
                    .rotation = self.transform.rotation,
                    .rotation_offset = self.transform.rotation_offset,
                    .uv_size = image_size,
                });
            },
        }
    }
};

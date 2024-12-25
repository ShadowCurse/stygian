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
    position: Vec2 = .{},
    rotation: f32 = 0.0,
    rotation_offset: Vec2 = .{},
};

pub const Object2dType = union(enum) {
    Color: Color,
    Image: *Image,
};

pub const Object2d = struct {
    type: Object2dType,
    transform: Transform2d,
    size: Vec2 = .{},

    const Self = @This();

    pub fn to_screen_quad(
        self: Self,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        switch (self.type) {
            .Color => |color| {
                screen_quads.add_quad(&.{
                    .color = color,
                    .type = .SolidColor,
                    .pos = self.transform.position
                        .sub(camera_controller.position.xy()),
                    .size = self.size,
                    .rotation = self.transform.rotation,
                    .rotation_offset = self.transform.rotation_offset,
                });
            },
            .Image => |image| {
                const image_size = Vec2{
                    .x = @as(f32, @floatFromInt(image.width)),
                    .y = @as(f32, @floatFromInt(image.height)),
                };
                screen_quads.add_quad(&.{
                    .type = .Texture,
                    .pos = self.transform.position
                        .sub(camera_controller.position.xy()),
                    .size = self.size,
                    .rotation = self.transform.rotation,
                    .rotation_offset = self.transform.rotation_offset,
                    .uv_size = image_size,
                });
            },
        }
    }
};

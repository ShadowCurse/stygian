const std = @import("std");
const log = @import("log.zig");

const MEMORY = &@import("memory.zig").MEMORY;

const VkRenderer = @import("render/vk_renderer.zig");
const FrameContext = VkRenderer.FrameContext;

const _render_mesh = @import("render/mesh.zig");
const MeshPipeline = _render_mesh.MeshPipeline;
const RenderMeshInfo = _render_mesh.RenderMeshInfo;

const _mesh = @import("mesh.zig");
const CubeMesh = _mesh.CubeMesh;

const _math = @import("math.zig");
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const WIDTH = 5;
pub const HEIGHT = 5;

// TODO fix this
pub const CENTER_OFFSET: Vec3 = .{
    .x = -4,
    .z = -4,
};

const TileType = enum {
    None,
    Wall,
};

const Self = @This();

pipeline: MeshPipeline,
mesh: RenderMeshInfo,

map: [WIDTH][HEIGHT]TileType,
meshes_set: u32,

pub fn init(renderer: *VkRenderer) !Self {
    const pipeline = try MeshPipeline.init(renderer);
    const mesh = try RenderMeshInfo.init(renderer, &CubeMesh.indices, &CubeMesh.vertices, WIDTH * HEIGHT);

    return .{
        .pipeline = pipeline,
        .mesh = mesh,
        .map = .{
            .{ .Wall, .Wall, .Wall, .Wall, .Wall },
            .{ .Wall, .None, .None, .None, .Wall },
            .{ .Wall, .None, .None, .None, .Wall },
            .{ .Wall, .None, .None, .None, .Wall },
            .{ .Wall, .Wall, .Wall, .Wall, .Wall },
        },
        .meshes_set = 0,
    };
}

pub fn deini(self: *Self, renderer: *VkRenderer) void {
    self.pipeline.deinit(renderer);
    self.mesh.deinit(renderer);
}

pub fn update(self: *Self, view_proj: Mat4) void {
    self.mesh.push_constants.view_proj = view_proj;
    self.meshes_set = 0;
    for (self.map, 0..) |row, r| {
        for (row, 0..) |tile, c| {
            switch (tile) {
                .None => {},
                .Wall => {
                    self.mesh.set_instance_info(self.meshes_set, .{
                        .transform = Mat4.IDENDITY.translate(
                            (Vec3{
                                .x = @as(f32, @floatFromInt(c)) * 2.0,
                                .z = @as(f32, @floatFromInt(r)) * 2.0,
                            })
                                .add(CENTER_OFFSET),
                        ),
                    });
                    self.meshes_set += 1;
                },
            }
        }
    }
}

pub fn render(
    self: *const Self,
    frame_context: *const FrameContext,
) void {
    self.pipeline.render(frame_context, &.{.{ &self.mesh, self.meshes_set }});
}

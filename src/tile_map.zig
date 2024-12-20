const std = @import("std");
const log = @import("log.zig");

const Memory = @import("memory.zig");
const VkRenderer = @import("vk_renderer/renderer.zig");
const FrameContext = VkRenderer.FrameContext;

const _render_mesh = @import("vk_renderer/mesh.zig");
const MeshPipeline = _render_mesh.MeshPipeline;
const RenderMeshInfo = _render_mesh.RenderMeshInfo;

const _mesh = @import("mesh.zig");
const CubeMesh = _mesh.CubeMesh;

const _math = @import("math.zig");
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const WIDTH = 5;
pub const HEIGHT = 5;

pub const GAP_W = 0.2;
pub const GAP_H = 0.2;

const TileType = enum {
    None,
    Wall,
};

const Self = @This();

pipeline: MeshPipeline,
mesh: RenderMeshInfo,

map: [WIDTH][HEIGHT]TileType,
meshes_set: u32,

pub fn init(memory: *Memory, renderer: *VkRenderer) !Self {
    const pipeline = try MeshPipeline.init(memory, renderer);
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
    var top_left: Vec3 = .{
        .x = -(2.0 + GAP_W) / 2.0 * (WIDTH - 1),
        .z = -(2.0 + GAP_H) / 2.0 * (HEIGHT - 1),
    };
    for (self.map, 0..) |row, r| {
        for (row, 0..) |tile, c| {
            switch (tile) {
                .None => {},
                .Wall => {
                    self.mesh.set_instance_info(self.meshes_set, .{
                        .transform = Mat4.IDENDITY.translate(top_left.add(
                            .{
                                .x = @as(f32, @floatFromInt(c)) * (2.0 + GAP_W),
                                .z = @as(f32, @floatFromInt(r)) * (2.0 + GAP_H),
                            },
                        )),
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

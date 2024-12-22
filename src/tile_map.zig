const std = @import("std");
const log = @import("log.zig");

const Allocator = std.mem.Allocator;
const Memory = @import("memory.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;

const TileType = enum {
    None,
    Wall,
};

const Self = @This();

map: []TileType,
width: u32,
height: u32,
gap_w: f32,
gap_h: f32,

pub fn init(memory: *Memory, width: u32, height: u32, gap_w: f32, gap_h: f32) !Self {
    const game_alloc = memory.game_alloc();
    const map = try game_alloc.alloc(TileType, width * height);

    return .{
        .map = map,
        .width = width,
        .height = height,
        .gap_w = gap_w,
        .gap_h = gap_h,
    };
}

pub fn deini(self: Self, memory: *Memory) void {
    const game_alloc = memory.game_alloc();
    game_alloc.free(self.map);
}

pub fn set_tile(self: *Self, x: u32, y: u32, t: TileType) void {
    const index = x + y * self.width;
    if (self.map.len < index) {
        log.warn(
            @src(),
            "Trying to set a tile outside range: {}/{} outside {}/{}",
            .{ x, y, self.width, self.height },
        );
    } else {
        self.map[index] = t;
    }
}

pub fn get_positions(self: *const Self, allocator: Allocator) ![]Vec2 {
    var filled: u32 = 0;
    for (0..self.height) |y| {
        for (0..self.width) |x| {
            const index = x + y * self.width;
            if (self.map[index] == .Wall) {
                filled += 1;
            }
        }
    }
    const positions = try allocator.alloc(Vec2, filled);
    var top_left: Vec2 = .{
        .x = -(2.0 + self.gap_w) / 2.0 * @as(f32, @floatFromInt(self.width - 1)),
        .y = -(2.0 + self.gap_h) / 2.0 * @as(f32, @floatFromInt(self.height - 1)),
    };
    var p: u32 = 0;
    for (0..self.height) |y| {
        for (0..self.width) |x| {
            const index = x + y * self.width;
            const tile = self.map[index];
            switch (tile) {
                .None => {},
                .Wall => {
                    positions[p] = top_left.add(.{
                        .x = @as(f32, @floatFromInt(x)) * (2.0 + self.gap_w),
                        .y = @as(f32, @floatFromInt(y)) * (2.0 + self.gap_h),
                    });
                    p += 1;
                },
            }
        }
    }
    return positions;
}

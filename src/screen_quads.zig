const log = @import("log.zig");

const Font = @import("font.zig").Font;
const Memory = @import("memory.zig");

const _math = @import("math.zig");
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

pub const ScreenQuad = extern struct {
    color: Vec3 = .{},
    type: ScreenQuadType = .VertColor,
    pos: Vec2 = .{},
    size: Vec2 = .{},
    uv_pos: Vec2 = .{},
    uv_scale: Vec2 = .{},
};
pub const ScreenQuadType = enum(u32) {
    VertColor = 0,
    SolidColor = 1,
    Texture = 2,
    Font = 3,
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

pub fn slice(self: *const Self) []const ScreenQuad {
    return self.quads[0..self.used_quads];
}

pub fn add_quad(self: *Self, quad: *const ScreenQuad) void {
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
    self.quads[self.used_quads] = quad.*;
}

pub fn add_text(
    self: *Self,
    font: *const Font,
    text: []const u8,
    pos: Vec2,
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
            .type = .Font,
            .pos = .{
                .x = pos.x + x_offset,
                .y = pos.y,
            },
            .size = .{
                .x = @as(f32, @floatFromInt(char_info.x1 - char_info.x0)),
                .y = @as(f32, @floatFromInt(char_info.y1 - char_info.y0)),
            },
            .uv_pos = .{
                .x = @as(f32, @floatFromInt(char_info.x0)) /
                    @as(f32, @floatFromInt(font.image.width)),
                .y = @as(f32, @floatFromInt(char_info.y0)) /
                    @as(f32, @floatFromInt(font.image.height)),
            },
            .uv_scale = .{
                .x = @as(f32, @floatFromInt((char_info.x1 - char_info.x0))) / @as(
                    f32,
                    @floatFromInt(font.image.width),
                ),
                .y = @as(f32, @floatFromInt((char_info.y1 - char_info.y0))) / @as(
                    f32,
                    @floatFromInt(font.image.height),
                ),
            },
        };
        x_offset += char_info.xadvance;
    }
}

const log = @import("log.zig");
const stb = @import("bindings/stb.zig");

const Color = @import("color.zig").Color;
const Memory = @import("memory.zig");

width: u32,
height: u32,
channels: u32,
data: []u8,

const Self = @This();

pub fn init(memory: *Memory, path: [:0]const u8) !Self {
    const game_alloc = memory.game_alloc();

    var x: i32 = undefined;
    var y: i32 = undefined;
    var c: i32 = undefined;
    if (@as(?[*]u8, stb.stbi_load(path, &x, &y, &c, stb.STBI_rgb_alpha))) |image| {
        defer stb.stbi_image_free(image);

        const width: u32 = @intCast(x);
        const height: u32 = @intCast(y);
        const channels: u32 = @intCast(c);

        log.debug(
            @src(),
            "loaded texture from path: {s} width: {} height: {} channels: {}",
            .{ path, width, height, channels },
        );

        const bytes = try game_alloc.alloc(u8, width * height * channels);
        var data: []u8 = undefined;
        data.ptr = image;
        data.len = width * height * channels;
        @memcpy(bytes, data);

        return .{
            .width = width,
            .height = height,
            .channels = channels,
            .data = bytes,
        };
    } else {
        log.err(@src(), "Cannot load an texture from path: {s}", .{path});
        return error.TextureInit;
    }
}

pub fn deinit(self: Self, memory: *Memory) void {
    const game_alloc = memory.game_alloc();
    game_alloc.free(self.data);
}

pub fn as_color_slice(self: Self) []Color {
    // TODO add assert
    var slice: []Color = undefined;
    slice.ptr = @alignCast(@ptrCast(self.data.ptr));
    slice.len = self.data.len / 4;
    return slice;
}

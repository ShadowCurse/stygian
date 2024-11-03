const log = @import("log.zig");
const stb = @import("stb.zig");

width: u32,
height: u32,
channels: u32,
data: []u8,

const Self = @This();

pub fn init(path: [:0]const u8) !Self {
    var x: i32 = undefined;
    var y: i32 = undefined;
    var c: i32 = undefined;
    if (@as(?[*]u8, stb.stbi_load(path, &x, &y, &c, stb.STBI_rgb_alpha))) |image| {
        const width: u32 = @intCast(x);
        const height: u32 = @intCast(y);
        const channels: u32 = @intCast(c);
        var data: []u8 = undefined;
        data.ptr = image;
        data.len = width * height * channels;

        log.debug(
            @src(),
            "loaded image from path: {s} width: {} height: {} channels: {}",
            .{ path, width, height, channels },
        );
        return .{
            .width = width,
            .height = height,
            .channels = channels,
            .data = data,
        };
    } else {
        return error.ImageInit;
    }
}

pub fn deinit(self: *const Self) void {
    stb.stbi_image_free(self.data.ptr);
}

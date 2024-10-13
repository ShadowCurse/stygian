const std = @import("std");
const Memory = @import("memory.zig");

pub fn main() !void {
    var memory = try Memory.init();
    defer memory.deinit();

    {
        const game_alloc = memory.game_alloc();
        const buf = try game_alloc.alloc(u8, 1024);
        defer game_alloc.free(buf);
        std.log.info("game: alloc {} bytes. game requested bytes: {}", .{ buf.len, memory.game_allocator.total_requested_bytes });
    }
    std.log.info("game: game requested bytes after: {}", .{memory.game_allocator.total_requested_bytes});

    {
        const frame_alloc = memory.frame_alloc();
        defer memory.reset_frame();
        const buf = try frame_alloc.alloc(u8, 1024);
        defer frame_alloc.free(buf);
        std.log.info("frame: alloc {} bytes. frame alloc end index: {}", .{ buf.len, memory.frame_allocator.end_index });
    }
    std.log.info("frame alloc end index after: {}", .{memory.frame_allocator.end_index});
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{
    .enable_memory_limit = true,
});
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const GAME_MEMORY_SIZE = 1024 * 1024 * 32;
const FRAME_MEMORY_SIZE = 1024 * 1024;

const Self = @This();

game_allocator: GeneralPurposeAllocator,

frame_buffer: []u8,
frame_allocator: FixedBufferAllocator,

pub fn init() !Self {
    var game_allocator = GeneralPurposeAllocator{};
    game_allocator.setRequestedMemoryLimit(GAME_MEMORY_SIZE);

    const prot = std.os.linux.PROT.READ | std.os.linux.PROT.WRITE;
    const flags = std.os.linux.MAP{
        .TYPE = .PRIVATE,
        .ANONYMOUS = true,
    };
    const frame_buffer = try std.posix.mmap(null, FRAME_MEMORY_SIZE, prot, flags, 0, 0);
    const frame_allocator = std.heap.FixedBufferAllocator.init(frame_buffer);

    return .{
        .game_allocator = game_allocator,

        .frame_buffer = frame_buffer,
        .frame_allocator = frame_allocator,
    };
}

pub fn deinit(self: *Self) void {
    _ = self.game_allocator.deinit();
}

pub fn game_alloc(self: *Self) Allocator {
    return self.game_allocator.allocator();
}

pub fn frame_alloc(self: *Self) Allocator {
    return self.frame_allocator.allocator();
}

pub fn reset_frame(self: *Self) void {
    self.frame_allocator.reset();
}

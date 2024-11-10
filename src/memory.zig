const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{
    .enable_memory_limit = true,
});
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const GAME_MEMORY_SIZE = 1024 * 1024 * 32;
const FRAME_MEMORY_SIZE = 1024 * 1024;
const SCRATCH_MEMORY_SIZE = 1024 * 1024;

game_allocator: GeneralPurposeAllocator,

frame_buffer: []u8,
frame_allocator: FixedBufferAllocator,

scratch_buffer: []u8,
scratch_allocator: FixedBufferAllocator,

const Self = @This();
pub var MEMORY: Self = undefined;

pub fn init(self: *Self) !void {
    self.game_allocator = GeneralPurposeAllocator{};
    self.game_allocator.setRequestedMemoryLimit(GAME_MEMORY_SIZE);

    const prot = std.os.linux.PROT.READ | std.os.linux.PROT.WRITE;
    const flags = std.os.linux.MAP{
        .TYPE = .PRIVATE,
        .ANONYMOUS = true,
    };
    self.frame_buffer = try std.posix.mmap(null, FRAME_MEMORY_SIZE, prot, flags, 0, 0);
    self.frame_allocator = std.heap.FixedBufferAllocator.init(self.frame_buffer);

    self.scratch_buffer = try std.posix.mmap(null, SCRATCH_MEMORY_SIZE, prot, flags, 0, 0);
    self.scratch_allocator = std.heap.FixedBufferAllocator.init(self.scratch_buffer);
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

pub fn scratch_alloc(self: *Self) Allocator {
    return self.scratch_allocator.allocator();
}

pub fn reset_scratch(self: *Self) void {
    self.scratch_allocator.reset();
}

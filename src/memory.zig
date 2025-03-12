const std = @import("std");
const builtin = @import("builtin");
const log = @import("log.zig");
const platform = @import("platform/root.zig");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const DebugAllocator = std.heap.DebugAllocator(.{
    .enable_memory_limit = true,
});
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

const GAME_MEMORY_SIZE = 1024 * 1024 * build_options.game_memory_mb;
const FRAME_MEMORY_SIZE = 1024 * 1024 * build_options.frame_memory_mb;
const SCRATCH_MEMORY_SIZE = platform.PAGE_SIZE * build_options.scratch_memory_pages;

game_allocator: DebugAllocator,
frame_buffer: []u8,
frame_allocator: FixedBufferAllocator,
scratch_allocator: ScratchAllocator,

const Self = @This();

pub fn init() !Self {
    var game_allocator = DebugAllocator{};
    game_allocator.requested_memory_limit = GAME_MEMORY_SIZE;

    const frame_buffer = if (FRAME_MEMORY_SIZE != 0)
        try platform.mmap(FRAME_MEMORY_SIZE)
    else
        &.{};
    const frame_allocator = std.heap.FixedBufferAllocator.init(frame_buffer);

    const scratch_allocator = try ScratchAllocator.init(SCRATCH_MEMORY_SIZE);

    return .{
        .game_allocator = game_allocator,
        .frame_buffer = frame_buffer,
        .frame_allocator = frame_allocator,
        .scratch_allocator = scratch_allocator,
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

pub fn scratch_alloc(self: *Self) Allocator {
    return self.scratch_allocator.allocator();
}

const ScratchAllocator = struct {
    mem: []align(platform.PAGE_SIZE) u8,
    end: u32,
    total_allocated: u32,

    pub fn init(size: u64) !ScratchAllocator {
        try std.testing.expect(size % platform.PAGE_SIZE == 0);
        const mem = try platform.mmap(size);
        return .{
            .mem = mem,
            .end = 0,
            .total_allocated = 0,
        };
    }

    pub fn allocator(self: *ScratchAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, l: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *ScratchAllocator = @ptrCast(@alignCast(ctx));

        if (self.mem.len < l) return null;

        const len: u32 = @intCast(l);

        const ptr_align = alignment.toByteUnits();
        const adjust_off: u32 = @intCast(
            std.mem.alignPointerOffset(
                self.mem.ptr + self.end,
                ptr_align,
            ) orelse return null,
        );
        const adjusted_index = self.end + adjust_off;
        const new_end = adjusted_index + len;

        self.total_allocated += len;
        if (self.mem.len < new_end) {
            const ret = self.mem.ptr;
            std.testing.expect(std.mem.isAligned(@intFromPtr(ret), ptr_align)) catch unreachable;
            self.end = len;
            return ret;
        } else {
            const ret = self.mem.ptr + adjusted_index;
            std.testing.expect(std.mem.isAligned(@intFromPtr(ret), ptr_align)) catch unreachable;
            self.end = new_end;
            return ret;
        }
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;

        if (buf.len < new_len) {
            return false;
        } else {
            return true;
        }
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = alignment;
        _ = ret_addr;

        if (buf.len < new_len) {
            return buf.ptr;
        } else {
            return null;
        }
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = ret_addr;
    }
};

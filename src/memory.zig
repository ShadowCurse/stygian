const std = @import("std");
const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{
    .enable_memory_limit = true,
});
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const HOST_PAGE_SIZE = std.mem.page_size;

const GAME_MEMORY_SIZE = 1024 * 1024 * 32;
const FRAME_MEMORY_SIZE = 1024 * 1024;
const SCRATCH_MEMORY_SIZE = HOST_PAGE_SIZE * 1024;

game_allocator: GeneralPurposeAllocator,

frame_buffer: []u8,
frame_allocator: FixedBufferAllocator,

scratch_allocator: ScratchAllocator,

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

    self.scratch_allocator = try ScratchAllocator.init(SCRATCH_MEMORY_SIZE);
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
    mem: []align(HOST_PAGE_SIZE) u8,
    end: u32,
    total_allocated: u32,

    pub fn init(size: u64) !ScratchAllocator {
        try std.testing.expect(size % HOST_PAGE_SIZE == 0);
        const memfd = try std.posix.memfd_create("scratch_allocator", std.os.linux.FD_CLOEXEC);
        try std.posix.ftruncate(memfd, size);
        const mem = try std.posix.mmap(
            null,
            size * 2,
            std.posix.PROT.NONE,
            std.posix.MAP{
                .TYPE = .PRIVATE,
                .ANONYMOUS = true,
            },
            -1,
            0,
        );
        _ = try std.posix.mmap(
            mem.ptr,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            std.posix.MAP{
                .TYPE = .SHARED,
                .FIXED = true,
            },
            memfd,
            0,
        );
        _ = try std.posix.mmap(
            @alignCast(mem.ptr + size),
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            std.posix.MAP{
                .TYPE = .SHARED,
                .FIXED = true,
            },
            memfd,
            0,
        );
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
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, l: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *ScratchAllocator = @ptrCast(@alignCast(ctx));

        if (self.mem.len < l) return null;

        const len: u32 = @intCast(l);

        const p_align = @as(usize, 1) << @as(Allocator.Log2Align, @intCast(ptr_align));
        const adjust_off: u32 = @intCast(std.mem.alignPointerOffset(self.mem.ptr + self.end, p_align) orelse return null);
        const adjusted_index = self.end + adjust_off;
        const new_end = adjusted_index + len;

        self.total_allocated += len;
        if (self.mem.len < new_end) {
            const ret = self.mem.ptr;
            std.testing.expect(std.mem.isAligned(@intFromPtr(ret), p_align)) catch unreachable;
            self.end = len;
            return ret;
        } else {
            const ret = self.mem.ptr + adjusted_index;
            std.testing.expect(std.mem.isAligned(@intFromPtr(ret), p_align)) catch unreachable;
            self.end = new_end;
            return ret;
        }
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf_align;
        _ = ret_addr;

        if (buf.len < new_len) {
            return false;
        } else {
            return true;
        }
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }
};

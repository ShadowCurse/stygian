const std = @import("std");

const IN_ACCESS = 0x00000001;
const IN_MODIFY = 0x00000002;
const IN_ATTRIB = 0x00000004;
const IN_CLOSE_WRITE = 0x00000008;
const IN_CLOSE_NOWRITE = 0x00000010;
const IN_OPEN = 0x00000020;
const IN_MOVED_FROM = 0x00000040;
const IN_MOVED_TO = 0x00000080;
const IN_CREATE = 0x00000100;
const IN_DELETE = 0x00000200;
const IN_DELETE_SELF = 0x00000400;
const IN_MOVE_SELF = 0x00000800;

const IN_UNMOUNT = 0x00002000;
const IN_Q_OVERFLOW = 0x00004000;
const IN_IGNORED = 0x00008000;

const IN_CLOSE = (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE);
const IN_MOVE = (IN_MOVED_FROM | IN_MOVED_TO);

const IN_ONLYDIR = 0x01000000;
const IN_DONT_FOLLOW = 0x02000000;
const IN_EXCL_UNLINK = 0x04000000;
const IN_MASK_CREATE = 0x10000000;
const IN_MASK_ADD = 0x20000000;
const IN_ISDIR = 0x40000000;
const IN_ONESHOT = 0x80000000;

const IN_ALL_EVENTS = (IN_ACCESS | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE |
    IN_CLOSE_NOWRITE | IN_OPEN | IN_MOVED_FROM |
    IN_MOVED_TO | IN_DELETE | IN_CREATE | IN_DELETE_SELF |
    IN_MOVE_SELF);

pub const RuntimeWatch = struct {
    inotify_fd: i32,
    runtime_fd: i32,
    runtime_dl_handle: *anyopaque = undefined,

    const Self = @This();

    pub fn init(runtime_path: [:0]const u8) !Self {
        const inotify_fd = try std.posix.inotify_init1(@bitCast(std.os.linux.O{ .NONBLOCK = true }));
        const runtime_fd = try std.posix.inotify_add_watchZ(
            inotify_fd,
            runtime_path,
            IN_ALL_EVENTS,
        );

        return .{
            .inotify_fd = inotify_fd,
            .runtime_fd = runtime_fd,
        };
    }

    pub fn has_event(self: *const Self) !bool {
        var buff: [1024]u32 = undefined;
        var buff_u8: []u8 = undefined;
        buff_u8.ptr = @ptrCast(&buff);
        buff_u8.len = buff.len * 4;
        if (std.posix.read(self.inotify_fd, buff_u8)) |_| {
            while (std.posix.read(self.inotify_fd, buff_u8)) |_| {} else |e| {
                if (e != std.posix.ReadError.WouldBlock) {
                    return e;
                }
            }
            return true;
        } else |e| {
            if (e != std.posix.ReadError.WouldBlock) {
                return e;
            }
        }
        return false;
    }
};

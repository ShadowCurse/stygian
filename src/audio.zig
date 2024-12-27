const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Memory = @import("memory.zig");

pub const PlayingSoundtrack = struct {
    soundtrack_id: SoundtrackId,
    progress_bytes: u32,
};

pub const SoundtrackId = u32;
pub const Soundtrack = struct {
    spec: sdl.SDL_AudioSpec,
    data: []u8,
};

// This type assumes it will never be moved after init.
pub const Audio = struct {
    audio_device_id: sdl.SDL_AudioDeviceID,
    volume: f32,

    soundtracks: [MAX_SOUNDTRACKS]Soundtrack,
    soundtracks_num: u32,

    playing_soundtrack: ?PlayingSoundtrack,

    pub const DEBUG_SOUNDRACK_ID = 0;

    const MAX_SOUNDTRACKS = 4;
    const Self = @This();

    // This assummes everything is in i16.
    // TODO maybe move to f32 for simplicity
    pub fn callback(self: *Self, stream_ptr: [*]u8, stream_len: i32) callconv(.C) void {
        const stream_len_u32 = @as(u32, @intCast(stream_len));
        if (self.playing_soundtrack) |*ps| {
            const soundtrack = &self.soundtracks[ps.soundtrack_id];
            if (soundtrack.data.len <= ps.progress_bytes) {
                self.playing_soundtrack = null;
                return;
            }

            var stream_i16: []i16 = undefined;
            stream_i16.ptr = @alignCast(@ptrCast(stream_ptr));
            stream_i16.len = stream_len_u32 / 2;

            var data_i16: []i16 = undefined;
            data_i16.ptr = @alignCast(@ptrCast(soundtrack.data.ptr));
            data_i16.len = soundtrack.data.len / 2;
            const data_start = ps.progress_bytes / 2;

            const remain_bytes = soundtrack.data.len - ps.progress_bytes;
            const copy_bytes = @min(remain_bytes, stream_len_u32);
            const copy = copy_bytes / 2;
            for (stream_i16[0..copy], data_i16[data_start .. data_start + copy]) |*s, d| {
                const new_d = @as(f32, @floatFromInt(d)) * self.volume;
                s.* = @intFromFloat(new_d);
            }
            ps.progress_bytes += copy_bytes;
        }
    }

    pub fn init(self: *Self, volume: f32) !void {
        var wanted = sdl.SDL_AudioSpec{
            .freq = 44100,
            .format = sdl.AUDIO_S16,
            .channels = 2,
            .samples = 4096,
            .callback = @ptrCast(&Self.callback),
            .userdata = self,
        };

        self.audio_device_id = sdl.SDL_OpenAudioDevice(null, 0, &wanted, null, 0);
        self.volume = volume;
        self.soundtracks_num = 1;
        self.playing_soundtrack = null;
    }

    pub fn pause(self: Self) void {
        sdl.SDL_PauseAudioDevice(self.audio_device_id, 1);
    }

    pub fn unpause(self: Self) void {
        sdl.SDL_PauseAudioDevice(self.audio_device_id, 0);
    }

    pub fn play(self: *Self, soundtrack_id: SoundtrackId) void {
        log.assert(
            @src(),
            soundtrack_id < self.soundtracks_num,
            "Trying to play soundtrack outside the range: {} available, {} requested",
            .{ self.soundtracks_num, soundtrack_id },
        );
        self.playing_soundtrack = .{
            .soundtrack_id = soundtrack_id,
            .progress_bytes = 0,
        };
        self.unpause();
    }

    pub fn stop(self: *Self) void {
        self.playing_soundtrack = null;
        self.pause();
    }

    pub fn load_wav(self: *Self, memory: *Memory, path: [:0]const u8) SoundtrackId {
        if (self.soundtracks_num == self.soundtracks.len) {
            log.err(
                @src(),
                "Trying to load more audio tracks than capacity: MAX_SOUNDTRACKS: {}, path: {s}",
                .{ @as(u32, MAX_SOUNDTRACKS), path },
            );
            return DEBUG_SOUNDRACK_ID;
        }

        const game_alloc = memory.game_alloc();
        var soundtrack = &self.soundtracks[self.soundtracks_num];

        var buff_ptr: [*]u8 = undefined;
        var buff_len: u32 = undefined;
        const r = sdl.SDL_LoadWAV(
            path,
            &soundtrack.spec,
            @as([*c][*c]u8, @ptrCast(&buff_ptr)),
            &buff_len,
        );
        if (r == null) {
            log.err(
                @src(),
                "Cannot load WAV file. Path: {s} error: {s}",
                .{ path, sdl.SDL_GetError() },
            );
            return DEBUG_SOUNDRACK_ID;
        }
        defer sdl.SDL_FreeWAV(buff_ptr);

        soundtrack.data = game_alloc.alloc(u8, buff_len) catch |e| {
            log.err(
                @src(),
                "Cannot allocate memory for an audio track. Audio path: {s} error: {}",
                .{ path, e },
            );
            return DEBUG_SOUNDRACK_ID;
        };
        var buff_u8: []u8 = undefined;
        buff_u8.ptr = buff_ptr;
        buff_u8.len = buff_len;
        @memcpy(soundtrack.data, buff_u8);

        const id = self.soundtracks_num;
        self.soundtracks_num += 1;

        log.info(
            @src(),
            "Loaded WAV file from {s} with specs: freq: {}, format: {}, channels: {}",
            .{
                path,
                soundtrack.spec.freq,
                soundtrack.spec.format,
                soundtrack.spec.channels,
            },
        );
        return id;
    }
};

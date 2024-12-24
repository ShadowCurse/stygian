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

    soundtracks: [MAX_SOUNDTRACKS]Soundtrack,
    soundtracks_num: u32,

    playing_soundtrack: ?PlayingSoundtrack,

    const MAX_SOUNDTRACKS = 4;
    const Self = @This();

    pub fn callback(self: *Self, stream_ptr: [*]u8, stream_len: i32) callconv(.C) void {
        const stream_len_u32 = @as(u32, @intCast(stream_len));
        if (self.playing_soundtrack) |*ps| {
            const soundtrack = &self.soundtracks[ps.soundtrack_id];
            if (soundtrack.data.len <= ps.progress_bytes) {
                self.playing_soundtrack = null;
                return;
            }

            var stream: []u8 = undefined;
            stream.ptr = @ptrCast(stream_ptr);
            stream.len = stream_len_u32;

            const remain_bytes = soundtrack.data.len - ps.progress_bytes;
            const copy_bytes = @min(remain_bytes, stream_len_u32);
            const copy = copy_bytes;
            @memcpy(
                stream[0..copy],
                soundtrack.data[ps.progress_bytes .. ps.progress_bytes + copy],
            );
            ps.progress_bytes += copy_bytes;
        }
    }

    pub fn init(self: *Self) !void {
        var wanted = sdl.SDL_AudioSpec{
            .freq = 44100,
            .format = sdl.AUDIO_S16,
            .channels = 2,
            .samples = 4096,
            .callback = @ptrCast(&Self.callback),
            .userdata = self,
        };

        self.audio_device_id = sdl.SDL_OpenAudioDevice(null, 0, &wanted, null, 0);
        self.soundtracks_num = 0;
        self.playing_soundtrack = null;
    }

    pub fn pause(self: Self) void {
        sdl.SDL_PauseAudioDevice(self.audio_device_id, 1);
    }

    pub fn unpause(self: Self) void {
        sdl.SDL_PauseAudioDevice(self.audio_device_id, 0);
    }

    pub fn play(self: *Self, soundtrack_id: SoundtrackId) void {
        self.playing_soundtrack = .{
            .soundtrack_id = soundtrack_id,
            .progress_bytes = 0,
        };
        self.unpause();
    }

    pub fn load_wav(self: *Self, memory: *Memory, path: [:0]const u8) !SoundtrackId {
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
            log.err(@src(), "Cannot load WAV file from: {s}", .{path});
            return error.SDLLoadWav;
        }
        defer sdl.SDL_FreeWAV(buff_ptr);

        soundtrack.data = try game_alloc.alloc(u8, buff_len);
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

const std = @import("std");
const build_options = @import("build_options");
const log = @import("log.zig");
const sdl = @import("bindings/sdl.zig");

const Tracing = @import("tracing.zig");
const Memory = @import("memory.zig");

pub const trace = Tracing.Measurements(struct {
    callback: Tracing.Counter,
});

pub const PlayingSoundtrack = struct {
    soundtrack_id: SoundtrackId = Audio.DEBUG_SOUNDRACK_ID,
    progress_bytes: u32 = 0,
    left_current_volume: f32 = 0.0,
    left_target_volume: f32 = 0.0,
    left_volume_delta_per_sample: f32 = 0.0,
    right_current_volume: f32 = 0.0,
    right_target_volume: f32 = 0.0,
    right_volume_delta_per_sample: f32 = 0.0,
    is_finised: bool = true,
};

pub const SoundtrackId = u32;
pub const Soundtrack = struct {
    spec: sdl.SDL_AudioSpec = .{},
    data: []align(64) u8 = &.{},
};

// This type assumes it will never be moved after init.
pub const Audio = struct {
    audio_device_id: sdl.SDL_AudioDeviceID,
    volume: f32,

    soundtracks: [MAX_SOUNDTRACKS]Soundtrack,
    soundtracks_num: u32,

    playing_soundtracks: [MAX_SOUNDTRACKS]PlayingSoundtrack,

    callback_buffer: []align(64) u8,

    pub const DEBUG_SOUNDRACK_ID = 0;
    const MAX_SOUNDTRACKS = build_options.max_audio_tracks;
    const Self = @This();

    pub fn callback(self: *Self, stream_ptr: [*]u8, stream_len: i32) callconv(.C) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const stream_len_u32 = @as(u32, @intCast(stream_len));

        var stream_8_i16: []@Vector(8, i16) = undefined;
        stream_8_i16.ptr = @alignCast(@ptrCast(stream_ptr));
        stream_8_i16.len = stream_len_u32 / 16;

        var buffer_8_i16: []@Vector(8, i16) = undefined;
        buffer_8_i16.ptr = @alignCast(@ptrCast(self.callback_buffer.ptr));
        buffer_8_i16.len = self.callback_buffer.len / 16;
        @memset(buffer_8_i16, @splat(0.0));

        const min_i16_f32: @Vector(4, f32) = @splat(std.math.minInt(i16));
        const max_i16_f32: @Vector(4, f32) = @splat(std.math.maxInt(i16));
        for (&self.playing_soundtracks) |*playing_soundtrack| {
            if (playing_soundtrack.is_finised)
                continue;
            const soundtrack = &self.soundtracks[playing_soundtrack.soundtrack_id];

            const remain_bytes = soundtrack.data.len - playing_soundtrack.progress_bytes;
            const copy_bytes = @min(remain_bytes, stream_len_u32);

            var data_8_i16: []@Vector(8, i16) = undefined;
            data_8_i16.ptr = @alignCast(@ptrCast(soundtrack.data.ptr));
            data_8_i16.len = soundtrack.data.len / 16;
            const data_8_start = playing_soundtrack.progress_bytes / 16;
            const copy_8 = copy_bytes / 16;

            const samples_to_reach_target_volume_left: u32 =
                if (playing_soundtrack.left_volume_delta_per_sample == 0.0)
                0
            else
                @intFromFloat(
                    @abs((playing_soundtrack.left_target_volume -
                        playing_soundtrack.left_current_volume) /
                        playing_soundtrack.left_volume_delta_per_sample),
                );

            const samples_to_reach_target_volume_right: u32 =
                if (playing_soundtrack.right_volume_delta_per_sample == 0.0)
                0
            else
                @intFromFloat(
                    @abs((playing_soundtrack.right_target_volume -
                        playing_soundtrack.right_current_volume) /
                        playing_soundtrack.right_volume_delta_per_sample),
                );

            const left_pack_volume_reach = samples_to_reach_target_volume_left / 4;
            const left_item_volume_reach = samples_to_reach_target_volume_left -
                left_pack_volume_reach * 4;

            const right_pack_volume_reach = samples_to_reach_target_volume_right / 4;
            const right_item_volume_reach = samples_to_reach_target_volume_right -
                right_pack_volume_reach * 4;

            var left_volume_f32: @Vector(4, f32) = @splat(playing_soundtrack.left_current_volume);
            if (left_pack_volume_reach <= copy_8) {
                playing_soundtrack.left_current_volume = playing_soundtrack.left_target_volume;
                playing_soundtrack.left_volume_delta_per_sample = 0.0;
            } else {
                playing_soundtrack.left_current_volume +=
                    playing_soundtrack.left_volume_delta_per_sample *
                    @as(f32, @floatFromInt(copy_8 * 4));
            }

            var right_volume_f32: @Vector(4, f32) = @splat(playing_soundtrack.right_current_volume);
            if (right_pack_volume_reach <= copy_8) {
                playing_soundtrack.right_current_volume = playing_soundtrack.right_target_volume;
                playing_soundtrack.right_volume_delta_per_sample = 0.0;
            } else {
                playing_soundtrack.right_current_volume +=
                    playing_soundtrack.right_volume_delta_per_sample *
                    @as(f32, @floatFromInt(copy_8 * 4));
            }

            const master_volume: @Vector(4, f32) = @splat(self.volume);

            for (0..copy_8) |i| {
                const orig_data = data_8_i16[data_8_start + i];
                const left_mask = @Vector(4, i32){ 0, 2, 4, 6 };
                const left_channel_i16: @Vector(4, i16) =
                    @shuffle(i16, orig_data, undefined, left_mask);
                const right_mask = @Vector(4, i32){ 1, 3, 5, 7 };
                const right_channel_i16: @Vector(4, i16) =
                    @shuffle(i16, orig_data, undefined, right_mask);

                var left_channel_f32: @Vector(4, f32) = .{
                    @floatFromInt(left_channel_i16[0]),
                    @floatFromInt(left_channel_i16[1]),
                    @floatFromInt(left_channel_i16[2]),
                    @floatFromInt(left_channel_i16[3]),
                };
                var right_channel_f32: @Vector(4, f32) = .{
                    @floatFromInt(right_channel_i16[0]),
                    @floatFromInt(right_channel_i16[1]),
                    @floatFromInt(right_channel_i16[2]),
                    @floatFromInt(right_channel_i16[3]),
                };

                if (left_pack_volume_reach == i) {
                    switch (left_item_volume_reach) {
                        0 => {
                            // d, d, d, d
                            const d = playing_soundtrack.left_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            left_volume_f32 += a_0;
                        },
                        1 => {
                            // d, d * 2, d * 2, d * 2
                            const d = playing_soundtrack.left_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                            left_volume_f32 += a_0 + a_1;
                        },
                        2 => {
                            // d, d * 2, d * 3, d * 3
                            const d = playing_soundtrack.left_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                            const a_2 = @Vector(4, f32){ 0.0, 0.0, d, d };
                            left_volume_f32 += a_0 + a_1 + a_2;
                        },
                        3 => {
                            // d, d * 2, d * 3, d * 4
                            const d = playing_soundtrack.left_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                            const a_2 = @Vector(4, f32){ 0.0, 0.0, d, d };
                            const a_3 = @Vector(4, f32){ 0.0, 0.0, 0.0, d };
                            left_volume_f32 += a_0 + a_1 + a_2 + a_3;
                        },
                        else => unreachable,
                    }
                } else if (left_pack_volume_reach < i) {} else {
                    // d, d * 2, d * 3, d * 4
                    const d = playing_soundtrack.left_volume_delta_per_sample;
                    const a_0: @Vector(4, f32) = @splat(d);
                    const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                    const a_2 = @Vector(4, f32){ 0.0, 0.0, d, d };
                    const a_3 = @Vector(4, f32){ 0.0, 0.0, 0.0, d };
                    left_volume_f32 += a_0 + a_1 + a_2 + a_3;
                }

                if (right_pack_volume_reach == i) {
                    switch (right_item_volume_reach) {
                        0 => {
                            // d, d, d, d
                            const d = playing_soundtrack.right_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            right_volume_f32 += a_0;
                        },
                        1 => {
                            // d, d * 2, d * 2, d * 2
                            const d = playing_soundtrack.right_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                            right_volume_f32 += a_0 + a_1;
                        },
                        2 => {
                            // d, d * 2, d * 3, d * 3
                            const d = playing_soundtrack.right_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                            const a_2 = @Vector(4, f32){ 0.0, 0.0, d, d };
                            right_volume_f32 += a_0 + a_1 + a_2;
                        },
                        3 => {
                            // d, d * 2, d * 3, d * 4
                            const d = playing_soundtrack.right_volume_delta_per_sample;
                            const a_0: @Vector(4, f32) = @splat(d);
                            const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                            const a_2 = @Vector(4, f32){ 0.0, 0.0, d, d };
                            const a_3 = @Vector(4, f32){ 0.0, 0.0, 0.0, d };
                            right_volume_f32 += a_0 + a_1 + a_2 + a_3;
                        },
                        else => unreachable,
                    }
                } else if (right_pack_volume_reach < i) {} else {
                    // d, d * 2, d * 3, d * 4
                    const d = playing_soundtrack.right_volume_delta_per_sample;
                    const a_0: @Vector(4, f32) = @splat(d);
                    const a_1 = @Vector(4, f32){ 0.0, d, d, d };
                    const a_2 = @Vector(4, f32){ 0.0, 0.0, d, d };
                    const a_3 = @Vector(4, f32){ 0.0, 0.0, 0.0, d };
                    right_volume_f32 += a_0 + a_1 + a_2 + a_3;
                }

                left_channel_f32 *= left_volume_f32 * master_volume;
                right_channel_f32 *= right_volume_f32 * master_volume;

                // Add original to the left/right channels and clamp
                const dst_data = buffer_8_i16[i];
                const dst_left_channel_i16: @Vector(4, i16) =
                    @shuffle(i16, dst_data, undefined, left_mask);
                const dst_right_channel_i16: @Vector(4, i16) =
                    @shuffle(i16, dst_data, undefined, right_mask);
                const dst_left_channel_f32: @Vector(4, f32) = .{
                    @floatFromInt(dst_left_channel_i16[0]),
                    @floatFromInt(dst_left_channel_i16[1]),
                    @floatFromInt(dst_left_channel_i16[2]),
                    @floatFromInt(dst_left_channel_i16[3]),
                };
                const dst_right_channel_f32: @Vector(4, f32) = .{
                    @floatFromInt(dst_right_channel_i16[0]),
                    @floatFromInt(dst_right_channel_i16[1]),
                    @floatFromInt(dst_right_channel_i16[2]),
                    @floatFromInt(dst_right_channel_i16[3]),
                };
                left_channel_f32 += dst_left_channel_f32;
                right_channel_f32 += dst_right_channel_f32;

                left_channel_f32 = std.math.clamp(left_channel_f32, min_i16_f32, max_i16_f32);
                right_channel_f32 = std.math.clamp(right_channel_f32, min_i16_f32, max_i16_f32);

                const final_data_mask = @Vector(8, i32){ 0, -1, 1, -2, 2, -3, 3, -4 };
                const final_data_f32: @Vector(8, f32) =
                    @shuffle(f32, left_channel_f32, right_channel_f32, final_data_mask);

                buffer_8_i16[i] = .{
                    @intFromFloat(final_data_f32[0]),
                    @intFromFloat(final_data_f32[1]),
                    @intFromFloat(final_data_f32[2]),
                    @intFromFloat(final_data_f32[3]),
                    @intFromFloat(final_data_f32[4]),
                    @intFromFloat(final_data_f32[5]),
                    @intFromFloat(final_data_f32[6]),
                    @intFromFloat(final_data_f32[7]),
                };
            }

            // var stream_i16: []i16 = undefined;
            // stream_i16.ptr = @alignCast(@ptrCast(stream_ptr));
            // stream_i16.len = stream_len_u32 / 2;
            // @memset(stream_i16, 0);
            // var data_i16: []i16 = undefined;
            // data_i16.ptr = @alignCast(@ptrCast(soundtrack.data.ptr));
            // data_i16.len = soundtrack.data.len / 2;
            // const data_start = playing_soundtrack.progress_bytes / 2;
            // const copy = copy_bytes / 2;
            // const left_volume = &playing_soundtrack.left_current_volume;
            // const right_volume = &playing_soundtrack.right_current_volume;
            // var i: u32 = 0;
            // while (i < copy - 1) : (i += 2) {
            //     const s_l = &stream_i16[i];
            //     const s_r = &stream_i16[i + 1];
            //     const l = data_i16[data_start + i];
            //     const r = data_i16[data_start + i + 1];
            //
            //     const new_l = @as(f32, @floatFromInt(l)) * left_volume.*;
            //     s_l.* += @intFromFloat(new_l);
            //     const new_r = @as(f32, @floatFromInt(r)) * right_volume.*;
            //     s_r.* += @intFromFloat(new_r);
            //
            //     left_volume.* += playing_soundtrack.left_volume_delta_per_sample;
            //     right_volume.* += playing_soundtrack.right_volume_delta_per_sample;
            //
            //     if (0.0 < playing_soundtrack.left_volume_delta_per_sample) {
            //         if (playing_soundtrack.left_target_volume <= left_volume.*) {
            //             left_volume.* = playing_soundtrack.left_target_volume;
            //         }
            //     } else {
            //         if (left_volume.* <= playing_soundtrack.left_target_volume) {
            //             left_volume.* = playing_soundtrack.left_target_volume;
            //         }
            //     }
            //     if (0.0 < playing_soundtrack.right_volume_delta_per_sample) {
            //         if (playing_soundtrack.right_target_volume <= right_volume.*) {
            //             right_volume.* = playing_soundtrack.right_target_volume;
            //         }
            //     } else {
            //         if (right_volume.* <= playing_soundtrack.right_target_volume) {
            //             right_volume.* = playing_soundtrack.right_target_volume;
            //         }
            //     }
            // }

            playing_soundtrack.progress_bytes += copy_bytes;
            if (soundtrack.data.len == playing_soundtrack.progress_bytes) {
                playing_soundtrack.is_finised = true;
            }
        }

        @memcpy(stream_8_i16, buffer_8_i16);
    }

    pub fn init(self: *Self, memory: *Memory, volume: f32) !void {
        const game_alloc = memory.game_alloc();

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
        self.soundtracks[DEBUG_SOUNDRACK_ID] = .{};
        self.soundtracks_num = 1;
        for (&self.playing_soundtracks) |*ps| {
            ps.* = .{};
        }

        self.callback_buffer = try game_alloc.alignedAlloc(
            u8,
            64,
            @sizeOf(i16) * wanted.channels * wanted.samples,
        );
    }

    pub fn pause(self: Self) void {
        sdl.SDL_PauseAudioDevice(self.audio_device_id, 1);
    }

    pub fn unpause(self: Self) void {
        sdl.SDL_PauseAudioDevice(self.audio_device_id, 0);
    }

    pub fn is_playing(self: Self, soundtrack_id: SoundtrackId) bool {
        log.assert(
            @src(),
            soundtrack_id < self.soundtracks_num,
            "Trying to check soundtrack outside the range: {} available, {} requested",
            .{ self.soundtracks_num, soundtrack_id },
        );
        for (&self.playing_soundtracks) |*ps| {
            if (ps.soundtrack_id == soundtrack_id) {
                return !ps.is_finised;
            }
        }
        return false;
    }

    pub fn play(
        self: *Self,
        soundtrack_id: SoundtrackId,
        left_volume: f32,
        right_volume: f32,
    ) void {
        log.assert(
            @src(),
            soundtrack_id < self.soundtracks_num,
            "Trying to play soundtrack outside the range: {} available, {} requested",
            .{ self.soundtracks_num, soundtrack_id },
        );
        for (&self.playing_soundtracks) |*ps| {
            if (ps.is_finised) {
                ps.* = .{
                    .soundtrack_id = soundtrack_id,
                    .progress_bytes = 0,
                    .left_current_volume = left_volume,
                    .left_target_volume = left_volume,
                    .left_volume_delta_per_sample = 0.0,
                    .right_current_volume = right_volume,
                    .right_target_volume = right_volume,
                    .right_volume_delta_per_sample = 0.0,
                    .is_finised = false,
                };
                self.unpause();
                return;
            }
        }
        log.warn(
            @src(),
            "Trying to play soundtrack id: {}, but the array is full",
            .{soundtrack_id},
        );
    }

    pub fn set_volume(
        self: *Self,
        soundtrack_id: SoundtrackId,
        left_target_volume: f32,
        left_time_seconds: f32,
        right_target_volume: f32,
        right_time_seconds: f32,
    ) void {
        log.assert(
            @src(),
            soundtrack_id < self.soundtracks_num,
            "Trying to stop soundtrack outside the range: {} available, {} requested",
            .{ self.soundtracks_num, soundtrack_id },
        );
        for (&self.playing_soundtracks) |*ps| {
            if (ps.soundtrack_id == soundtrack_id) {
                ps.left_target_volume = left_target_volume;
                ps.left_volume_delta_per_sample = (left_target_volume - ps.left_current_volume) /
                    (left_time_seconds * 44100.0);
                ps.right_target_volume = right_target_volume;
                ps.right_volume_delta_per_sample = (right_target_volume - ps.right_current_volume) /
                    (right_time_seconds * 44100.0);
                return;
            }
        }
    }

    pub fn stop(self: *Self, soundtrack_id: SoundtrackId) void {
        log.assert(
            @src(),
            soundtrack_id < self.soundtracks_num,
            "Trying to stop soundtrack outside the range: {} available, {} requested",
            .{ self.soundtracks_num, soundtrack_id },
        );
        for (&self.playing_soundtracks) |*ps| {
            if (ps.soundtrack_id == soundtrack_id) {
                ps.is_finised = true;
                return;
            }
        }
    }

    pub fn stop_all(self: *Self) void {
        for (&self.playing_soundtracks) |*ps| {
            ps.is_finised = true;
        }
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

        soundtrack.data = game_alloc.alignedAlloc(u8, 64, buff_len) catch |e| {
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

const std = @import("std");
const stygian = @import("stygian_runtime");
const build_options = stygian.build_options;

const log = stygian.log;
// This configures log level for the runtime
pub const log_options = log.Options{
    .level = .Info,
};

const Tracing = stygian.tracing;
pub const tracing_options = Tracing.Options{
    .max_measurements = 256,
    .enabled = true,
};

const sdl = stygian.bindings.sdl;

const _audio = stygian.audio;
const Audio = _audio.Audio;
const SoundtrackId = _audio.SoundtrackId;

const _color = stygian.color;
const Color = _color.Color;

const Text = stygian.text;
const Font = stygian.font;
const TileMap = stygian.tile_map;
const Textures = stygian.textures;
const FlipBook = stygian.flip_book;
const Particles = stygian.particles;
const ScreenQuads = stygian.screen_quads;

const Memory = stygian.memory;
const Events = stygian.platform.event;
const SoftRenderer = stygian.soft_renderer.renderer;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Mat4 = _math.Mat4;

const _objects = stygian.objects;
const Object2d = _objects.Object2d;
const Transform2d = _objects.Transform2d;

const Runtime = struct {
    camera_controller: CameraController2d,

    texture_store: Textures.Store,
    texture_color_test: Textures.Texture.Id,
    texture_color_test_palette: Textures.Texture.Id,
    texture_item_pot: Textures.Texture.Id,
    texture_alex: Textures.Texture.Id,

    flip_book: FlipBook,
    font: Font,

    screen_quads: ScreenQuads,
    tile_map: TileMap,
    particles: Particles,

    audio: Audio,
    background_sound_id: SoundtrackId,
    attack_sound_id: SoundtrackId,

    soft_renderer: SoftRenderer,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        self.camera_controller = CameraController2d.init(width, height);

        try self.texture_store.init(memory);
        self.texture_color_test = self.texture_store.load(memory, "assets/color_test.png");
        self.texture_color_test_palette =
            self.texture_store.load_bmp(memory, "assets/color_test_palette.bmp");
        self.texture_item_pot = self.texture_store.load(memory, "assets/item_pot.png");
        self.texture_alex = self.texture_store.load(memory, "assets/alex_idle_sheet.png");

        self.flip_book = FlipBook.init(self.texture_alex, 6);
        self.flip_book.start(10.0, true);
        self.font = Font.init(memory, &self.texture_store, "assets/Hack-Regular.ttf", 64);

        self.screen_quads = try ScreenQuads.init(memory, 2048);

        const tm_width = 40;
        const tm_height = 20;
        self.tile_map = try TileMap.init(memory, tm_width, tm_height, 0.2, 0.2);
        var y: u32 = 0;
        while (y < tm_height) : (y += 1) {
            var x: u32 = 0;
            while (x < tm_width) : (x += 1) {
                if (!(0 < y and y < tm_height - 1 and 0 < x and x < tm_width - 1)) {
                    self.tile_map.set_tile(x, y, .Wall);
                }
            }
        }
        self.particles = Particles.init(
            memory,
            100,
            .{ .Color = Color.BLUE },
            .{ .x = 400.0 },
            .{ .x = 5.0, .y = 5.0 },
            0.0,
            3.0,
            false,
        );
        try self.audio.init(memory, 1.0);
        self.background_sound_id = self.audio.load_wav(memory, "assets/background.wav");
        self.attack_sound_id = self.audio.load_wav(memory, "assets/alex_attack.wav");
        self.soft_renderer = SoftRenderer.init(memory, window, width, height);
    }

    fn run(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        width: i32,
        height: i32,
    ) void {
        self.screen_quads.reset();
        const frame_alloc = memory.frame_alloc();

        Tracing.prepare_next_frame(struct {
            SoftRenderer,
            ScreenQuads,
            Particles,
            _objects,
            _audio,
        });
        Tracing.to_screen_quads(
            struct { SoftRenderer, ScreenQuads, Particles, _objects, _audio },
            frame_alloc,
            &self.screen_quads,
            &self.font,
            32.0,
        );
        Tracing.zero_current(struct {
            SoftRenderer,
            ScreenQuads,
            Particles,
            _objects,
            _audio,
        });

        for (events) |event| {
            self.camera_controller.process_input(event, dt);
            switch (event) {
                .Keyboard => |key| {
                    if (key.type == .Pressed) {
                        switch (key.key) {
                            .@"1" => if (self.audio.is_playing(self.background_sound_id))
                                self.audio.stop(self.background_sound_id)
                            else
                                self.audio.play(self.background_sound_id, 0.2, 0.2),
                            .@"2" => if (self.audio.is_playing(self.attack_sound_id))
                                self.audio.stop(self.attack_sound_id)
                            else
                                self.audio.play(self.attack_sound_id, 0.2, 0.2),
                            .P => self.audio.stop_all(),
                            .@"3" => self.audio.volume += 0.01,
                            .@"4" => self.audio.volume -= 0.01,
                            .J => if (self.audio.is_playing(self.background_sound_id))
                                self.audio.set_volume(self.background_sound_id, 0.2, 2.0, 0.2, 2.0),
                            .K => if (self.audio.is_playing(self.background_sound_id))
                                self.audio.set_volume(self.background_sound_id, 0.0, 2.0, 0.0, 2.0),
                            .H => if (self.audio.is_playing(self.background_sound_id))
                                self.audio.set_volume(self.background_sound_id, 0.2, 2.0, 0.0, 2.0),
                            .L => if (self.audio.is_playing(self.background_sound_id))
                                self.audio.set_volume(self.background_sound_id, 0.0, 2.0, 0.2, 2.0),
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }
        self.camera_controller.update(dt);

        const A = struct {
            var a: f32 = 0;
        };
        A.a += dt;

        const objects = [_]Object2d{
            .{
                .type = .{ .Color = Color.ORANGE },
                .transform = .{
                    .position = .{},
                    .rotation = A.a,
                },
                .size = .{
                    .x = 50.0,
                    .y = 50.0,
                },
            },
            .{
                .type = .{ .TextureId = self.texture_item_pot },
                .transform = .{
                    .position = .{
                        .x = -100.0,
                        .y = 0.0,
                    },
                    .rotation = A.a,
                },
                .size = .{
                    .x = 50.0,
                    .y = 50.0,
                },
                .options = .{ .draw_aabb = true },
            },
            .{
                .type = .{ .TextureId = self.texture_color_test_palette },
                .transform = .{
                    .position = .{
                        .x = 100.0,
                        .y = 0.0,
                    },
                    .rotation = A.a,
                },
                .size = .{
                    .x = 50.0,
                    .y = 50.0,
                },
                .options = .{ .draw_aabb = true },
            },
        };

        for (&objects) |*object| {
            object.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
                &self.screen_quads,
            );
        }

        const tile_positions = self.tile_map.get_positions(frame_alloc);
        for (tile_positions) |tile_pos| {
            const object = Object2d{
                .type = .{ .Color = Color.ORANGE },
                .transform = .{
                    .position = tile_pos.mul_f32(25.0).extend(0.0),
                },
                .size = .{ .x = 50.0, .y = 50.0 },
            };
            object.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
                &self.screen_quads,
            );
        }

        const ParticleUpdate = struct {
            var rotation: f32 = 0.0;
            fn update(
                _rotation: *anyopaque,
                particle_index: u32,
                particle: *Particles.Particle,
                rng: *std.rand.DefaultPrng,
                _dt: f32,
            ) void {
                const r: *f32 = @alignCast(@ptrCast(_rotation));
                const random = rng.random();
                const angle = r.* + std.math.pi * 2.0 / 16.0 *
                    @as(f32, @floatFromInt(particle_index));
                const rng_angle = angle + (random.float(f32) * 2.0 - 1.0) * std.math.pi / 2.0;
                const c = @cos(rng_angle);
                const s = @sin(rng_angle);
                const additional_offset: Vec3 = .{ .x = c, .y = s, .z = 0.0 };
                particle.object.transform.position =
                    particle.object.transform.position.add(additional_offset);

                const rng_size = random.float(f32) * 2.0 - 1.0;
                particle.object.size =
                    particle.object.size.add((Vec2{ .x = 5.0, .y = 5.0 })
                    .mul_f32(rng_size * _dt));

                particle.object.transform.rotation += 3.0 * _dt;
                particle.object.type = .{ .Color = .{ .format = .{
                    .r = @intFromFloat(std.math.lerp(8.0, 128.0, particle.lifespan)),
                    .g = @intFromFloat(std.math.lerp(32.0, 255.0, particle.lifespan)),
                    .b = @intFromFloat(std.math.lerp(16.0, 64.0, particle.lifespan)),
                    .a = 255,
                } } };
            }
        };
        ParticleUpdate.rotation = @sin(A.a) * 1.5;

        self.particles.update(&ParticleUpdate.rotation, &ParticleUpdate.update, dt);
        self.particles.to_screen_quad(
            &self.camera_controller,
            &self.texture_store,
            &self.screen_quads,
        );

        const alex_pos = self.camera_controller.transform(.{
            .x = 0.0,
            .y = 425.0,
        });
        var flip_book_quad: ScreenQuads.Quad = .{
            .position = alex_pos.xy().extend(0.0),
            .size = .{
                .x = 128.0 * alex_pos.z,
                .y = 128.0 * alex_pos.z,
            },
        };
        self.flip_book.update(&self.texture_store, &flip_book_quad, dt);
        self.screen_quads.add_quad(flip_book_quad);

        const text_fps = Text.init(
            &self.font,
            std.fmt.allocPrint(
                frame_alloc,
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            32.0,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 300.0,
            },
            0.0,
            .{},
            .{ .dont_clip = true },
        );
        text_fps.to_screen_quads(frame_alloc, &self.screen_quads);

        const text_world_space = Text.init(
            &self.font,
            std.fmt.allocPrint(
                frame_alloc,
                "Camera positon: x: {d:.1} y: {d:.1} z: {d:.1}",
                .{
                    self.camera_controller.position.x,
                    self.camera_controller.position.y,
                    self.camera_controller.position.z,
                },
            ) catch unreachable,
            32.0,
            .{
                .x = -300.0,
                .y = 350.0,
            },
            0.0,
            .{},
            .{},
        );
        text_world_space.to_screen_quads_world_space(frame_alloc, &self.camera_controller, &self.screen_quads);

        self.soft_renderer.start_rendering();
        self.screen_quads.render(
            &self.soft_renderer,
            self.camera_controller.position.z,
            &self.texture_store,
        );
        self.soft_renderer.end_rendering();
    }
};

pub export fn runtime_main(
    window: *sdl.SDL_Window,
    events_ptr: [*]const Events.Event,
    events_len: usize,
    memory: *Memory,
    dt: f32,
    data: ?*anyopaque,
) *anyopaque {
    memory.reset_frame();

    var events: []const Events.Event = undefined;
    events.ptr = events_ptr;
    events.len = events_len;
    var runtime_ptr: ?*Runtime = @alignCast(@ptrCast(data));

    var width: i32 = undefined;
    var height: i32 = undefined;
    sdl.SDL_GetWindowSize(window, &width, &height);

    if (runtime_ptr == null) {
        log.info(@src(), "First time runtime init", .{});
        const game_alloc = memory.game_alloc();
        runtime_ptr = &(game_alloc.alloc(Runtime, 1) catch unreachable)[0];
        runtime_ptr.?.init(window, memory, @intCast(width), @intCast(height)) catch unreachable;
    } else {
        var runtime = runtime_ptr.?;
        runtime.run(memory, dt, events, width, height);
    }
    return @ptrCast(runtime_ptr);
}

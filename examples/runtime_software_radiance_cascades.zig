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
    // .max_measurements = 256,
    .max_measurements = 0,
    .enabled = false,
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
const Vec4 = _math.Vec4;
const Mat4 = _math.Mat4;

const _objects = stygian.objects;
const Object2d = _objects.Object2d;
const Transform2d = _objects.Transform2d;

const Runtime = struct {
    texture_store: Textures.Store,
    font: Font,
    screen_quads: ScreenQuads,
    soft_renderer: SoftRenderer,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        try self.texture_store.init(memory);
        self.font = Font.init(memory, &self.texture_store, "assets/Hack-Regular.ttf", 64);
        self.screen_quads = try ScreenQuads.init(memory, 2048);
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

        const text_fps = Text.init(
            &self.font,
            std.fmt.allocPrint(
                frame_alloc,
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            32.0,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0 + 150.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 300.0,
            },
            0.0,
            .{},
            .{ .dont_clip = true },
        );
        text_fps.to_screen_quads(&self.screen_quads);

        // The screen size is `width` and `height`
        // The resolution in ELEMENTS of the level_0 cascade is `width / 2` and `height / 2`
        // BUT the resolution in SAMPLES is HALF again `width / 4` and `height / 4`
        // because 4 ELEMENTS are used for 4 directions
        // For highter cascades the divisor is 16, 64 and so on
        const PIXEL_SIZE = 4;
        const LEVEL_0_INTERVAL = 25.0;
        const cascade_level_width = @divFloor(@as(u32, @intCast(width)), PIXEL_SIZE);
        const cascade_level_height = @divFloor(@as(u32, @intCast(height)), PIXEL_SIZE);

        // nuber of cascades is dependent on the screen size
        const diagonal = @sqrt(1280.0 * 1280.0 + 720.0 * 720.0);
        const cascades = comptime @as(
            usize,
            @intFromFloat(@ceil(std.math.log(f32, 4, diagonal / LEVEL_0_INTERVAL))),
        );

        var cascade_level_datas: [cascades][]Color = undefined;
        for (&cascade_level_datas) |*ld| {
            // The amount of elements is constant for all levels
            ld.* = frame_alloc.alloc(Color, cascade_level_width * cascade_level_height) catch
                unreachable;
            @memset(ld.*, Color.BLACK);
        }

        const Cascade = struct {
            const This = @This();
            fn data_point(
                data: []Color,
                data_width: u32,
                level: u32,
                x: usize,
                y: usize,
                index: usize,
            ) *Color {
                const row_width = std.math.pow(u32, 2, (level + 1));
                const add_rows = @divFloor(index, row_width);
                const new_index = index % row_width;
                return &data[x * row_width + (y * row_width + add_rows) * data_width + new_index];
            }

            fn avg_in_direction(
                data: []Color,
                data_width: u32,
                level: u32,
                x: usize,
                y: usize,
                index: usize,
            ) Vec4 {
                var avg: Vec4 = .{};
                var valid: f32 = 0.0;
                for (index * 4..index * 4 + 4) |i| {
                    const p = This.data_point(
                        data,
                        data_width,
                        level,
                        x,
                        y,
                        i,
                    );
                    if (p.format.a != 0) {
                        avg = avg.add(.{
                            .x = @as(f32, @floatFromInt(p.format.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(p.format.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(p.format.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(p.format.a)) / 255.0,
                        });
                        valid += 1.0;
                    }
                }
                if (valid != 0.0)
                    avg = avg.mul_f32(1.0 / valid);
                return avg;
            }
        };

        const Circle = struct {
            center: Vec2,
            radius: f32,
            color: Color,
        };

        var circles = [_]Circle{
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(width)) / 2.0,
                    .y = @as(f32, @floatFromInt(height)) / 2.0,
                },
                .radius = 25.0,
                .color = Color.ORAGE,
            },
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(width)) / 2.0,
                    .y = @as(f32, @floatFromInt(height)) / 2.0 - 100.0,
                },
                .radius = 50.0,
                .color = Color.WHITE,
            },
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(width)) / 2.0,
                    .y = @as(f32, @floatFromInt(height)) / 2.0 + 100.0,
                },
                .radius = 30.0,
                .color = Color.BLUE,
            },
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(width)) / 2.0 + 100.0,
                    .y = @as(f32, @floatFromInt(height)) / 2.0,
                },
                .radius = 40.0,
                .color = Color.BLACK,
            },
        };

        const Globals = struct {
            var camera_active: bool = false;
            var first_circle_offset: Vec2 = .{};
            var show_level: u32 = 0;
        };

        for (events) |event| {
            switch (event) {
                .Keyboard => |keyboard| {
                    switch (keyboard.key) {
                        Events.KeybordKeyScancode.@"1" => Globals.show_level = 0,
                        Events.KeybordKeyScancode.@"2" => Globals.show_level = 1,
                        Events.KeybordKeyScancode.@"3" => Globals.show_level = 2,
                        Events.KeybordKeyScancode.@"4" => Globals.show_level = 3,
                        Events.KeybordKeyScancode.@"5" => Globals.show_level = 4,
                        else => {},
                    }
                },
                .Mouse => |mouse| {
                    switch (mouse) {
                        .Button => |button| {
                            Globals.camera_active = button.type == .Pressed;
                        },
                        .Motion => |motion| {
                            if (Globals.camera_active) {
                                Globals.first_circle_offset.x += @as(f32, @floatFromInt(motion.x));
                                Globals.first_circle_offset.y += @as(f32, @floatFromInt(motion.y));
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        circles[0].center = circles[0].center.add(Globals.first_circle_offset);

        // For each cascade level go over all samples and for each angle fill corresponding
        // element in the texture with a sample of the scene.
        for (0..cascade_level_datas.len) |l| {
            const level: u32 = @intCast(l);
            const cascade_level_data = cascade_level_datas[level];
            // For each level the rays have an offset from the center of the sample and
            // a maximum distance the ray samples at. Each level must have 2 times longer ray length
            // and 2 times more granual angular stepping.
            const point_offset = (LEVEL_0_INTERVAL *
                (1.0 - @as(f32, @floatFromInt(std.math.pow(u32, 4, level))))) / -3.0;
            const ray_length = LEVEL_0_INTERVAL *
                @as(f32, @floatFromInt(std.math.pow(u32, 4, level)));
            // The amount of samples can fit in the cascade data layer is inverse proportional to
            // the level;
            // level 0 uses 4 elements (4 angles), so divisor will be 2 (for width and height)
            // level 1 uses 16 enements, so divisor will be 4
            const elements_per_row = std.math.pow(u32, 2, 1 + level);
            const elements_per_column = elements_per_row;
            const elements_total = elements_per_row * elements_per_column;
            const level_sample_point_offset = PIXEL_SIZE * std.math.pow(u32, 2, level);
            for (0..cascade_level_height / elements_per_row) |y| {
                for (0..cascade_level_width / elements_per_column) |x| {
                    const screen_position = Vec2{
                        .x = @floatFromInt(x * PIXEL_SIZE * elements_per_row +
                            level_sample_point_offset),
                        .y = @floatFromInt(y * PIXEL_SIZE * elements_per_column +
                            level_sample_point_offset),
                    };
                    // Go over all angles for a sample
                    for (0..elements_total) |i| {
                        const cascale_data_point = Cascade.data_point(
                            cascade_level_data,
                            cascade_level_width,
                            level,
                            x,
                            y,
                            i,
                        );
                        const angle = std.math.pi / @as(f32, @floatFromInt(elements_total)) +
                            @as(f32, @floatFromInt(i)) * std.math.pi /
                            @as(f32, @floatFromInt(elements_total / 2));
                        const ray_direction = Vec2{ .x = @cos(angle), .y = @sin(angle) };
                        const ray_origin = screen_position.add(ray_direction.mul_f32(point_offset));
                        for (circles) |circle| {
                            const circle_radius_2 = circle.radius * circle.radius;
                            const to_circle = circle.center.sub(ray_origin);
                            // check if the ray originates within circle
                            if (to_circle.dot(to_circle) <= circle_radius_2) {
                                cascale_data_point.* = circle.color;
                            } else {
                                const t = ray_direction.dot(to_circle);
                                if (0.0 < t) {
                                    const distance = @min(t, ray_length);
                                    const p = ray_origin.add(ray_direction.mul_f32(distance));
                                    const p_to_circle = circle.center.sub(p);
                                    if (p_to_circle.dot(p_to_circle) <= circle_radius_2) {
                                        cascale_data_point.* = circle.color;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Merge cascades in reverse order.
        // For each angle in the lower cascade sample find 4 closes angles in the 4
        // closest samples from next cascade and calculate average for those 16 angles.
        if (true) {
            for (0..cascade_level_datas.len - 1) |l| {
                const level: u32 = @intCast(cascade_level_datas.len - 2 - l);
                const next_cascade_level_data = cascade_level_datas[level + 1];
                const next_elements_per_row = std.math.pow(u32, 2, 1 + level + 1);
                const next_elements_per_column = next_elements_per_row;
                const next_height = cascade_level_height / next_elements_per_row;
                const next_width = cascade_level_width / next_elements_per_column;

                const current_cascade_level_data = cascade_level_datas[level];
                const current_elements_per_row = std.math.pow(u32, 2, 1 + level);
                const current_elements_per_column = current_elements_per_row;
                const current_elements_total =
                    current_elements_per_row * current_elements_per_column;
                const current_height = cascade_level_height / current_elements_per_row;
                const current_width = cascade_level_width / current_elements_per_column;

                for (0..current_height) |y| {
                    for (0..current_width) |x| {
                        const x_i32 = @as(i32, @intCast(x));
                        const y_i32 = @as(i32, @intCast(y));
                        const w_1 = @as(i32, @intCast(current_width - 1));
                        const h_1 = @as(i32, @intCast(current_height - 1));
                        const next_x: u32 = @min(
                            @as(u32, @intCast(@divFloor(@min(x_i32 + 1, w_1), 2))),
                            next_width - 1,
                        );
                        const prev_x: u32 = @intCast(@divFloor(@max(x_i32 - 1, 0), 2));
                        const next_y: u32 = @min(
                            @as(u32, @intCast(@divFloor(@min(y_i32 + 1, h_1), 2))),
                            next_height - 1,
                        );
                        const prev_y: u32 = @intCast(@divFloor(@max(y_i32 - 1, 0), 2));
                        log.assert(@src(), 0 <= next_x and next_x < next_width, "", .{});
                        log.assert(@src(), 0 <= prev_x and prev_x < next_width, "", .{});
                        log.assert(@src(), 0 <= next_y and next_y < next_height, "", .{});
                        log.assert(@src(), 0 <= prev_y and prev_y < next_height, "", .{});

                        for (0..current_elements_total) |i| {
                            const current_p = Cascade.data_point(
                                current_cascade_level_data,
                                cascade_level_width,
                                level,
                                x,
                                y,
                                i,
                            );

                            const p_00 = Cascade.avg_in_direction(
                                next_cascade_level_data,
                                cascade_level_width,
                                level + 1,
                                prev_x,
                                prev_y,
                                i,
                            );
                            const p_01 = Cascade.avg_in_direction(
                                next_cascade_level_data,
                                cascade_level_width,
                                level + 1,
                                prev_x,
                                next_y,
                                i,
                            );
                            const p_10 = Cascade.avg_in_direction(
                                next_cascade_level_data,
                                cascade_level_width,
                                level + 1,
                                next_x,
                                prev_y,
                                i,
                            );
                            const p_11 = Cascade.avg_in_direction(
                                next_cascade_level_data,
                                cascade_level_width,
                                level + 1,
                                next_x,
                                next_y,
                                i,
                            );

                            const x_mix: f32 = if (x % 2 == 0) 0.75 else 0.25;
                            const y_mix: f32 = if (y % 2 == 0) 0.75 else 0.25;

                            const p_00_10_mix =
                                p_00.mul_f32(x_mix).add(p_10.mul_f32(1.0 - x_mix));
                            const p_01_11_mix =
                                p_01.mul_f32(x_mix).add(p_11.mul_f32(1.0 - x_mix));
                            const avg =
                                p_00_10_mix.mul_f32(y_mix).add(p_01_11_mix.mul_f32(1.0 - y_mix));

                            const curr_r: f32 = @as(f32, @floatFromInt(current_p.format.r)) / 255.0;
                            const curr_g: f32 = @as(f32, @floatFromInt(current_p.format.g)) / 255.0;
                            const curr_b: f32 = @as(f32, @floatFromInt(current_p.format.b)) / 255.0;
                            const curr_a: f32 = @as(f32, @floatFromInt(current_p.format.a)) / 255.0;

                            current_p.format.r = @intFromFloat(std.math.clamp(
                                (avg.x * curr_a + curr_r) * 255.0,
                                0.0,
                                255.0,
                            ));
                            current_p.format.g = @intFromFloat(std.math.clamp(
                                (avg.y * curr_a + curr_g) * 255.0,
                                0.0,
                                255.0,
                            ));
                            current_p.format.b = @intFromFloat(std.math.clamp(
                                (avg.z * curr_a + curr_b) * 255.0,
                                0.0,
                                255.0,
                            ));
                            current_p.format.a = @intFromFloat(std.math.clamp(
                                (curr_a * avg.w) * 255.0,
                                0.0,
                                255.0,
                            ));
                        }
                    }
                }
            }
        }

        const level = Globals.show_level;
        const elements_per_row = std.math.pow(u32, 2, 1 + level);
        const elements_per_column = elements_per_row;

        self.soft_renderer.start_rendering();

        // For each pixel find the sample from cascade_0 it is closest to
        // and use average of values from that sample.
        if (true) {
            const hh: u32 = @intCast(height);
            const ww: u32 = @intCast(width);
            const colors = self.soft_renderer.surface_texture.as_color_slice();
            for (0..hh) |y| {
                for (0..ww) |x| {
                    const rc_x = @min(
                        @divFloor(x, PIXEL_SIZE * 2),
                        cascade_level_width / elements_per_row - 1,
                    );
                    const rc_y = @min(
                        @divFloor(y, PIXEL_SIZE * 2),
                        cascade_level_height / elements_per_column - 1,
                    );
                    var r: f32 = 0;
                    var g: f32 = 0;
                    var b: f32 = 0;
                    for (0..4) |i| {
                        const p = Cascade.data_point(
                            cascade_level_datas[0],
                            cascade_level_width,
                            0,
                            rc_x,
                            rc_y,
                            i,
                        );
                        r += @floatFromInt(p.format.r);
                        g += @floatFromInt(p.format.g);
                        b += @floatFromInt(p.format.b);
                    }
                    r /= 4.0;
                    g /= 4.0;
                    b /= 4.0;

                    colors[x + y * ww] = .{
                        .format = .{
                            .r = @intFromFloat(r),
                            .g = @intFromFloat(g),
                            .b = @intFromFloat(b),
                            .a = 0,
                        },
                    };
                }
            }
        }

        if (false) {

            // DEBUG Draw rectangles for each element in the cascade with color it managed to sample.
            const cascade_level_data = cascade_level_datas[level];
            const point_offset =
                (LEVEL_0_INTERVAL * (1.0 - @as(f32, @floatFromInt(std.math.pow(u32, 4, level))))) /
                -3.0;
            const ray_length =
                LEVEL_0_INTERVAL * @as(f32, @floatFromInt(std.math.pow(u32, 4, level)));
            const elements_total = elements_per_row * elements_per_column;
            const scale_mul = std.math.pow(u32, 2, level);
            for (0..cascade_level_height) |y| {
                for (0..cascade_level_width) |x| {
                    const screen_position = Vec2{
                        .x = @floatFromInt(x * PIXEL_SIZE + PIXEL_SIZE / 2),
                        .y = @floatFromInt(y * PIXEL_SIZE + PIXEL_SIZE / 2),
                    };
                    const color = cascade_level_data[x + y * cascade_level_width];
                    self.soft_renderer.draw_color_rect(
                        screen_position,
                        .{ .x = PIXEL_SIZE, .y = PIXEL_SIZE },
                        color,
                    );
                }
            }

            // DEBUG Draw a sample screen space position and rays it sample with
            for (0..cascade_level_height / elements_per_row) |y| {
                for (0..cascade_level_width / elements_per_column) |x| {
                    const screen_position = Vec2{
                        .x = @floatFromInt(x * PIXEL_SIZE * elements_per_row +
                            PIXEL_SIZE * scale_mul),
                        .y = @floatFromInt(y * PIXEL_SIZE * elements_per_column +
                            PIXEL_SIZE * scale_mul),
                    };

                    for (0..elements_total) |i| {
                        self.soft_renderer.draw_color_rect(
                            screen_position,
                            .{ .x = 5.0, .y = 5.0 },
                            Color.BLUE,
                        );

                        const cascale_data_point = Cascade.data_point(
                            cascade_level_data,
                            cascade_level_width,
                            level,
                            x,
                            y,
                            i,
                        );
                        if (cascale_data_point.format.a != 0) {
                            const angle = std.math.pi / @as(f32, @floatFromInt(elements_total)) +
                                @as(f32, @floatFromInt(i)) * std.math.pi /
                                @as(f32, @floatFromInt(elements_total / 2));
                            const ray_direction = Vec2{ .x = @cos(angle), .y = @sin(angle) };
                            const ray_origin = screen_position
                                .add(ray_direction.mul_f32(point_offset));
                            self.soft_renderer.draw_line(
                                ray_origin,
                                ray_origin.add(ray_direction.mul_f32(ray_length)),
                                cascale_data_point.*,
                            );
                        }
                    }
                }
            }
        }

        // DEBUG draw each circle on the scene with a rectangle.
        if (false) {
            for (circles) |circle| {
                self.soft_renderer.draw_color_rect(
                    circle.center,
                    .{ .x = circle.radius * 2.0, .y = circle.radius * 2.0 },
                    circle.color,
                );
            }
        }

        self.screen_quads.render(
            &self.soft_renderer,
            0.0,
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

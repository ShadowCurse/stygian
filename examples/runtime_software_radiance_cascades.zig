const std = @import("std");
const stygian = @import("stygian_runtime");
const build_options = stygian.build_options;

const log = stygian.log;
// This configures log level for the runtime
pub const log_options = log.Options{
    .level = .Info,
};

const Allocator = std.mem.Allocator;

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
const Vec4 = _math.Vec4;
const Mat4 = _math.Mat4;

const _objects = stygian.objects;
const Object2d = _objects.Object2d;
const Transform2d = _objects.Transform2d;

const Circle = struct {
    center: Vec2,
    radius: f32,
    color: Color,
};

const Cascade = struct {
    pub const trace = Tracing.Measurements(struct {
        data_point: Tracing.Counter,
        data_point_mut: Tracing.Counter,
        avg_in_direction: Tracing.Counter,
        sample: Tracing.Counter,
        merge: Tracing.Counter,
        draw_to_the_texture: Tracing.Counter,
    });

    data: []Color,
    data_width: u32,
    level: u32,

    point_offset: f32,
    ray_length: f32,
    elements_per_row: u32,
    elements_per_column: u32,
    elements_total: u32,
    samples_per_row: u32,
    samples_per_column: u32,
    level_sample_point_offset: u32,

    // The screen size is `width` and `height`
    // The resolution in ELEMENTS of the level_0 cascade is `width / 2` and `height / 2`
    // BUT the resolution in SAMPLES is HALF again `width / 4` and `height / 4`
    // because 4 ELEMENTS are used for 4 directions
    // For highter cascades the divisor is 16, 64 and so on
    const PIXEL_SIZE = 4;
    const LEVEL_0_INTERVAL = 25.0;

    const Self = @This();

    const CascadesNeedeResult = struct {
        width: u32,
        height: u32,
        n: u32,
    };
    fn cascades_needed(width: u32, height: u32) CascadesNeedeResult {
        const c_width = @divFloor(width, Self.PIXEL_SIZE);
        const c_height = @divFloor(height, Self.PIXEL_SIZE);

        // nuber of cascades is dependent on the screen size
        const diagonal = @sqrt(@as(f32, @floatFromInt(width * width)) +
            @as(f32, @floatFromInt(height * height)));
        const n: u32 =
            @intFromFloat(@ceil(std.math.log(f32, 4, diagonal / Self.LEVEL_0_INTERVAL)));
        return .{
            .width = c_width,
            .height = c_height,
            .n = n,
        };
    }

    fn init(allocator: Allocator, width: u32, height: u32, level: u32) !Self {
        const data = try allocator.alloc(Color, width * height);
        @memset(data, Color.BLACK);

        // const cascade_level_data = cascade_level_datas[level];
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
        const samples_per_row = width / elements_per_row;
        const samples_per_column = height / elements_per_column;
        const level_sample_point_offset = PIXEL_SIZE * std.math.pow(u32, 2, level);

        return .{
            .data = data,
            .data_width = width,
            .level = level,
            .point_offset = point_offset,
            .ray_length = ray_length,
            .elements_per_row = elements_per_row,
            .elements_per_column = elements_per_column,
            .elements_total = elements_total,
            .samples_per_row = samples_per_row,
            .samples_per_column = samples_per_column,
            .level_sample_point_offset = level_sample_point_offset,
        };
    }

    fn data_point(
        self: Self,
        x: usize,
        y: usize,
        index: usize,
    ) *Color {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        // elements are stored contigiously in memory
        return &self.data[
            x * self.elements_total +
                y * self.samples_per_row * self.elements_total +
                index
        ];
    }

    fn data_point_mut(
        self: *Self,
        x: usize,
        y: usize,
        index: usize,
    ) *Color {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        // elements are stored contigiously in memory
        return &self.data[
            x * self.elements_total +
                y * self.samples_per_row * self.elements_total +
                index
        ];
    }

    fn avg_in_direction(
        self: Self,
        x: usize,
        y: usize,
        index: usize,
    ) Vec4 {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        var avg: Vec4 = .{};
        var valid: u8 = 0.0;
        for (index * 4..index * 4 + 4) |i| {
            const p = self.data_point(
                x,
                y,
                i,
            );
            if (p.format.a != 0) {
                avg = avg.add(p.to_vec4());
                valid += 1;
            }
        }
        if (valid != 0.0)
            avg = avg.mul_f32(1.0 / @as(f32, @floatFromInt(valid)));
        return avg;
    }

    fn sample(self: Self, circles: []Circle) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        for (0..self.samples_per_column) |y| {
            for (0..self.samples_per_row) |x| {
                const screen_position = Vec2{
                    .x = @floatFromInt(x * Self.PIXEL_SIZE * self.elements_per_row +
                        self.level_sample_point_offset),
                    .y = @floatFromInt(y * Self.PIXEL_SIZE * self.elements_per_column +
                        self.level_sample_point_offset),
                };
                // Go over all angles for a sample
                for (0..self.elements_total) |i| {
                    const cascale_data_point = self.data_point(x, y, i);
                    const angle = std.math.pi / @as(f32, @floatFromInt(self.elements_total)) +
                        @as(f32, @floatFromInt(i)) * std.math.pi /
                        @as(f32, @floatFromInt(self.elements_total / 2));
                    const ray_direction = Vec2{ .x = @cos(angle), .y = @sin(angle) };
                    const ray_origin = screen_position.add(ray_direction.mul_f32(self.point_offset));
                    for (circles) |circle| {
                        const circle_radius_2 = circle.radius * circle.radius;
                        const to_circle = circle.center.sub(ray_origin);
                        // check if the ray originates within circle
                        if (to_circle.dot(to_circle) <= circle_radius_2) {
                            cascale_data_point.* = circle.color;
                        } else {
                            const t = ray_direction.dot(to_circle);
                            if (0.0 < t) {
                                const distance = @min(t, self.ray_length);
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

    fn merge(noalias current: *Self, noalias next: *Self) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const color_normalize: f32 = 1.0 / 255.0;
        const w_1 = @as(i32, @intCast(current.samples_per_row - 1));
        const h_1 = @as(i32, @intCast(current.samples_per_column - 1));
        for (0..current.samples_per_column) |y| {
            const y_mix: f32 = if (y % 2 == 0) 0.75 else 0.25;
            for (0..current.samples_per_row) |x| {
                const x_mix: f32 = if (x % 2 == 0) 0.75 else 0.25;

                const x_i32 = @as(i32, @intCast(x));
                const y_i32 = @as(i32, @intCast(y));
                const next_x: u32 = @min(
                    @as(u32, @intCast(@divFloor(@min(x_i32 + 1, w_1), 2))),
                    next.samples_per_row - 1,
                );
                const prev_x: u32 = @intCast(@divFloor(@max(x_i32 - 1, 0), 2));
                const next_y: u32 = @min(
                    @as(u32, @intCast(@divFloor(@min(y_i32 + 1, h_1), 2))),
                    next.samples_per_column - 1,
                );
                const prev_y: u32 = @intCast(@divFloor(@max(y_i32 - 1, 0), 2));

                for (0..current.elements_total) |i| {
                    const current_p = current.data_point_mut(x, y, i);

                    const p_00 = next.avg_in_direction(prev_x, prev_y, i);
                    const p_01 = next.avg_in_direction(prev_x, next_y, i);
                    const p_10 = next.avg_in_direction(next_x, prev_y, i);
                    const p_11 = next.avg_in_direction(next_x, next_y, i);

                    const p_00_10_mix =
                        p_00.mul_f32(x_mix).add(p_10.mul_f32(1.0 - x_mix));
                    const p_01_11_mix =
                        p_01.mul_f32(x_mix).add(p_11.mul_f32(1.0 - x_mix));
                    const avg_mix =
                        p_00_10_mix.mul_f32(y_mix).add(p_01_11_mix.mul_f32(1.0 - y_mix));

                    const avg = avg_mix.mul_f32(color_normalize);
                    const curr = current_p.to_vec4().mul_f32(color_normalize);

                    const current_color: Color = .{
                        .format = .{
                            .r = @intFromFloat(@min((avg.x * curr.w + curr.x) * 255.0, 255.0)),
                            .g = @intFromFloat(@min((avg.y * curr.w + curr.y) * 255.0, 255.0)),
                            .b = @intFromFloat(@min((avg.z * curr.w + curr.z) * 255.0, 255.0)),
                            .a = @intFromFloat(@min(curr.w * avg.w, 255.0)),
                        },
                    };
                    current_p.* = current_color;
                }
            }
        }
    }

    fn draw_to_the_texture(self: Self, texture: *Textures.Texture) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const colors = texture.as_color_slice();
        const px_width = Self.PIXEL_SIZE * self.elements_per_row;
        const px_heigth = Self.PIXEL_SIZE * self.elements_per_column;
        for (0..self.samples_per_column) |y| {
            for (0..self.samples_per_row) |x| {
                var r: f32 = 0;
                var g: f32 = 0;
                var b: f32 = 0;
                for (0..4) |i| {
                    const p = self.data_point(
                        x,
                        y,
                        i,
                    );
                    r += @floatFromInt(p.format.r);
                    g += @floatFromInt(p.format.g);
                    b += @floatFromInt(p.format.b);
                }
                r /= 4.0;
                g /= 4.0;
                b /= 4.0;
                const sample_avg_color: Color = .{
                    .format = .{
                        .r = @intFromFloat(r),
                        .g = @intFromFloat(g),
                        .b = @intFromFloat(b),
                        .a = 0,
                    },
                };

                var px_start = x * px_width + y * self.samples_per_row * px_width * px_heigth;
                for (0..px_heigth) |_| {
                    const row = colors[px_start .. px_start + px_width];
                    @memset(row, sample_avg_color);
                    px_start += self.samples_per_row * px_width;
                }
            }
        }
    }
};

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

        Tracing.prepare_next_frame(struct { Cascade });
        Tracing.to_screen_quads(
            struct { Cascade },
            frame_alloc,
            &self.screen_quads,
            &self.font,
            32.0,
        );
        Tracing.zero_current(struct { Cascade });

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

        const cascades_needed = Cascade.cascades_needed(@intCast(width), @intCast(height));
        var cascades: []Cascade = frame_alloc.alloc(Cascade, cascades_needed.n) catch unreachable;
        for (cascades, 0..) |*cascade, level| {
            cascade.* = Cascade.init(
                frame_alloc,
                cascades_needed.width,
                cascades_needed.height,
                @intCast(level),
            ) catch unreachable;
        }

        var circles = [_]Circle{
            .{
                .center = .{
                    .x = @as(f32, @floatFromInt(width)) / 2.0,
                    .y = @as(f32, @floatFromInt(height)) / 2.0,
                },
                .radius = 25.0,
                .color = Color.ORAGNE,
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
                .color = Color.NONE,
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
        for (cascades) |*cascade| {
            cascade.sample(&circles);
        }

        // Merge cascades in reverse order.
        // For each angle in the lower cascade sample find 4 closes angles in the 4
        // closest samples from next cascade and calculate average for those 16 angles.
        if (true) {
            for (0..cascades.len - 1) |l| {
                const level: u32 = @intCast(cascades.len - 2 - l);
                const next_cascade = &cascades[level + 1];
                const current_cascade = &cascades[level];
                current_cascade.merge(next_cascade);
            }
        }

        const level = Globals.show_level;
        const elements_per_row = std.math.pow(u32, 2, 1 + level);
        const elements_per_column = elements_per_row;

        self.soft_renderer.start_rendering();

        // For each pixel find the sample from cascade_0 it is closest to
        // and use average of values from that sample.
        if (true) {
            cascades[0].draw_to_the_texture(&self.soft_renderer.surface_texture);
        }

        if (false) {
            // DEBUG Draw rectangles for each element in the cascade with color it managed to sample.
            const cascade = &cascades[level];
            const point_offset =
                (Cascade.LEVEL_0_INTERVAL * (1.0 - @as(f32, @floatFromInt(std.math.pow(u32, 4, level))))) /
                -3.0;
            const ray_length =
                Cascade.LEVEL_0_INTERVAL * @as(f32, @floatFromInt(std.math.pow(u32, 4, level)));
            const elements_total = elements_per_row * elements_per_column;
            const scale_mul = std.math.pow(u32, 2, level);
            for (0..cascades_needed.height) |y| {
                for (0..cascades_needed.width) |x| {
                    const screen_position = Vec2{
                        .x = @floatFromInt(x * Cascade.PIXEL_SIZE + Cascade.PIXEL_SIZE / 2),
                        .y = @floatFromInt(y * Cascade.PIXEL_SIZE + Cascade.PIXEL_SIZE / 2),
                    };
                    const color = cascade.data[x + y * cascades_needed.width];
                    self.soft_renderer.draw_color_rect(
                        screen_position,
                        .{ .x = Cascade.PIXEL_SIZE, .y = Cascade.PIXEL_SIZE },
                        color,
                    );
                }
            }

            // DEBUG Draw a sample screen space position and rays it sample with
            for (0..cascades_needed.height / elements_per_row) |y| {
                for (0..cascades_needed.width / elements_per_column) |x| {
                    const screen_position = Vec2{
                        .x = @floatFromInt(x * Cascade.PIXEL_SIZE * elements_per_row +
                            Cascade.PIXEL_SIZE * scale_mul),
                        .y = @floatFromInt(y * Cascade.PIXEL_SIZE * elements_per_column +
                            Cascade.PIXEL_SIZE * scale_mul),
                    };

                    for (0..elements_total) |i| {
                        self.soft_renderer.draw_color_rect(
                            screen_position,
                            .{ .x = 5.0, .y = 5.0 },
                            Color.BLUE,
                        );

                        const cascale_data_point = cascade.data_point(
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

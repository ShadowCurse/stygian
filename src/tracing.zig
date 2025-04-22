const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");

const Text = @import("text.zig");
const Font = @import("font.zig");
const ScreenQuads = @import("screen_quads.zig");

pub const Options = struct {
    max_measurements: u32 = 0,
    enabled: bool = false,
};

const root = @import("root");
pub const options: Options = if (@hasDecl(root, "tracing_options"))
    root.tracing_options
else
    .{};

pub var current_measurement: u32 = 0;
pub var total_time: [options.max_measurements]i128 = undefined;
pub var total_avg: i128 = 0;

pub fn prepare_next_frame(comptime all_perf_types: type) void {
    if (!options.enabled) return;

    const tt = calculate_total_time(all_perf_types);
    const old = total_time[current_measurement];
    total_time[current_measurement] = tt;
    total_avg += @divFloor(tt - old, options.max_measurements);

    current_measurement = (current_measurement + 1) % 256;
    zero_current(all_perf_types);
}
pub fn calculate_total_time(comptime all_perf_types: type) i128 {
    if (!options.enabled) return;

    var total: i128 = 0;
    const fields = comptime @typeInfo(all_perf_types).@"struct".fields;
    inline for (fields) |field| {
        const trace = field.type.trace;
        const data = trace.previous();
        const data_fields = comptime @typeInfo(@TypeOf(data.*)).@"struct".fields;
        inline for (data_fields) |df| {
            total += @field(data.*, df.name).ns;
        }
    }
    return total;
}
pub fn zero_current(comptime all_perf_types: type) void {
    if (!options.enabled) return;

    const fields = comptime @typeInfo(all_perf_types).@"struct".fields;
    inline for (fields) |field| {
        const trace = field.type.trace;
        trace.zero_current();
    }
}

pub const Counter = struct {
    ns: i128 = 0,
    count: u32 = 0,

    pub fn avg(self: Counter) i128 {
        if (self.count != 0)
            return @divTrunc(self.ns, @as(i128, self.count))
        else
            return 0;
    }
};

pub fn Measurements(comptime T: type) type {
    return if (!options.enabled)
        struct {
            pub fn start() void {}
            pub fn end(comptime src: std.builtin.SourceLocation, _: void) void {
                _ = src;
            }
        }
    else
        struct {
            pub var measurements: [options.max_measurements]T =
                std.mem.zeroes([options.max_measurements]T);

            pub const Start = struct {
                start_ns: i128,
            };

            pub fn start() Start {
                return .{
                    .start_ns = std.time.nanoTimestamp(),
                };
            }
            pub fn end(
                comptime src: std.builtin.SourceLocation,
                s: Start,
            ) void {
                const m = &@field(measurements[current_measurement], src.fn_name);
                m.ns += std.time.nanoTimestamp() - s.start_ns;
                m.count += 1;
            }

            pub fn zero_current() void {
                const m = &measurements[current_measurement];
                const fields = comptime @typeInfo(T).@"struct".fields;
                inline for (fields) |field| {
                    @field(m, field.name) = .{};
                }
            }

            pub fn sum_all() T {
                var sum: T = std.mem.zeroes(T);
                const fields = comptime @typeInfo(T).@"struct".fields;
                for (&measurements) |*m| {
                    inline for (fields) |field| {
                        @field(sum, field.name).ns += @field(m.*, field.name).ns;
                        @field(sum, field.name).count += @field(m.*, field.name).count;
                    }
                }
                return sum;
            }

            pub fn previous() *T {
                const p = if (current_measurement == 0)
                    options.max_measurements - 1
                else
                    current_measurement - 1;
                return &measurements[p];
            }

            pub fn current() *T {
                return &measurements[current_measurement];
            }
        };
}

pub fn to_screen_quads(
    comptime all_traced_types: type,
    allocator: Allocator,
    screen_quads: *ScreenQuads,
    font: *const Font,
    size: f32,
) void {
    if (!options.enabled) return;

    var y: f32 = size;
    const y_advance: f32 = size;
    const x: f32 = size;

    const pt_fields = comptime @typeInfo(all_traced_types).@"struct".fields;
    inline for (pt_fields) |ptf| {
        const trace = ptf.type.trace;
        const measurement = trace.previous();
        const sum = trace.sum_all();

        const m_fields = comptime @typeInfo(@TypeOf(measurement.*)).@"struct".fields;
        inline for (m_fields) |mf| {
            const field_avg = @field(sum, mf.name).avg();
            const m = @field(measurement.*, mf.name);
            const name_width = @min(mf.name.len, 20);
            const s =
                std.fmt.allocPrint(
                    allocator,
                    "{s: <20}: f_n: {d: >4}, f_avg: {d: >9}ns, t_avg: {d: >9}ns",
                    .{ mf.name[0..name_width], m.count, m.avg(), field_avg },
                ) catch |e| {
                    log.warn(@src(), "Cannot formant performance measurement. Error: {}", .{e});
                    return;
                };

            const text = Text.init(
                font,
                s,
                size,
                .{
                    .x = x,
                    .y = y,
                },
                0.0,
                .{},
                null,
                .{ .center = false },
            );
            text.to_screen_quads(allocator, screen_quads);
            y += y_advance;
        }
    }
}

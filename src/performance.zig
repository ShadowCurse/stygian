const std = @import("std");
const Allocator = std.mem.Allocator;

const log = @import("log.zig");

const Font = @import("font.zig").Font;
const ScreenQuads = @import("screen_quads.zig");

pub const MAX_MEASUREMENTS = 256;

pub var current_measurement: u32 = 0;
pub var total_time: [MAX_MEASUREMENTS]i128 = undefined;
pub var total_avg: i128 = 0;

pub fn prepare_next_frame(comptime all_perf_types: type) void {
    const tt = calculate_total_time(all_perf_types);
    const old = total_time[current_measurement];
    total_time[current_measurement] = tt;
    total_avg += @divFloor(tt - old, MAX_MEASUREMENTS);

    current_measurement = (current_measurement + 1) % 256;

    const fields = comptime @typeInfo(all_perf_types).Struct.fields;
    inline for (fields) |field| {
        const perf = field.type.perf;
        perf.zero_current();
    }
}
pub fn calculate_total_time(comptime all_perf_types: type) i128 {
    var total: i128 = 0;
    const fields = comptime @typeInfo(all_perf_types).Struct.fields;
    inline for (fields) |field| {
        const perf = field.type.perf;
        const data = perf.previous();
        const data_fields = comptime @typeInfo(@TypeOf(data.*)).Struct.fields;
        inline for (data_fields) |df| {
            total += @field(data.*, df.name).ns;
        }
    }
    return total;
}
pub fn zero_current(comptime all_perf_types: type) void {
    const fields = comptime @typeInfo(all_perf_types).Struct.fields;
    inline for (fields) |field| {
        const perf = field.type.perf;
        perf.zero_current();
    }
}

pub const Fn = struct {
    ns: i128 = 0,
    count: u32 = 0,

    pub fn avg(self: Fn) i128 {
        return @divTrunc(self.ns, @as(i128, self.count));
    }
};

pub fn Measurements(comptime T: type) type {
    return struct {
        pub var measurements: [MAX_MEASUREMENTS]T = undefined;

        pub fn start(
            comptime src: std.builtin.SourceLocation,
        ) void {
            const m = &@field(measurements[current_measurement], src.fn_name);
            m.ns -= std.time.nanoTimestamp();
            m.count += 1;
        }
        pub fn end(
            comptime src: std.builtin.SourceLocation,
        ) void {
            const m = &@field(measurements[current_measurement], src.fn_name);
            m.ns += std.time.nanoTimestamp();
        }

        pub fn zero_current() void {
            const m = &measurements[current_measurement];
            const fields = comptime @typeInfo(T).Struct.fields;
            inline for (fields) |field| {
                @field(m, field.name) = .{};
            }
        }

        pub fn previous() *T {
            const p = if (current_measurement == 0)
                MAX_MEASUREMENTS - 1
            else
                current_measurement - 1;
            return &measurements[p];
        }

        pub fn current() *T {
            return &measurements[current_measurement];
        }
    };
}

pub fn draw_perf(
    comptime all_perf_types: type,
    allocator: Allocator,
    screen_quads: *ScreenQuads,
    font: *const Font,
) void {
    var perf_y: f32 = font.size;
    const perf_y_advance: f32 = font.size;
    const perf_x: f32 = font.size;

    const pt_fields = comptime @typeInfo(all_perf_types).Struct.fields;
    inline for (pt_fields) |ptf| {
        const perf = ptf.type.perf;
        const measurement = perf.previous();

        const m_fields = comptime @typeInfo(@TypeOf(measurement.*)).Struct.fields;
        inline for (m_fields) |mf| {
            const m = @field(measurement.*, mf.name);
            if (m.count != 0) {
                const s =
                    std.fmt.allocPrint(
                    allocator,
                    "{s}: n: {}, avg: {}ns",
                    .{ mf.name, m.count, m.avg() },
                ) catch |e| {
                    log.warn(@src(), "Cannot formant performance measurement. Error: {}", .{e});
                    return;
                };
                screen_quads.add_text(
                    font,
                    s,
                    .{
                        .x = perf_x,
                        .y = perf_y,
                        .z = 2.0,
                    },
                    false,
                );
                perf_y += perf_y_advance;
            }
        }
    }

    const p = if (current_measurement == 0)
        MAX_MEASUREMENTS - 1
    else
        current_measurement - 1;

    const s =
        std.fmt.allocPrint(
        allocator,
        "Total: {}ns avg: {}ns",
        .{ total_time[p], total_avg },
    ) catch |e| {
        log.warn(@src(), "Cannot formant performance measurement. Error: {}", .{e});
        return;
    };
    screen_quads.add_text(
        font,
        s,
        .{
            .x = perf_x,
            .y = perf_y,
            .z = 2.0,
        },
        false,
    );
}

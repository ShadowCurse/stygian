const stygian = @import("stygian_platform");
const log = stygian.log;

// This configures log level for the platform
pub const log_options = log.Options{
    .level = .Info,
};

const platform_start = stygian.platform.start.platform_start;
pub fn main() !void {
    try platform_start();
}

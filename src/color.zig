pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const GREY = Color{ .r = 69, .g = 69, .b = 69, .a = 255 };
    pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
};

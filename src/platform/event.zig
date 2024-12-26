const builtin = @import("builtin");
const log = @import("../log.zig");
const sdl = @import("../bindings/sdl.zig");

pub const MAX_EVENTS = 8;

pub fn get(events: []Event) []Event {
    var sdl_events: [MAX_EVENTS]sdl.SDL_Event = undefined;
    const filled_sdl_events = if (builtin.os.tag == .emscripten) blk: {
        var n: u32 = 0;
        while (sdl.SDL_PollEvent(&sdl_events[n]) != 0 and
            n < sdl_events.len) : (n += 1)
        {}
        break :blk sdl_events[0..n];
    } else blk: {
        sdl.SDL_FlushEvents(
            sdl.SDL_FIRSTEVENT,
            sdl.SDL_LASTEVENT,
        );
        sdl.SDL_PumpEvents();
        const num_events = sdl.SDL_PeepEvents(
            &sdl_events,
            @intCast(sdl_events.len),
            sdl.SDL_PEEKEVENT,
            sdl.SDL_FIRSTEVENT,
            sdl.SDL_LASTEVENT,
        );

        break :blk if (num_events < 0) e: {
            log.err(@src(), "Cannot get SDL events: {s}", .{sdl.SDL_GetError()});
            break :e sdl_events[0..0];
        } else sdl_events[0..@intCast(num_events)];
    };
    const to_fill_events = events[0..filled_sdl_events.len];
    for (filled_sdl_events, to_fill_events) |*sdl_event, *event| {
        switch (sdl_event.type) {
            sdl.SDL_QUIT => {
                log.debug(@src(), "Got QUIT", .{});
                event.* = .Quit;
            },
            // Skip this as it is triggered on key presses
            sdl.SDL_TEXTINPUT => {},
            sdl.SDL_KEYDOWN => {
                if (builtin.os.tag == .emscripten) {
                    const key: KeybordKeyScancode = @enumFromInt(sdl_event.key.keysym.sym);
                    log.debug(@src(), "Got KEYDOWN event for key: {}", .{key});
                    event.* = .{
                        .Keyboard = .{
                            .type = .Pressed,
                            .key = key,
                        },
                    };
                } else {
                    const key: KeybordKeyScancode = @enumFromInt(sdl_event.key.keysym.scancode);
                    log.debug(@src(), "Got KEYDOWN event for key: {}", .{key});
                    event.* = .{
                        .Keyboard = .{
                            .type = .Pressed,
                            .key = key,
                        },
                    };
                }
            },
            sdl.SDL_KEYUP => {
                if (builtin.os.tag == .emscripten) {
                    const key: KeybordKeyScancode = @enumFromInt(sdl_event.key.keysym.sym);
                    log.debug(@src(), "Got KEYUP event for key: {}", .{key});
                    event.* = .{
                        .Keyboard = .{
                            .type = .Released,
                            .key = @enumFromInt(sdl_event.key.keysym.sym),
                        },
                    };
                } else {
                    const key: KeybordKeyScancode = @enumFromInt(sdl_event.key.keysym.scancode);
                    log.debug(@src(), "Got KEYUP event for key: {}", .{key});
                    event.* = .{
                        .Keyboard = .{
                            .type = .Released,
                            .key = key,
                        },
                    };
                }
            },
            sdl.SDL_MOUSEMOTION => {
                log.debug(
                    @src(),
                    "Got MOUSEMOTION event with x: {}, y: {}",
                    .{ sdl_event.motion.xrel, sdl_event.motion.yrel },
                );
                event.* = .{
                    .Mouse = .{
                        .Motion = .{
                            .x = sdl_event.motion.xrel,
                            .y = sdl_event.motion.yrel,
                        },
                    },
                };
            },
            sdl.SDL_MOUSEBUTTONDOWN => {
                log.debug(
                    @src(),
                    "Got MOUSEBUTTONDOWN event for key: {}",
                    .{sdl_event.button.button},
                );
                event.* = .{
                    .Mouse = .{
                        .Button = .{
                            .type = .Pressed,
                            .key = sdl_event.button.button,
                        },
                    },
                };
            },
            sdl.SDL_MOUSEBUTTONUP => {
                log.debug(
                    @src(),
                    "Got MOUSEBUTTONUP event for key: {}",
                    .{sdl_event.button.button},
                );
                event.* = .{
                    .Mouse = .{
                        .Button = .{
                            .type = .Released,
                            .key = sdl_event.button.button,
                        },
                    },
                };
            },
            sdl.SDL_MOUSEWHEEL => {
                if (builtin.os.tag == .emscripten) {
                    log.debug(
                        @src(),
                        "Got MOUSEWHEEL event with value: {}",
                        .{sdl_event.wheel.y},
                    );
                    event.* = .{
                        .Mouse = .{
                            .Wheel = .{
                                .amount = @floatFromInt(sdl_event.wheel.y),
                            },
                        },
                    };
                } else {
                    log.debug(
                        @src(),
                        "Got MOUSEWHEEL event with value: {}",
                        .{sdl_event.wheel.preciseY},
                    );
                    event.* = .{
                        .Mouse = .{
                            .Wheel = .{
                                .amount = sdl_event.wheel.preciseY,
                            },
                        },
                    };
                }
            },
            else => {
                log.warn(@src(), "Got unrecognised SDL event type: {}", .{sdl_event.type});
            },
        }
    }
    return to_fill_events;
}

pub const Event = union(enum) {
    Quit: void,
    Keyboard: KeybordEvent,
    Mouse: MouseEvent,
};

pub const KeyEventType = enum {
    Pressed,
    Released,
};

pub const MouseEvent = union(enum) {
    Motion: MouseMotion,
    Button: MouseButton,
    Wheel: MouseWheel,
};

pub const MouseMotion = struct {
    x: i32,
    y: i32,
};
pub const MouseButton = struct {
    type: KeyEventType,
    key: u8,
};
pub const MouseWheel = struct {
    // Amount scrolled
    amount: f32,
};

pub const KeybordEvent = struct {
    type: KeyEventType,
    key: KeybordKeyScancode,
};

// Based on SDL2 key scancodes
pub const KeybordKeyScancode = enum(u32) {
    UNKNOWN = 0,
    A = 4,
    B = 5,
    C = 6,
    D = 7,
    E = 8,
    F = 9,
    G = 10,
    H = 11,
    I = 12,
    J = 13,
    K = 14,
    L = 15,
    M = 16,
    N = 17,
    O = 18,
    P = 19,
    Q = 20,
    R = 21,
    S = 22,
    T = 23,
    U = 24,
    V = 25,
    W = 26,
    X = 27,
    Y = 28,
    Z = 29,
    @"1" = 30,
    @"2" = 31,
    @"3" = 32,
    @"4" = 33,
    @"5" = 34,
    @"6" = 35,
    @"7" = 36,
    @"8" = 37,
    @"9" = 38,
    @"0" = 39,
    RETURN = 40,
    ESCAPE = 41,
    BACKSPACE = 42,
    TAB = 43,
    SPACE = 44,
    MINUS = 45,
    EQUALS = 46,
    LEFTBRACKET = 47,
    RIGHTBRACKET = 48,
    BACKSLASH = 49,
    NONUSHASH = 50,
    SEMICOLON = 51,
    APOSTROPHE = 52,
    GRAVE = 53,
    COMMA = 54,
    PERIOD = 55,
    SLASH = 56,
    CAPSLOCK = 57,
    F1 = 58,
    F2 = 59,
    F3 = 60,
    F4 = 61,
    F5 = 62,
    F6 = 63,
    F7 = 64,
    F8 = 65,
    F9 = 66,
    F10 = 67,
    F11 = 68,
    F12 = 69,
    PRINTSCREEN = 70,
    SCROLLLOCK = 71,
    PAUSE = 72,
    INSERT = 73,
    HOME = 74,
    PAGEUP = 75,
    DELETE = 76,
    END = 77,
    PAGEDOWN = 78,
    RIGHT = 79,
    LEFT = 80,
    DOWN = 81,
    UP = 82,
    NUMLOCKCLEAR = 83,
    KP_DIVIDE = 84,
    KP_MULTIPLY = 85,
    KP_MINUS = 86,
    KP_PLUS = 87,
    KP_ENTER = 88,
    KP_1 = 89,
    KP_2 = 90,
    KP_3 = 91,
    KP_4 = 92,
    KP_5 = 93,
    KP_6 = 94,
    KP_7 = 95,
    KP_8 = 96,
    KP_9 = 97,
    KP_0 = 98,
    KP_PERIOD = 99,
    NONUSBACKSLASH = 100,
    APPLICATION = 101,
    POWER = 102,
    KP_EQUALS = 103,
    F13 = 104,
    F14 = 105,
    F15 = 106,
    F16 = 107,
    F17 = 108,
    F18 = 109,
    F19 = 110,
    F20 = 111,
    F21 = 112,
    F22 = 113,
    F23 = 114,
    F24 = 115,
    EXECUTE = 116,
    HELP = 117,
    MENU = 118,
    SELECT = 119,
    STOP = 120,
    AGAIN = 121,
    UNDO = 122,
    CUT = 123,
    COPY = 124,
    PASTE = 125,
    FIND = 126,
    MUTE = 127,
    VOLUMEUP = 128,
    VOLUMEDOWN = 129,
    KP_COMMA = 133,
    KP_EQUALSAS400 = 134,
    INTERNATIONAL1 = 135,
    INTERNATIONAL2 = 136,
    INTERNATIONAL3 = 137,
    INTERNATIONAL4 = 138,
    INTERNATIONAL5 = 139,
    INTERNATIONAL6 = 140,
    INTERNATIONAL7 = 141,
    INTERNATIONAL8 = 142,
    INTERNATIONAL9 = 143,
    LANG1 = 144,
    LANG2 = 145,
    LANG3 = 146,
    LANG4 = 147,
    LANG5 = 148,
    LANG6 = 149,
    LANG7 = 150,
    LANG8 = 151,
    LANG9 = 152,
    ALTERASE = 153,
    SYSREQ = 154,
    CANCEL = 155,
    CLEAR = 156,
    PRIOR = 157,
    RETURN2 = 158,
    SEPARATOR = 159,
    OUT = 160,
    OPER = 161,
    CLEARAGAIN = 162,
    CRSEL = 163,
    EXSEL = 164,
    KP_00 = 176,
    KP_000 = 177,
    THOUSANDSSEPARATOR = 178,
    DECIMALSEPARATOR = 179,
    CURRENCYUNIT = 180,
    CURRENCYSUBUNIT = 181,
    KP_LEFTPAREN = 182,
    KP_RIGHTPAREN = 183,
    KP_LEFTBRACE = 184,
    KP_RIGHTBRACE = 185,
    KP_TAB = 186,
    KP_BACKSPACE = 187,
    KP_A = 188,
    KP_B = 189,
    KP_C = 190,
    KP_D = 191,
    KP_E = 192,
    KP_F = 193,
    KP_XOR = 194,
    KP_POWER = 195,
    KP_PERCENT = 196,
    KP_LESS = 197,
    KP_GREATER = 198,
    KP_AMPERSAND = 199,
    KP_DBLAMPERSAND = 200,
    KP_VERTICALBAR = 201,
    KP_DBLVERTICALBAR = 202,
    KP_COLON = 203,
    KP_HASH = 204,
    KP_SPACE = 205,
    KP_AT = 206,
    KP_EXCLAM = 207,
    KP_MEMSTORE = 208,
    KP_MEMRECALL = 209,
    KP_MEMCLEAR = 210,
    KP_MEMADD = 211,
    KP_MEMSUBTRACT = 212,
    KP_MEMMULTIPLY = 213,
    KP_MEMDIVIDE = 214,
    KP_PLUSMINUS = 215,
    KP_CLEAR = 216,
    KP_CLEARENTRY = 217,
    KP_BINARY = 218,
    KP_OCTAL = 219,
    KP_DECIMAL = 220,
    KP_HEXADECIMAL = 221,
    LCTRL = 224,
    LSHIFT = 225,
    LALT = 226,
    LGUI = 227,
    RCTRL = 228,
    RSHIFT = 229,
    RALT = 230,
    RGUI = 231,
    MODE = 257,
    AUDIONEXT = 258,
    AUDIOPREV = 259,
    AUDIOSTOP = 260,
    AUDIOPLAY = 261,
    AUDIOMUTE = 262,
    MEDIASELECT = 263,
    WWW = 264,
    MAIL = 265,
    CALCULATOR = 266,
    COMPUTER = 267,
    AC_SEARCH = 268,
    AC_HOME = 269,
    AC_BACK = 270,
    AC_FORWARD = 271,
    AC_STOP = 272,
    AC_REFRESH = 273,
    AC_BOOKMARKS = 274,
    BRIGHTNESSDOWN = 275,
    BRIGHTNESSUP = 276,
    DISPLAYSWITCH = 277,
    KBDILLUMTOGGLE = 278,
    KBDILLUMDOWN = 279,
    KBDILLUMUP = 280,
    EJECT = 281,
    SLEEP = 282,
    APP1 = 283,
    APP2 = 284,
    AUDIOREWIND = 285,
    AUDIOFASTFORWARD = 286,
    SOFTLEFT = 287,
    SOFTRIGHT = 288,
    CALL = 289,
    ENDCALL = 290,
};

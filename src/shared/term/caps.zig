const std = @import("std");
const builtin = @import("builtin");

// Import the ZON capabilities database (compiled at comptime)
const cfg = @import("termcaps.zon");

pub const WidthMethod = enum { grapheme, wcwidth };

// Terminal size information
pub const TerminalSize = struct {
    width: u16,
    height: u16,
};

// Mouse capability information
pub const MouseCapabilities = struct {
    // Basic mouse support
    supports_x10_mouse: bool = false,
    supports_vt200_mouse: bool = false,
    supports_button_event: bool = false,
    supports_any_event: bool = false,

    // Extended mouse protocols
    supports_sgr_mouse: bool = false,
    supports_urxvt_mouse: bool = false,
    supports_pixel_position: bool = false,
    supports_utf8_mouse: bool = false,

    // Additional features
    supports_focus_events: bool = false,
    supports_alternate_scroll: bool = false,
    supports_bracketed_paste: bool = false,

    // Terminal-specific capabilities
    supports_kitty_mouse: bool = false,
    supports_iterm2_mouse: bool = false,
    supports_wezterm_mouse: bool = false,

    // Maximum coordinate values
    max_x_coordinate: u32 = 223, // Default X10 limit (223)
    max_y_coordinate: u32 = 223, // Default X10 limit (223)

    // Detected mouse protocol preference
    preferred_protocol: MouseProtocol = .none,
};

// Mouse protocol types in order of preference
pub const MouseProtocol = enum {
    none,
    x10, // Most basic, limited to 223x223
    normal, // VT200 style
    utf8, // UTF-8 encoding for coordinates
    urxvt, // urxvt extended format
    sgr, // SGR format (no coordinate limits)
    pixel, // Pixel-based positioning
    kitty, // Kitty-specific protocol
};

// Query types for advanced terminal detection
pub const QueryType = enum {
    /// Device Attributes queries
    primary_device_attributes, // DA1 - Basic terminal identification
    secondary_device_attributes, // DA2 - Terminal version and hardware
    tertiary_device_attributes, // DA3 - Unit ID (rarely supported)

    /// Terminal size and positioning
    cursor_position, // CPR - Current cursor position
    window_size_chars, // Window size in characters
    window_size_pixels, // Window size in pixels

    /// Color support queries
    color_support_test, // Test if terminal supports specific color modes
    background_color, // Request current background color
    foreground_color, // Request current foreground color

    /// Feature support tests
    bracketed_paste_test, // Test bracketed paste support
    focus_events_test, // Test focus events support
    synchronized_output_test, // Test synchronized update support
    hyperlink_test, // Test hyperlink support

    /// Terminal-specific queries
    kitty_version, // Kitty terminal version query
    iterm2_version, // iTerm2 proprietary queries
    wezterm_version, // WezTerm version query

    /// Clipboard queries
    clipboard_contents, // Request clipboard contents (if supported)

    /// Image support tests
    sixel_support_test, // Test Sixel graphics support
    kitty_graphics_test, // Test Kitty graphics protocol
    iterm2_inline_images_test, // Test iTerm2 inline images

    /// Mouse mode queries (DECRQM)
    mouse_x10_query, // Query X10 mouse mode
    mouse_vt200_query, // Query VT200 mouse mode
    mouse_button_event_query, // Query button event mode
    mouse_any_event_query, // Query any event mode
    mouse_sgr_query, // Query SGR mouse mode
    mouse_urxvt_query, // Query urxvt mouse mode
    mouse_pixel_query, // Query pixel position mode
    mouse_focus_query, // Query focus event mode
    mouse_alternate_scroll_query, // Query alternate scroll mode
};

// Query response information
pub const QueryResponse = struct {
    query_type: QueryType,
    raw_response: []const u8,
    parsed_data: Response,
    timestamp: i64, // When the response was received
};

// Parsed data from query responses
pub const Response = union(enum) {
    device_attributes: struct {
        primary_da: ?[]const u8 = null,
        secondary_da: ?[]const u8 = null,
        tertiary_da: ?[]const u8 = null,
    },

    position: struct {
        row: u16,
        col: u16,
    },

    size: struct {
        width: u16,
        height: u16,
    },

    color: struct {
        r: u8,
        g: u8,
        b: u8,
    },

    version_info: struct {
        version: []const u8,
        build: ?[]const u8 = null,
    },

    boolean_result: bool,
    text_data: []const u8,
    raw_data: []const u8,
};

// Error types for terminal query operations
pub const QueryError = error{
    InvalidResponse,
    ResponseTimeout,
    ReadError,
    WriteError,
    BufferOverflow,
    TerminalNotSupported,
    RawModeError,
    MalformedSequence,
};

pub const TermCaps = struct {
    supportsTruecolor: bool,
    supportsHyperlinkOsc8: bool,
    supportsClipboardOsc52: bool,
    supportsWorkingDirOsc7: bool,
    supportsTitleOsc012: bool,
    supportsNotifyOsc9: bool,
    supportsFinalTermOsc133: bool,
    // iTerm2 proprietary extensions (OSC 1337)
    supportsITerm2Osc1337: bool,
    // xterm default color controls: OSC 10/11/12 (foreground/background/cursor)
    supportsColorOsc10_12: bool,
    supportsKittyKeyboard: bool,
    supportsKittyGraphics: bool,
    supportsSixel: bool,
    supportsModifyOtherKeys: bool,
    supportsXtwinops: bool,
    supportsBracketedPaste: bool,
    supportsFocusEvents: bool,
    supportsSgrMouse: bool,
    supportsSgrPixelMouse: bool,
    supportsLightDarkReport: bool,
    // Linux console palette control (OSC P and OSC ]R)
    supportsLinuxPaletteOscP: bool,
    // Device attributes and version queries (DA1/DA2/DA3, XTVERSION)
    supportsDeviceAttributes: bool,
    supportsCursorStyle: bool,
    supportsCursorPositionReport: bool,
    supportsPointerShape: bool,
    needsTmuxPassthrough: bool,
    needsScreenPassthrough: bool,
    screenChunkLimit: u16,
    widthMethod: WidthMethod,
};

pub const Program = enum {
    Kitty,
    WezTerm,
    ITerm2,
    AppleTerminal,
    VTE,
    Alacritty,
    Ghostty,
    Konsole,
    Xterm,
    VSCode,
    WindowsTerminal,
    LinuxConsole,
    Unknown,
};

fn defaultsCaps() TermCaps {
    const d = cfg.defaults;
    return TermCaps{
        .supportsTruecolor = d.supports_truecolor,
        .supportsHyperlinkOsc8 = d.supports_hyperlink_osc8,
        .supportsClipboardOsc52 = d.supports_clipboard_osc52,
        .supportsWorkingDirOsc7 = d.supports_working_dir_osc7,
        .supportsTitleOsc012 = d.supports_title_osc012,
        .supportsNotifyOsc9 = d.supports_notify_osc9,
        .supportsFinalTermOsc133 = d.supports_finalterm_osc133,
        .supportsITerm2Osc1337 = if (@hasField(@TypeOf(d), "supports_iterm2_osc1337")) d.supports_iterm2_osc1337 else false,
        .supportsColorOsc10_12 = d.supports_color_osc10_12,
        .supportsKittyKeyboard = d.supports_kitty_keyboard,
        .supportsKittyGraphics = d.supports_kitty_graphics,
        .supportsSixel = d.supports_sixel,
        .supportsModifyOtherKeys = d.supports_modify_other_keys,
        .supportsXtwinops = d.supports_xtwinops,
        .supportsBracketedPaste = d.supports_bracketed_paste,
        .supportsFocusEvents = d.supports_focus_events,
        .supportsSgrMouse = d.supports_sgr_mouse,
        .supportsSgrPixelMouse = d.supports_sgr_pixel_mouse,
        .supportsLightDarkReport = d.supports_lightdark_report,
        .supportsLinuxPaletteOscP = if (@hasField(@TypeOf(d), "supports_linux_palette_oscp")) d.supports_linux_palette_oscp else false,
        .supportsDeviceAttributes = if (@hasField(@TypeOf(d), "supports_device_attributes")) d.supports_device_attributes else true,
        .supportsCursorStyle = if (@hasField(@TypeOf(d), "supports_cursor_style")) d.supports_cursor_style else true,
        .supportsCursorPositionReport = if (@hasField(@TypeOf(d), "supports_cursor_position_report")) d.supports_cursor_position_report else true,
        .supportsPointerShape = if (@hasField(@TypeOf(d), "supports_pointer_shape")) d.supports_pointer_shape else false,
        .needsTmuxPassthrough = d.needs_tmux_passthrough,
        .needsScreenPassthrough = d.needs_screen_passthrough,
        .screenChunkLimit = @intCast(d.screen_chunk_limit),
        .widthMethod = if (std.mem.eql(u8, d.width_method, "wcwidth")) .wcwidth else .grapheme,
    };
}

fn overlayCaps(comptime ProgObj: type, prog: ProgObj, caps: *TermCaps) void {
    // Update each field if present in program override
    if (@hasField(ProgObj, "supports_truecolor")) caps.supportsTruecolor = prog.supports_truecolor;
    if (@hasField(ProgObj, "supports_hyperlink_osc8")) caps.supportsHyperlinkOsc8 = prog.supports_hyperlink_osc8;
    if (@hasField(ProgObj, "supports_clipboard_osc52")) caps.supportsClipboardOsc52 = prog.supports_clipboard_osc52;
    if (@hasField(ProgObj, "supports_working_dir_osc7")) caps.supportsWorkingDirOsc7 = prog.supports_working_dir_osc7;
    if (@hasField(ProgObj, "supports_title_osc012")) caps.supportsTitleOsc012 = prog.supports_title_osc012;
    if (@hasField(ProgObj, "supports_notify_osc9")) caps.supportsNotifyOsc9 = prog.supports_notify_osc9;
    if (@hasField(ProgObj, "supports_finalterm_osc133")) caps.supportsFinalTermOsc133 = prog.supports_finalterm_osc133;
    if (@hasField(ProgObj, "supports_iterm2_osc1337")) caps.supportsITerm2Osc1337 = prog.supports_iterm2_osc1337;
    if (@hasField(ProgObj, "supports_color_osc10_12")) caps.supportsColorOsc10_12 = prog.supports_color_osc10_12;
    if (@hasField(ProgObj, "supports_kitty_keyboard")) caps.supportsKittyKeyboard = prog.supports_kitty_keyboard;
    if (@hasField(ProgObj, "supports_kitty_graphics")) caps.supportsKittyGraphics = prog.supports_kitty_graphics;
    if (@hasField(ProgObj, "supports_sixel")) caps.supportsSixel = prog.supports_sixel;
    if (@hasField(ProgObj, "supports_modify_other_keys")) caps.supportsModifyOtherKeys = prog.supports_modify_other_keys;
    if (@hasField(ProgObj, "supports_xtwinops")) caps.supportsXtwinops = prog.supports_xtwinops;
    if (@hasField(ProgObj, "supports_bracketed_paste")) caps.supportsBracketedPaste = prog.supports_bracketed_paste;
    if (@hasField(ProgObj, "supports_focus_events")) caps.supportsFocusEvents = prog.supports_focus_events;
    if (@hasField(ProgObj, "supports_sgr_mouse")) caps.supportsSgrMouse = prog.supports_sgr_mouse;
    if (@hasField(ProgObj, "supports_sgr_pixel_mouse")) caps.supportsSgrPixelMouse = prog.supports_sgr_pixel_mouse;
    if (@hasField(ProgObj, "supports_lightdark_report")) caps.supportsLightDarkReport = prog.supports_lightdark_report;
    if (@hasField(ProgObj, "supports_linux_palette_oscp")) caps.supportsLinuxPaletteOscP = prog.supports_linux_palette_oscp;
    if (@hasField(ProgObj, "supports_device_attributes")) caps.supportsDeviceAttributes = prog.supports_device_attributes;
    if (@hasField(ProgObj, "supports_cursor_style")) caps.supportsCursorStyle = prog.supports_cursor_style;
    if (@hasField(ProgObj, "supports_cursor_position_report")) caps.supportsCursorPositionReport = prog.supports_cursor_position_report;
    if (@hasField(ProgObj, "supports_pointer_shape")) caps.supportsPointerShape = prog.supports_pointer_shape;
    if (@hasField(ProgObj, "needs_tmux_passthrough")) caps.needsTmuxPassthrough = prog.needs_tmux_passthrough;
    if (@hasField(ProgObj, "needs_screen_passthrough")) caps.needsScreenPassthrough = prog.needs_screen_passthrough;
    if (@hasField(ProgObj, "screen_chunk_limit")) caps.screenChunkLimit = @intCast(prog.screen_chunk_limit);
    if (@hasField(ProgObj, "width_method")) caps.widthMethod = if (std.mem.eql(u8, prog.width_method, "wcwidth")) .grapheme else .wcwidth;
}

fn capsForProgram(comptime P: Program) TermCaps {
    var caps = defaultsCaps();
    const bp = cfg.by_program;
    switch (P) {
        .Kitty => overlayCaps(@TypeOf(bp.kitty), bp.kitty, &caps),
        .WezTerm => overlayCaps(@TypeOf(bp.wezterm), bp.wezterm, &caps),
        .ITerm2 => overlayCaps(@TypeOf(bp.iterm2), bp.iterm2, &caps),
        .AppleTerminal => overlayCaps(@TypeOf(bp.apple_terminal), bp.apple_terminal, &caps),
        .VTE => overlayCaps(@TypeOf(bp.vte), bp.vte, &caps),
        .Alacritty => overlayCaps(@TypeOf(bp.alacritty), bp.alacritty, &caps),
        .Ghostty => overlayCaps(@TypeOf(bp.ghostty), bp.ghostty, &caps),
        .Konsole => overlayCaps(@TypeOf(bp.konsole), bp.konsole, &caps),
        .Xterm => overlayCaps(@TypeOf(bp.xterm), bp.xterm, &caps),
        .VSCode => overlayCaps(@TypeOf(bp.vscode), bp.vscode, &caps),
        .WindowsTerminal => overlayCaps(@TypeOf(bp.windows_terminal), bp.windows_terminal, &caps),
        .LinuxConsole => overlayCaps(@TypeOf(bp.linux_console), bp.linux_console, &caps),
        .Unknown => {},
    }
    return caps;
}

pub fn detectProgram(env: *const std.process.EnvMap) Program {
    if (env.get("KITTY_PID") != null) return .Kitty;
    if (env.get("WEZTERM_EXECUTABLE") != null) return .WezTerm;
    if (env.get("WT_SESSION") != null) return .WindowsTerminal;
    if (env.get("VSCODE_GIT_IPC_HANDLE") != null) return .VSCode;

    // Check for Ghostty
    if (env.get("GHOSTTY_RESOURCES_DIR") != null) return .Ghostty;

    if (env.get("TERM_PROGRAM")) |tp| {
        if (std.mem.eql(u8, tp, "WezTerm")) return .WezTerm;
        if (std.mem.eql(u8, tp, "iTerm.app")) return .ITerm2;
        if (std.mem.eql(u8, tp, "Apple_Terminal")) return .AppleTerminal;
        if (std.ascii.eqlIgnoreCase(tp, "vscode")) return .VSCode;
    }

    if (env.get("KONSOLE_VERSION") != null) return .Konsole;
    if (env.get("VTE_VERSION") != null) return .VTE; // Many VTE-based terminals

    if (env.get("TERM")) |term| {
        if (std.mem.eql(u8, term, "linux")) return .LinuxConsole;
        if (std.mem.indexOf(u8, term, "xterm-kitty") != null) return .Kitty;
        if (std.mem.indexOf(u8, term, "alacritty") != null) return .Alacritty;
        if (std.mem.startsWith(u8, term, "xterm-ghostty")) return .Ghostty;
        if (std.mem.indexOf(u8, term, "xterm") != null) return .Xterm;
        if (std.mem.indexOf(u8, term, "gnome") != null) return .VTE;
        if (std.mem.indexOf(u8, term, "konsole") != null) return .Konsole;
    }

    return .Unknown;
}

fn applyMultiplexerOverlays(env: *const std.process.EnvMap, caps: *TermCaps) void {
    // tmux
    if (env.get("TMUX") != null) {
        const mx = cfg.multiplexers.tmux;
        if (@hasField(@TypeOf(mx), "needs_tmux_passthrough")) caps.needsTmuxPassthrough = mx.needs_tmux_passthrough;
    }
    // screen
    if (env.get("STY") != null or env.get("SCREEN") != null) {
        const mxs = cfg.multiplexers.screen;
        if (@hasField(@TypeOf(mxs), "needs_screen_passthrough")) caps.needsScreenPassthrough = mxs.needs_screen_passthrough;
        if (@hasField(@TypeOf(mxs), "screen_chunk_limit")) caps.screenChunkLimit = @intCast(mxs.screen_chunk_limit);
    }
}

pub fn detectCaps(allocator: std.mem.Allocator) !TermCaps {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    return detectCapsFromEnv(&env);
}

pub fn detectCapsFromEnv(env: *const std.process.EnvMap) TermCaps {
    const prog = detectProgram(env);
    var caps = switch (prog) {
        .Kitty => capsForProgram(.Kitty),
        .WezTerm => capsForProgram(.WezTerm),
        .ITerm2 => capsForProgram(.ITerm2),
        .AppleTerminal => capsForProgram(.AppleTerminal),
        .VTE => capsForProgram(.VTE),
        .Alacritty => capsForProgram(.Alacritty),
        .Ghostty => capsForProgram(.Ghostty),
        .Konsole => capsForProgram(.Konsole),
        .Xterm => capsForProgram(.Xterm),
        .VSCode => capsForProgram(.VSCode),
        .WindowsTerminal => capsForProgram(.WindowsTerminal),
        .LinuxConsole => capsForProgram(.LinuxConsole),
        .Unknown => capsForProgram(.Unknown),
    };

    applyMultiplexerOverlays(env, &caps);
    return caps;
}

// Lightweight helpers to gate feature usage
pub inline fn canUseOsc8(caps: TermCaps) bool {
    return caps.supportsHyperlinkOsc8;
}
pub inline fn canUseOsc52(caps: TermCaps) bool {
    return caps.supportsClipboardOsc52;
}
pub inline fn needsTmuxWrap(caps: TermCaps) bool {
    return caps.needsTmuxPassthrough;
}
pub inline fn needsScreenWrap(caps: TermCaps) bool {
    return caps.needsScreenPassthrough;
}
pub inline fn canUseDeviceAttributes(caps: TermCaps) bool {
    return caps.supportsDeviceAttributes;
}
pub inline fn canUseCursorStyle(caps: TermCaps) bool {
    return caps.supportsCursorStyle;
}
pub inline fn canUseCursorPositionReport(caps: TermCaps) bool {
    return caps.supportsCursorPositionReport;
}
pub inline fn canUsePointerShape(caps: TermCaps) bool {
    return caps.supportsPointerShape;
}

/// Convenience function to get terminal capabilities without allocator
pub fn getTermCaps() TermCaps {
    var env = std.process.getEnvMap(std.heap.page_allocator) catch std.process.EnvMap.init(std.heap.page_allocator);
    defer env.deinit();
    return detectCapsFromEnv(&env);
}

/// Get current terminal size
pub fn getTerminalSize() !TerminalSize {
    return switch (builtin.target.os.tag) {
        .windows => getTerminalSizeWindows(),
        else => getTerminalSizeUnix(),
    };
}

fn getTerminalSizeUnix() !TerminalSize {
    const os = std.os;
    const linux = std.os.linux;

    // Define winsize structure manually since it may not be available in std.c
    const winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };

    var ws: winsize = undefined;

    // Try to get terminal size using TIOCGWINSZ ioctl
    if (builtin.os.tag == .linux) {
        const TIOCGWINSZ = 0x5413;
        if (linux.ioctl(os.STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&ws)) == -1) {
            return error.GetTerminalSizeFailed;
        }
    } else {
        // For other Unix systems, try a generic approach
        // This may need platform-specific adjustments
        return error.GetTerminalSizeFailed;
    }

    if (ws.ws_col == 0 or ws.ws_row == 0) {
        return error.GetTerminalSizeFailed;
    }

    return TerminalSize{
        .width = ws.ws_col,
        .height = ws.ws_row,
    };
}

fn getTerminalSizeWindows() !TerminalSize {
    // Windows-specific terminal size detection
    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    const stdout_handle = kernel32.GetStdHandle(windows.STD_OUTPUT_HANDLE) orelse return error.GetTerminalSizeFailed;

    var csbi: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(stdout_handle, &csbi) == 0) {
        return error.GetTerminalSizeFailed;
    }

    const width = @as(u16, @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1));
    const height = @as(u16, @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1));

    return TerminalSize{ .width = width, .height = height };
}

/// Detect mouse capabilities for the current terminal
pub fn detectMouseCapabilities(allocator: std.mem.Allocator) !MouseCapabilities {
    var caps = MouseCapabilities{};
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const program = detectProgram(&env);

    // Apply terminal-specific capabilities
    switch (program) {
        .Kitty => {
            caps.supports_kitty_mouse = true;
            caps.supports_sgr_mouse = true;
            caps.supports_pixel_position = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_alternate_scroll = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .ITerm2 => {
            caps.supports_iterm2_mouse = true;
            caps.supports_sgr_mouse = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.supports_alternate_scroll = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .WezTerm => {
            caps.supports_wezterm_mouse = true;
            caps.supports_sgr_mouse = true;
            caps.supports_pixel_position = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .Alacritty => {
            caps.supports_sgr_mouse = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .Xterm, .Xterm => {
            caps.supports_vt200_mouse = true;
            caps.supports_button_event = true;
            caps.supports_any_event = true;
            caps.supports_sgr_mouse = true; // Modern xterm supports SGR
            caps.supports_bracketed_paste = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        else => {
            // Conservative defaults
            caps.supports_vt200_mouse = true;
            caps.max_x_coordinate = 223;
            caps.max_y_coordinate = 223;
        },
    }

    // Determine the preferred mouse protocol
    determinePreferredMouseProtocol(&caps);

    return caps;
}

/// Determine the preferred mouse protocol based on capabilities
fn determinePreferredMouseProtocol(caps: *MouseCapabilities) void {
    if (caps.supports_kitty_mouse) {
        caps.preferred_protocol = .kitty;
    } else if (caps.supports_pixel_position) {
        caps.preferred_protocol = .pixel;
    } else if (caps.supports_sgr_mouse) {
        caps.preferred_protocol = .sgr;
    } else if (caps.supports_urxvt_mouse) {
        caps.preferred_protocol = .urxvt;
    } else if (caps.supports_utf8_mouse) {
        caps.preferred_protocol = .utf8;
    } else if (caps.supports_any_event or
        caps.supports_button_event or
        caps.supports_vt200_mouse)
    {
        caps.preferred_protocol = .normal;
    } else if (caps.supports_x10_mouse) {
        caps.preferred_protocol = .x10;
    } else {
        caps.preferred_protocol = .none;
    }
}

/// Generate a human-readable capability report
pub fn generateCapabilityReport(allocator: std.mem.Allocator, caps: TermCaps) ![]u8 {
    var report = std.ArrayList(u8).init(allocator);
    defer report.deinit();

    const writer = report.writer();

    try writer.print("Terminal Capabilities Report\n", .{});
    try writer.print("===========================\n\n", .{});

    // Terminal identification
    try writer.print("Terminal Type: {s}\n", .{@tagName(detectProgramFromCaps(caps))});

    // Color support
    try writer.print("\nColor Support:\n", .{});
    try writer.print("  True Color: {}\n", .{caps.supportsTruecolor});
    try writer.print("  Hyperlinks (OSC 8): {}\n", .{caps.supportsHyperlinkOsc8});
    try writer.print("  Clipboard (OSC 52): {}\n", .{caps.supportsClipboardOsc52});

    // Advanced features
    try writer.print("\nAdvanced Features:\n", .{});
    try writer.print("  Working Directory (OSC 7): {}\n", .{caps.supportsWorkingDirOsc7});
    try writer.print("  Title Change (OSC 0/1/2): {}\n", .{caps.supportsTitleOsc012});
    try writer.print("  Notify (OSC 9): {}\n", .{caps.supportsNotifyOsc9});
    try writer.print("  FinalTerm OSC 133: {}\n", .{caps.supportsFinalTermOsc133});
    try writer.print("  iTerm2 OSC 1337: {}\n", .{caps.supportsITerm2Osc1337});
    try writer.print("  Color OSC 10/11/12: {}\n", .{caps.supportsColorOsc10_12});
    try writer.print("  Kitty Keyboard: {}\n", .{caps.supportsKittyKeyboard});
    try writer.print("  Kitty Graphics: {}\n", .{caps.supportsKittyGraphics});
    try writer.print("  Sixel Graphics: {}\n", .{caps.supportsSixel});
    try writer.print("  Modify Other Keys: {}\n", .{caps.supportsModifyOtherKeys});
    try writer.print("  XTWINOPS: {}\n", .{caps.supportsXtwinops});
    try writer.print("  Bracketed Paste: {}\n", .{caps.supportsBracketedPaste});
    try writer.print("  Focus Events: {}\n", .{caps.supportsFocusEvents});
    try writer.print("  SGR Mouse: {}\n", .{caps.supportsSgrMouse});
    try writer.print("  SGR Pixel Mouse: {}\n", .{caps.supportsSgrPixelMouse});
    try writer.print("  Light/Dark Report: {}\n", .{caps.supportsLightDarkReport});
    try writer.print("  Linux Palette OSC P: {}\n", .{caps.supportsLinuxPaletteOscP});
    try writer.print("  Device Attributes: {}\n", .{caps.supportsDeviceAttributes});
    try writer.print("  Cursor Style: {}\n", .{caps.supportsCursorStyle});
    try writer.print("  Cursor Position Report: {}\n", .{caps.supportsCursorPositionReport});
    try writer.print("  Pointer Shape: {}\n", .{caps.supportsPointerShape});

    // Multiplexer requirements
    try writer.print("\nMultiplexer Requirements:\n", .{});
    try writer.print("  Needs tmux Passthrough: {}\n", .{caps.needsTmuxPassthrough});
    try writer.print("  Needs Screen Passthrough: {}\n", .{caps.needsScreenPassthrough});
    try writer.print("  Screen Chunk Limit: {}\n", .{caps.screenChunkLimit});
    try writer.print("  Width Method: {s}\n", .{@tagName(caps.widthMethod)});

    return try report.toOwnedSlice();
}

/// Generate a mouse capability report
pub fn generateMouseCapabilityReport(allocator: std.mem.Allocator, caps: MouseCapabilities) ![]u8 {
    var report = std.ArrayList(u8).init(allocator);
    defer report.deinit();

    const writer = report.writer();

    try writer.print("Mouse Capabilities Report\n", .{});
    try writer.print("=========================\n\n", .{});

    // Preferred protocol
    try writer.print("Preferred Protocol: {s}\n\n", .{@tagName(caps.preferred_protocol)});

    // Basic mouse support
    try writer.print("Basic Mouse Support:\n", .{});
    try writer.print("  X10 Mouse: {}\n", .{caps.supports_x10_mouse});
    try writer.print("  VT200 Mouse: {}\n", .{caps.supports_vt200_mouse});
    try writer.print("  Button Events: {}\n", .{caps.supports_button_event});
    try writer.print("  Any Event (Motion): {}\n", .{caps.supports_any_event});

    // Extended protocols
    try writer.print("\nExtended Mouse Protocols:\n", .{});
    try writer.print("  SGR Mouse: {}\n", .{caps.supports_sgr_mouse});
    try writer.print("  urxvt Mouse: {}\n", .{caps.supports_urxvt_mouse});
    try writer.print("  UTF-8 Mouse: {}\n", .{caps.supports_utf8_mouse});
    try writer.print("  Pixel Position: {}\n", .{caps.supports_pixel_position});

    // Terminal-specific
    try writer.print("\nTerminal-Specific Support:\n", .{});
    try writer.print("  Kitty Mouse: {}\n", .{caps.supports_kitty_mouse});
    try writer.print("  iTerm2 Mouse: {}\n", .{caps.supports_iterm2_mouse});
    try writer.print("  WezTerm Mouse: {}\n", .{caps.supports_wezterm_mouse});

    // Additional features
    try writer.print("\nAdditional Features:\n", .{});
    try writer.print("  Focus Events: {}\n", .{caps.supports_focus_events});
    try writer.print("  Alternate Scroll: {}\n", .{caps.supports_alternate_scroll});
    try writer.print("  Bracketed Paste: {}\n", .{caps.supports_bracketed_paste});

    // Coordinate limits
    try writer.print("\nCoordinate Limits:\n", .{});
    try writer.print("  Max X: {}\n", .{caps.max_x_coordinate});
    try writer.print("  Max Y: {}\n", .{caps.max_y_coordinate});

    return try report.toOwnedSlice();
}

/// Helper function to detect program from capabilities (reverse lookup)
fn detectProgramFromCaps(caps: TermCaps) Program {
    // This is a simplified reverse lookup - in practice you'd need more sophisticated detection
    // For now, we'll use environment detection which is already implemented
    _ = caps; // Mark as used to avoid unused parameter warning
    var env = std.process.getEnvMap(std.heap.page_allocator) catch std.process.EnvMap.init(std.heap.page_allocator);
    defer env.deinit();
    return detectProgram(&env);
}

const std = @import("std");
const builtin = @import("builtin");

// Import the ZON capabilities database (compiled at comptime)
const cfg = @import("termcaps.zon");

// Field mapping utilities for cleaner overlay implementation
const field_mapping = struct {
    // Maps PascalCase field names to snake_case ZON field names
    fn mapField(comptime field_name: []const u8) []const u8 {
        if (std.mem.eql(u8, field_name, "supportsTruecolor")) return "supports_truecolor";
        if (std.mem.eql(u8, field_name, "supportsHyperlinkOsc8")) return "supports_hyperlink_osc8";
        if (std.mem.eql(u8, field_name, "supportsClipboardOsc52")) return "supports_clipboard_osc52";
        if (std.mem.eql(u8, field_name, "supportsWorkingDirOsc7")) return "supports_working_dir_osc7";
        if (std.mem.eql(u8, field_name, "supportsTitleOsc012")) return "supports_title_osc012";
        if (std.mem.eql(u8, field_name, "supportsNotifyOsc9")) return "supports_notify_osc9";
        if (std.mem.eql(u8, field_name, "supportsFinalTermOsc133")) return "supports_finalterm_osc133";
        if (std.mem.eql(u8, field_name, "supportsITerm2Osc1337")) return "supports_iterm2_osc1337";
        if (std.mem.eql(u8, field_name, "supportsColorOsc10_12")) return "supports_color_osc10_12";
        if (std.mem.eql(u8, field_name, "supportsKittyKeyboard")) return "supports_kitty_keyboard";
        if (std.mem.eql(u8, field_name, "supportsKittyGraphics")) return "supports_kitty_graphics";
        if (std.mem.eql(u8, field_name, "supportsSixel")) return "supports_sixel";
        if (std.mem.eql(u8, field_name, "supportsModifyOtherKeys")) return "supports_modify_other_keys";
        if (std.mem.eql(u8, field_name, "supportsXtwinops")) return "supports_xtwinops";
        if (std.mem.eql(u8, field_name, "supportsBracketedPaste")) return "supports_bracketed_paste";
        if (std.mem.eql(u8, field_name, "supportsFocusEvents")) return "supports_focus_events";
        if (std.mem.eql(u8, field_name, "supportsSgrMouse")) return "supports_sgr_mouse";
        if (std.mem.eql(u8, field_name, "supportsSgrPixelMouse")) return "supports_sgr_pixel_mouse";
        if (std.mem.eql(u8, field_name, "supportsLightDarkReport")) return "supports_lightdark_report";
        if (std.mem.eql(u8, field_name, "supportsLinuxPaletteOscP")) return "supports_linux_palette_oscp";
        if (std.mem.eql(u8, field_name, "supportsDeviceAttributes")) return "supports_device_attributes";
        if (std.mem.eql(u8, field_name, "supportsCursorStyle")) return "supports_cursor_style";
        if (std.mem.eql(u8, field_name, "supportsCursorPositionReport")) return "supports_cursor_position_report";
        if (std.mem.eql(u8, field_name, "supportsPointerShape")) return "supports_pointer_shape";
        if (std.mem.eql(u8, field_name, "needsTmuxPassthrough")) return "needs_tmux_passthrough";
        if (std.mem.eql(u8, field_name, "needsScreenPassthrough")) return "needs_screen_passthrough";
        if (std.mem.eql(u8, field_name, "screenChunkLimit")) return "screen_chunk_limit";
        if (std.mem.eql(u8, field_name, "widthMethod")) return "width_method";
        return field_name;
    }
};

/// Width method for character width calculation
pub const WidthMethod = enum { grapheme, wcwidth };

/// Terminal size information
pub const TerminalSize = struct {
    width: u16,
    height: u16,
};

/// DECRQM response status for mode queries
pub const DECRQMStatus = enum(u8) {
    not_recognized = 0,
    set = 1,
    reset = 2,
    permanently_set = 3,
    permanently_reset = 4,
};

/// Mouse protocol types in order of preference
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

/// Mouse capability information
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

/// Terminal type identification
pub const TerminalType = enum {
    // Classic VT series
    vt100,
    vt220,
    vt320,
    vt420,
    vt520,

    // Modern terminals
    xterm,
    gnome_terminal,
    konsole,
    terminal_app, // macOS Terminal.app
    iterm2,
    wezterm,
    alacritty,
    kitty,
    ghostty,

    // Legacy/compatibility
    rxvt,
    urxvt,
    tmux,
    screen,

    unknown,

    /// Convert secondary device attribute ID to terminal type
    pub fn fromSecondaryId(terminal_id: u32) TerminalType {
        return switch (terminal_id) {
            1 => .vt100,
            2 => .vt220,
            18, 19 => .vt320,
            24, 25 => .vt420,
            28, 29, 41 => .vt520,
            0 => .xterm, // xterm reports 0 for compatibility
            65 => .gnome_terminal,
            115 => .konsole,
            95 => .terminal_app,
            else => .unknown,
        };
    }

    /// Convert terminal type to human-readable string
    pub fn toString(self: TerminalType) []const u8 {
        return switch (self) {
            .vt100 => "VT100",
            .vt220 => "VT220",
            .vt320 => "VT320",
            .vt420 => "VT420",
            .vt520 => "VT520",
            .xterm => "XTerm",
            .gnome_terminal => "GNOME Terminal",
            .konsole => "Konsole",
            .terminal_app => "Terminal.app",
            .iterm2 => "iTerm2",
            .wezterm => "WezTerm",
            .alacritty => "Alacritty",
            .kitty => "Kitty",
            .ghostty => "Ghostty",
            .rxvt => "RXVT",
            .urxvt => "URXVT",
            .tmux => "tmux",
            .screen => "GNU Screen",
            .unknown => "Unknown",
        };
    }
};

/// Terminal program identification
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

/// Comprehensive terminal capabilities structure
pub const TermCaps = struct {
    supportsTruecolor: bool,
    supportsHyperlinkOsc8: bool,
    supportsClipboardOsc52: bool,
    supportsWorkingDirOsc7: bool,
    supportsTitleOsc012: bool,
    supportsNotifyOsc9: bool,
    supportsFinalTermOsc133: bool,
    supportsITerm2Osc1337: bool,
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
    supportsLinuxPaletteOscP: bool,
    supportsDeviceAttributes: bool,
    supportsCursorStyle: bool,
    supportsCursorPositionReport: bool,
    supportsPointerShape: bool,
    needsTmuxPassthrough: bool,
    needsScreenPassthrough: bool,
    screenChunkLimit: u16,
    widthMethod: WidthMethod,
};

/// Unified terminal capabilities detector
pub const TerminalCapabilities = struct {
    allocator: std.mem.Allocator,

    // Terminal identification
    program: Program,
    terminal_type: TerminalType,
    terminal_name: []const u8,

    // Core capabilities
    caps: TermCaps,
    mouse_caps: MouseCapabilities,

    // Size information
    size: ?TerminalSize,

    pub fn init(allocator: std.mem.Allocator) !TerminalCapabilities {
        var env = try std.process.getEnvMap(allocator);
        defer env.deinit();

        const program = detectProgram(&env);
        const caps = detectCapsFromEnv(&env);
        const mouse_caps = try detectMouseCapabilities(allocator, &env);
        const terminal_type = detectTerminalType(&env);

        return TerminalCapabilities{
            .allocator = allocator,
            .program = program,
            .terminal_type = terminal_type,
            .terminal_name = try allocator.dupe(u8, programToString(program)),
            .caps = caps,
            .mouse_caps = mouse_caps,
            .size = null,
        };
    }

    pub fn deinit(self: *TerminalCapabilities) void {
        self.allocator.free(self.terminal_name);
    }

    /// Detect current terminal size
    pub fn detectSize(self: *TerminalCapabilities) !void {
        self.size = try getTerminalSize();
    }

    /// Generate a comprehensive capability report
    pub fn generateReport(self: *TerminalCapabilities, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();

        const writer = report.writer();

        try writer.print("Terminal Capabilities Report\n", .{});
        try writer.print("===========================\n\n", .{});

        // Terminal identification
        try writer.print("Terminal Program: {s}\n", .{programToString(self.program)});
        try writer.print("Terminal Type: {s}\n", .{self.terminal_type.toString()});
        try writer.print("Terminal Name: {s}\n", .{self.terminal_name});

        if (self.size) |size| {
            try writer.print("Terminal Size: {}x{}\n", .{ size.width, size.height });
        }

        // Color support
        try writer.print("\nColor Support:\n", .{});
        try writer.print("  True Color: {}\n", .{self.caps.supportsTruecolor});
        try writer.print("  Hyperlinks (OSC 8): {}\n", .{self.caps.supportsHyperlinkOsc8});
        try writer.print("  Clipboard (OSC 52): {}\n", .{self.caps.supportsClipboardOsc52});

        // Advanced features
        try writer.print("\nAdvanced Features:\n", .{});
        try writer.print("  Working Directory (OSC 7): {}\n", .{self.caps.supportsWorkingDirOsc7});
        try writer.print("  Title Change (OSC 0/1/2): {}\n", .{self.caps.supportsTitleOsc012});
        try writer.print("  Notify (OSC 9): {}\n", .{self.caps.supportsNotifyOsc9});
        try writer.print("  FinalTerm OSC 133: {}\n", .{self.caps.supportsFinalTermOsc133});
        try writer.print("  iTerm2 OSC 1337: {}\n", .{self.caps.supportsITerm2Osc1337});
        try writer.print("  Color OSC 10/11/12: {}\n", .{self.caps.supportsColorOsc10_12});
        try writer.print("  Kitty Keyboard: {}\n", .{self.caps.supportsKittyKeyboard});
        try writer.print("  Kitty Graphics: {}\n", .{self.caps.supportsKittyGraphics});
        try writer.print("  Sixel Graphics: {}\n", .{self.caps.supportsSixel});
        try writer.print("  Modify Other Keys: {}\n", .{self.caps.supportsModifyOtherKeys});
        try writer.print("  XTWINOPS: {}\n", .{self.caps.supportsXtwinops});
        try writer.print("  Bracketed Paste: {}\n", .{self.caps.supportsBracketedPaste});
        try writer.print("  Focus Events: {}\n", .{self.caps.supportsFocusEvents});
        try writer.print("  SGR Mouse: {}\n", .{self.caps.supportsSgrMouse});
        try writer.print("  SGR Pixel Mouse: {}\n", .{self.caps.supportsSgrPixelMouse});
        try writer.print("  Light/Dark Report: {}\n", .{self.caps.supportsLightDarkReport});
        try writer.print("  Linux Palette OSC P: {}\n", .{self.caps.supportsLinuxPaletteOscP});
        try writer.print("  Device Attributes: {}\n", .{self.caps.supportsDeviceAttributes});
        try writer.print("  Cursor Style: {}\n", .{self.caps.supportsCursorStyle});
        try writer.print("  Cursor Position Report: {}\n", .{self.caps.supportsCursorPositionReport});
        try writer.print("  Pointer Shape: {}\n", .{self.caps.supportsPointerShape});

        // Mouse capabilities
        try writer.print("\nMouse Capabilities:\n", .{});
        try writer.print("  Preferred Protocol: {s}\n", .{@tagName(self.mouse_caps.preferred_protocol)});
        try writer.print("  Max Coordinates: {}x{}\n", .{ self.mouse_caps.max_x_coordinate, self.mouse_caps.max_y_coordinate });
        try writer.print("  SGR Mouse: {}\n", .{self.mouse_caps.supports_sgr_mouse});
        try writer.print("  Kitty Mouse: {}\n", .{self.mouse_caps.supports_kitty_mouse});
        try writer.print("  Pixel Position: {}\n", .{self.mouse_caps.supports_pixel_position});
        try writer.print("  Focus Events: {}\n", .{self.mouse_caps.supports_focus_events});
        try writer.print("  Bracketed Paste: {}\n", .{self.mouse_caps.supports_bracketed_paste});

        // Multiplexer requirements
        try writer.print("\nMultiplexer Requirements:\n", .{});
        try writer.print("  Needs tmux Passthrough: {}\n", .{self.caps.needsTmuxPassthrough});
        try writer.print("  Needs Screen Passthrough: {}\n", .{self.caps.needsScreenPassthrough});
        try writer.print("  Screen Chunk Limit: {}\n", .{self.caps.screenChunkLimit});
        try writer.print("  Width Method: {s}\n", .{@tagName(self.caps.widthMethod)});

        return try report.toOwnedSlice();
    }

    /// Enable mouse protocol on the given writer
    pub fn enableMouseProtocol(self: *TerminalCapabilities, writer: anytype) !void {
        const ansi_mod = @import("ansi/mod.zig");

        // Convert from capabilities MouseProtocol to ansi.mode MouseProtocol
        const protocol = switch (self.mouse_caps.preferred_protocol) {
            .none => return,
            .x10 => ansi_mod.mode.MouseProtocol.x10,
            .normal => ansi_mod.mode.MouseProtocol.normal,
            .utf8 => ansi_mod.mode.MouseProtocol.utf8,
            .urxvt => ansi_mod.mode.MouseProtocol.urxvt,
            .sgr => ansi_mod.mode.MouseProtocol.sgr,
            .pixel => ansi_mod.mode.MouseProtocol.sgr_pixels,
            .kitty => ansi_mod.mode.MouseProtocol.sgr_pixels,
        };

        try ansi_mod.mode.enableMouseTracking(writer, protocol, self.caps);

        // Enable bracketed paste if supported
        if (self.mouse_caps.supports_bracketed_paste) {
            try ansi_mod.mode.enableBracketedPaste(writer, self.caps);
        }
    }

    /// Disable mouse mode
    pub fn disableMouseMode(self: *TerminalCapabilities, writer: anytype) !void {
        const ansi_mod = @import("ansi/mod.zig");
        try ansi_mod.mode.disableMouseTracking(writer, self.caps);
        try ansi_mod.mode.disableBracketedPaste(writer, self.caps);
    }
};

// Internal implementation functions

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

// Helper function to apply overlay with special case handling
fn applyOverlay(prog_config: anytype, caps: *TermCaps) void {
    // Use field mapping to overlay values, but only for fields that exist in the program config
    inline for (std.meta.fields(TermCaps)) |field| {
        const source_field_name = field_mapping.mapField(field.name);
        if (@hasField(@TypeOf(prog_config), source_field_name)) {
            // Handle special cases
            if (std.mem.eql(u8, field.name, "widthMethod")) {
                caps.widthMethod = if (std.mem.eql(u8, @field(prog_config, source_field_name), "wcwidth")) .wcwidth else .grapheme;
            } else if (std.mem.eql(u8, field.name, "screenChunkLimit")) {
                caps.screenChunkLimit = @intCast(@field(prog_config, source_field_name));
            } else {
                // Normal field mapping
                @field(caps, field.name) = @field(prog_config, source_field_name);
            }
        }
    }
}

fn capsForProgram(comptime P: Program) TermCaps {
    var caps = defaultsCaps();
    const bp = cfg.by_program;
    switch (P) {
        .Kitty => applyOverlay(bp.kitty, &caps),
        .WezTerm => applyOverlay(bp.wezterm, &caps),
        .ITerm2 => applyOverlay(bp.iterm2, &caps),
        .AppleTerminal => applyOverlay(bp.apple_terminal, &caps),
        .VTE => applyOverlay(bp.vte, &caps),
        .Alacritty => applyOverlay(bp.alacritty, &caps),
        .Ghostty => applyOverlay(bp.ghostty, &caps),
        .Konsole => applyOverlay(bp.konsole, &caps),
        .Xterm => applyOverlay(bp.xterm, &caps),
        .VSCode => applyOverlay(bp.vscode, &caps),
        .WindowsTerminal => applyOverlay(bp.windows_terminal, &caps),
        .LinuxConsole => applyOverlay(bp.linux_console, &caps),
        .Unknown => applyOverlay(bp.unknown, &caps),
    }
    return caps;
}

fn detectProgram(env: *const std.process.EnvMap) Program {
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

fn programToString(program: Program) []const u8 {
    return switch (program) {
        .Kitty => "Kitty",
        .WezTerm => "WezTerm",
        .ITerm2 => "iTerm2",
        .AppleTerminal => "Apple Terminal",
        .VTE => "VTE",
        .Alacritty => "Alacritty",
        .Ghostty => "Ghostty",
        .Konsole => "Konsole",
        .Xterm => "XTerm",
        .VSCode => "VSCode",
        .WindowsTerminal => "Windows Terminal",
        .LinuxConsole => "Linux Console",
        .Unknown => "Unknown",
    };
}

fn detectTerminalType(env: *const std.process.EnvMap) TerminalType {
    const program = detectProgram(env);
    return switch (program) {
        .Kitty => .kitty,
        .WezTerm => .wezterm,
        .ITerm2 => .iterm2,
        .AppleTerminal => .terminal_app,
        .VTE => .gnome_terminal,
        .Alacritty => .alacritty,
        .Ghostty => .ghostty,
        .Konsole => .konsole,
        .Xterm => .xterm,
        .VSCode => .xterm, // VSCode uses xterm-compatible terminal
        .WindowsTerminal => .xterm, // Windows Terminal is xterm-compatible
        .LinuxConsole => .linux_console,
        .Unknown => .unknown,
    };
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

fn detectCapsFromEnv(env: *const std.process.EnvMap) TermCaps {
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

fn detectMouseCapabilities(allocator: std.mem.Allocator, env: *const std.process.EnvMap) !MouseCapabilities {
    var caps = MouseCapabilities{};
    const program = detectProgram(env);
    _ = allocator; // Currently unused but kept for future extensions

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
        .Ghostty => {
            caps.supports_sgr_mouse = true;
            caps.supports_pixel_position = true;
            caps.supports_focus_events = true;
            caps.supports_bracketed_paste = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .Xterm, .VSCode, .WindowsTerminal => {
            caps.supports_vt200_mouse = true;
            caps.supports_button_event = true;
            caps.supports_any_event = true;
            caps.supports_sgr_mouse = true; // Modern xterm supports SGR
            caps.supports_bracketed_paste = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .Konsole, .VTE => {
            caps.supports_sgr_mouse = true;
            caps.supports_vt200_mouse = true;
            caps.supports_x10_mouse = true;
            caps.supports_bracketed_paste = true;
            caps.max_x_coordinate = 65535;
            caps.max_y_coordinate = 65535;
        },
        .AppleTerminal => {
            caps.supports_vt200_mouse = true;
            caps.supports_x10_mouse = true;
            caps.supports_bracketed_paste = true;
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

fn getTerminalSize() !TerminalSize {
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

// Convenience functions for gatekeeping feature usage
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

// Tests
test "field mapping works correctly" {
    const testing = std.testing;

    // Test that field mapping converts PascalCase to snake_case correctly
    try testing.expectEqualStrings("supports_truecolor", field_mapping.mapField("supportsTruecolor"));
    try testing.expectEqualStrings("supports_kitty_keyboard", field_mapping.mapField("supportsKittyKeyboard"));
    try testing.expectEqualStrings("width_method", field_mapping.mapField("widthMethod"));
    try testing.expectEqualStrings("screen_chunk_limit", field_mapping.mapField("screenChunkLimit"));
}

test "terminal capabilities detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var caps = try TerminalCapabilities.init(allocator);
    defer caps.deinit();

    try testing.expect(caps.program != undefined);
    try testing.expect(caps.terminal_type != undefined);
    try testing.expect(caps.terminal_name.len > 0);
}

test "mouse protocol determination" {
    const testing = std.testing;

    var mouse_caps = MouseCapabilities{
        .supports_sgr_mouse = true,
        .supports_pixel_position = false,
        .supports_kitty_mouse = false,
    };

    determinePreferredMouseProtocol(&mouse_caps);
    try testing.expect(mouse_caps.preferred_protocol == .sgr);

    mouse_caps.supports_kitty_mouse = true;
    determinePreferredMouseProtocol(&mouse_caps);
    try testing.expect(mouse_caps.preferred_protocol == .kitty);
}

test "terminal type from secondary ID" {
    const testing = std.testing;

    try testing.expect(TerminalType.fromSecondaryId(0) == .xterm);
    try testing.expect(TerminalType.fromSecondaryId(1) == .vt100);
    try testing.expect(TerminalType.fromSecondaryId(65) == .gnome_terminal);
}

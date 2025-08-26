const std = @import("std");

// Import the ZON capabilities database (compiled at comptime)
const cfg = @import("termcaps.zon");

pub const WidthMethod = enum { grapheme, wcwidth };

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
        .Konsole => capsForProgram(.Konsole),
        .Xterm => capsForProgram(.Xterm),
        .VSCode => capsForProgram(.VSCode),
        .WindowsTerminal => capsForProgram(.WindowsTerminal),
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

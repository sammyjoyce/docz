const std = @import("std");
const caps = @import("caps.zig");
const device_attrs = @import("ansi/device_attributes.zig");

/// DECRQM response status
pub const DECRQMStatus = enum(u8) {
    not_recognized = 0,
    set = 1,
    reset = 2,
    permanently_set = 3,
    permanently_reset = 4,
};

/// Mouse capability detector
pub const MouseCapabilityDetector = struct {
    allocator: std.mem.Allocator,
    query_system: *TerminalQuerySystem,
    capabilities: caps.MouseCapabilities,
    terminal_type: TerminalType,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, query_system: *TerminalQuerySystem) Self {
        return Self{
            .allocator = allocator,
            .query_system = query_system,
            .capabilities = caps.MouseCapabilities{},
            .terminal_type = .unknown,
        };
    }

    /// Determine the preferred mouse protocol based on capabilities
    pub fn determinePreferredProtocol(self: *Self) void {
        // Protocol preference hierarchy (highest to lowest)
        if (self.capabilities.supports_kitty_mouse) {
            self.capabilities.preferred_protocol = .kitty;
        } else if (self.capabilities.supports_pixel_position) {
            self.capabilities.preferred_protocol = .pixel;
        } else if (self.capabilities.supports_sgr_mouse) {
            self.capabilities.preferred_protocol = .sgr;
        } else if (self.capabilities.supports_urxvt_mouse) {
            self.capabilities.preferred_protocol = .urxvt;
        } else if (self.capabilities.supports_utf8_mouse) {
            self.capabilities.preferred_protocol = .utf8;
        } else if (self.capabilities.supports_vt200_mouse) {
            self.capabilities.preferred_protocol = .normal;
        } else if (self.capabilities.supports_x10_mouse) {
            self.capabilities.preferred_protocol = .x10;
        } else {
            self.capabilities.preferred_protocol = .none;
        }
    }

    /// Apply terminal-specific capabilities
    pub fn applyTerminalSpecificCapabilities(self: *Self) void {
        switch (self.terminal_type) {
            .kitty => {
                self.capabilities.supports_kitty_mouse = true;
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_pixel_position = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .iterm2 => {
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_pixel_position = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .wezterm => {
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_pixel_position = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .alacritty => {
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .xterm => {
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_urxvt_mouse = true;
                self.capabilities.supports_utf8_mouse = true;
                self.capabilities.supports_vt200_mouse = true;
                self.capabilities.supports_x10_mouse = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .gnome_terminal, .konsole => {
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_vt200_mouse = true;
                self.capabilities.supports_x10_mouse = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .terminal_app => {
                self.capabilities.supports_vt200_mouse = true;
                self.capabilities.supports_x10_mouse = true;
                self.capabilities.supports_bracketed_paste = true;
            },
            .vt100, .vt220, .vt320, .vt420, .vt520 => {
                self.capabilities.supports_x10_mouse = true;
                self.capabilities.max_x_coordinate = 223;
                self.capabilities.max_y_coordinate = 223;
            },
            .unknown => {
                // Basic capabilities
                self.capabilities.supports_x10_mouse = true;
            },
        }
    }

    /// Enable mouse protocol
    pub fn enableMouseProtocol(self: *Self, writer: anytype) !void {
        switch (self.capabilities.preferred_protocol) {
            .none => return,
            .x10 => try writer.writeAll("\x1b[?9h"),
            .normal => try writer.writeAll("\x1b[?1000h"),
            .utf8 => try writer.writeAll("\x1b[?1005h\x1b[?1000h"),
            .urxvt => try writer.writeAll("\x1b[?1015h\x1b[?1000h"),
            .sgr => {
                try writer.writeAll("\x1b[?1002h"); // Button events
                if (self.capabilities.supports_focus_events) {
                    try writer.writeAll("\x1b[?1004h"); // Focus events
                }
            },
            .pixel => {
                try writer.writeAll("\x1b[?1002h\x1b[?1016h"); // Button events + pixel
                if (self.capabilities.supports_focus_events) {
                    try writer.writeAll("\x1b[?1004h"); // Focus events
                }
            },
            .kitty => {
                try writer.writeAll("\x1b[?1002h\x1b[?1016h"); // Button events + pixel
                if (self.capabilities.supports_focus_events) {
                    try writer.writeAll("\x1b[?1004h"); // Focus events
                }
            },
        }

        // Enable bracketed paste if supported
        if (self.capabilities.supports_bracketed_paste) {
            try writer.writeAll("\x1b[?2004h");
        }
    }

    /// Detect mouse capabilities
    pub fn detect(self: *Self) !void {
        // Simple detection - in a real implementation this would query the terminal
        self.applyTerminalSpecificCapabilities();
        self.determinePreferredProtocol();
    }

    /// Get capability report
    pub fn getCapabilityReport(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\Mouse Capabilities Report
            \\========================
            \\Terminal Type: {s}
            \\Preferred Protocol: {s}
            \\Max Coordinates: {}x{}
            \\Supports SGR Mouse: {}
            \\Supports Kitty Mouse: {}
            \\Supports Pixel Position: {}
            \\Supports Focus Events: {}
            \\Supports Bracketed Paste: {}
        , .{
            @tagName(self.terminal_type),
            @tagName(self.capabilities.preferred_protocol),
            self.capabilities.max_x_coordinate,
            self.capabilities.max_y_coordinate,
            self.capabilities.supports_sgr_mouse,
            self.capabilities.supports_kitty_mouse,
            self.capabilities.supports_pixel_position,
            self.capabilities.supports_focus_events,
            self.capabilities.supports_bracketed_paste,
        });
    }

    /// Enable best available mouse mode
    pub fn enableBestMouseMode(self: *Self, writer: anytype) !void {
        try self.enableMouseProtocol(writer);
    }

    /// Disable mouse mode
    pub fn disableMouseMode(self: *Self, writer: anytype) !void {
        _ = self; // Not used in stub implementation
        try writer.writeAll("\x1b[?1000l\x1b[?1002l\x1b[?1004l\x1b[?1005l\x1b[?1006l\x1b[?1015l\x1b[?1016l\x1b[?2004l");
    }

    /// Perform runtime tests
    pub fn performRuntimeTests(self: *Self, writer: anytype, reader: anytype) !void {
        _ = self;
        _ = writer;
        _ = reader;
        // Stub implementation - would perform actual runtime tests
    }
};

/// Re-export types from other modules
pub const MouseMode = @import("input/mouse.zig").MouseMode;
pub const MouseProtocol = caps.MouseProtocol;
pub const TerminalQuerySystem = @import("terminal_query_system.zig").TerminalQuerySystem;

/// Terminal type enum (simplified)
pub const TerminalType = enum {
    unknown,
    xterm,
    iterm2,
    wezterm,
    alacritty,
    kitty,
    gnome_terminal,
    konsole,
    terminal_app,
    vt100,
    vt220,
    vt320,
    vt420,
    vt520,
};
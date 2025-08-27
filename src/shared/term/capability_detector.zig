const std = @import("std");

/// Terminal capabilities
pub const TerminalCapabilities = struct {
    terminal_type: TerminalType = .unknown,
    supports_mouse: bool = false,
    supports_mouse_sgr: bool = false,
    supports_mouse_pixel: bool = false,
    supports_mouse_motion: bool = false,
    supports_focus_events: bool = false,
    supports_bracketed_paste: bool = false,
    supports_color: bool = false,
    supports_true_color: bool = false,
    supports_256_color: bool = false,
};

/// Terminal type
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

/// Main capability detector
pub const CapabilityDetector = struct {
    allocator: std.mem.Allocator,
    capabilities: TerminalCapabilities,

    pub fn init(allocator: std.mem.Allocator) CapabilityDetector {
        return CapabilityDetector{
            .allocator = allocator,
            .capabilities = TerminalCapabilities{},
        };
    }

    /// Detect terminal capabilities
    pub fn detect(self: *CapabilityDetector) !void {
        // Simple detection - in a real implementation this would query the terminal
        // For now, assume xterm-like capabilities
        self.capabilities.terminal_type = .xterm;
        self.capabilities.supports_mouse = true;
        self.capabilities.supports_mouse_sgr = true;
        self.capabilities.supports_mouse_pixel = true;
        self.capabilities.supports_mouse_motion = true;
        self.capabilities.supports_focus_events = true;
        self.capabilities.supports_bracketed_paste = true;
        self.capabilities.supports_color = true;
        self.capabilities.supports_true_color = true;
        self.capabilities.supports_256_color = true;
    }
};

/// Enhance capability detector with mouse detection
pub fn enhanceCapabilityDetectorWithMouse(
    detector: *CapabilityDetector,
    query_system: *TerminalQuerySystem,
) !void {
    _ = query_system; // Not used in stub implementation

    // Enhance with mouse capabilities
    detector.capabilities.supports_mouse = true;
    detector.capabilities.supports_mouse_sgr = true;
    detector.capabilities.supports_mouse_pixel = true;
    detector.capabilities.supports_mouse_motion = true;
    detector.capabilities.supports_focus_events = true;
    detector.capabilities.supports_bracketed_paste = true;
}

/// Re-export types
pub const TerminalQuerySystem = @import("terminal_query_system.zig").TerminalQuerySystem;
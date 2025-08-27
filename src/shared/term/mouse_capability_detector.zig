const std = @import("std");
const TerminalQuerySystem = @import("terminal_query_system.zig").TerminalQuerySystem;
const QueryType = @import("terminal_query_system.zig").QueryType;
const QueryResponse = @import("terminal_query_system.zig").QueryResponse;
const QueryError = @import("terminal_query_system.zig").QueryError;
const CapabilityDetector = @import("capability_detector.zig").CapabilityDetector;
const Capabilities = @import("capability_detector.zig").Capabilities;

/// Mouse modes that can be queried with DECRQM (DEC Request Mode)
pub const MouseMode = enum(u16) {
    // Basic mouse modes
    x10_mouse = 9, // X10 compatibility mode
    vt200_mouse = 1000, // VT200 mouse mode (button press/release)
    vt200_highlight = 1001, // VT200 highlight tracking
    button_event = 1002, // Button event tracking
    any_event = 1003, // Any event tracking (includes motion)

    // Extended modes
    focus_event = 1004, // Focus in/out events
    utf8_mouse = 1005, // UTF-8 mouse coordinate encoding
    sgr_mouse = 1006, // SGR (Select Graphic Rendition) extended coordinates
    alternate_scroll = 1007, // Alternate scroll mode
    urxvt_mouse = 1015, // urxvt extended mouse mode
    pixel_position = 1016, // Pixel-based mouse position reporting

    // Additional features
    bracketed_paste = 2004, // Bracketed paste mode
};

/// Mouse capability detection results
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

/// DECRQM response status codes
pub const DECRQMStatus = enum(u8) {
    not_recognized = 0, // Mode not recognized
    set = 1, // Mode is set (enabled)
    reset = 2, // Mode is reset (disabled)
    permanently_set = 3, // Mode is permanently set
    permanently_reset = 4, // Mode is permanently reset
};

/// Enhanced mouse capability detector
pub const MouseCapabilityDetector = struct {
    allocator: std.mem.Allocator,
    query_system: *TerminalQuerySystem,
    capabilities: MouseCapabilities = .{},
    terminal_type: Capabilities.TerminalType = .unknown,
    detection_timeout_ms: u32 = 100,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, query_system: *TerminalQuerySystem) Self {
        return Self{
            .allocator = allocator,
            .query_system = query_system,
        };
    }

    /// Perform comprehensive mouse capability detection
    pub fn detect(self: *Self) !void {
        // First, detect terminal type from environment
        try self.detectTerminalType();

        // Apply terminal-specific capabilities first
        self.applyTerminalSpecificCapabilities();

        // Then perform DECRQM queries to verify actual support
        try self.performDECRQMQueries();

        // Determine the preferred mouse protocol
        self.determinePreferredProtocol();
    }

    /// Detect terminal type from environment variables
    fn detectTerminalType(self: *Self) !void {
        const env_map = std.process.getEnvMap(self.allocator) catch return;
        defer env_map.deinit();

        if (env_map.get("KITTY_WINDOW_ID")) |_| {
            self.terminal_type = .kitty;
        } else if (env_map.get("ITERM_SESSION_ID")) |_| {
            self.terminal_type = .iterm2;
        } else if (env_map.get("WEZTERM_EXECUTABLE")) |_| {
            self.terminal_type = .wezterm;
        } else if (env_map.get("ALACRITTY_SOCKET")) |_| {
            self.terminal_type = .alacritty;
        } else if (env_map.get("TERM")) |term| {
            if (std.mem.startsWith(u8, term, "xterm")) {
                self.terminal_type = .xterm;
            } else if (std.mem.startsWith(u8, term, "screen")) {
                self.terminal_type = .screen;
            } else if (std.mem.startsWith(u8, term, "tmux")) {
                self.terminal_type = .tmux;
            }
        }
    }

    /// Apply terminal-specific mouse capabilities
    fn applyTerminalSpecificCapabilities(self: *Self) void {
        switch (self.terminal_type) {
            .kitty => {
                self.capabilities.supports_kitty_mouse = true;
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_pixel_position = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.supports_alternate_scroll = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .iterm2 => {
                self.capabilities.supports_iterm2_mouse = true;
                self.capabilities.supports_sgr_mouse = true;
                self.capabilities.supports_focus_events = true;
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.supports_alternate_scroll = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            .wezterm => {
                self.capabilities.supports_wezterm_mouse = true;
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
            .xterm, .xterm_256color => {
                self.capabilities.supports_vt200_mouse = true;
                self.capabilities.supports_button_event = true;
                self.capabilities.supports_any_event = true;
                self.capabilities.supports_sgr_mouse = true; // Modern xterm supports SGR
                self.capabilities.supports_bracketed_paste = true;
                self.capabilities.max_x_coordinate = 65535;
                self.capabilities.max_y_coordinate = 65535;
            },
            else => {
                // Conservative defaults
                self.capabilities.supports_vt200_mouse = true;
                self.capabilities.max_x_coordinate = 223;
                self.capabilities.max_y_coordinate = 223;
            },
        }
    }

    /// Perform DECRQM queries to verify mouse mode support
    fn performDECRQMQueries(self: *Self) !void {
        // Enable raw mode for reliable query/response
        const was_raw = self.query_system.raw_mode_enabled;
        if (!was_raw) {
            try self.query_system.enableRawMode();
        }
        defer {
            if (!was_raw) {
                self.query_system.disableRawMode() catch {};
            }
        }

        // Query each mouse mode
        const modes_to_query = [_]MouseMode{
            .x10_mouse,
            .vt200_mouse,
            .button_event,
            .any_event,
            .focus_event,
            .utf8_mouse,
            .sgr_mouse,
            .alternate_scroll,
            .urxvt_mouse,
            .pixel_position,
            .bracketed_paste,
        };

        for (modes_to_query) |mode| {
            const status = self.queryDECRQM(mode) catch continue;
            self.updateCapabilityFromDECRQM(mode, status);
        }

        // Also try terminal-specific queries
        try self.performTerminalSpecificQueries();
    }

    /// Query a specific DEC mode using DECRQM
    fn queryDECRQM(self: *Self, mode: MouseMode) !DECRQMStatus {
        // Build DECRQM query sequence: ESC[?<mode>$p
        var query_buf: [32]u8 = undefined;
        const query = try std.fmt.bufPrint(&query_buf, "\x1b[?{}$p", .{@intFromEnum(mode)});

        // Send query and wait for response
        const query_dup = try self.allocator.dupe(u8, query);
        defer self.allocator.free(query_dup);

        // Create a custom query type for DECRQM
        _ = try self.sendRawQuery(query_dup);

        // Wait for response with timeout
        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(self.detection_timeout_ms));

        while (std.time.milliTimestamp() < deadline) {
            try self.query_system.pollResponses(10);

            // Check if we got a DECRQM response
            if (self.checkForDECRQMResponse(mode)) |status| {
                return status;
            }
        }

        return DECRQMStatus.not_recognized;
    }

    /// Send a raw query sequence
    fn sendRawQuery(self: *Self, query: []const u8) !u32 {
        const writer = self.query_system.stdout_writer orelse self.query_system.stdout_file.writer();
        try writer.writeAll(query);

        if (self.query_system.stdout_file.isTty()) {
            try self.query_system.stdout_file.sync();
        }

        const query_id = self.query_system.next_query_id;
        self.query_system.next_query_id +%= 1;
        return query_id;
    }

    /// Check response buffer for DECRQM response
    fn checkForDECRQMResponse(self: *Self, mode: MouseMode) ?DECRQMStatus {
        const buffer = self.query_system.response_buffer.items;

        // DECRQM response format: ESC[?<mode>;<status>$y
        var search_buf: [32]u8 = undefined;
        const search_prefix = std.fmt.bufPrint(&search_buf, "\x1b[?{};", .{@intFromEnum(mode)}) catch return null;

        if (std.mem.indexOf(u8, buffer, search_prefix)) |start| {
            const remainder = buffer[start + search_prefix.len ..];

            // Find the status value before $y
            if (std.mem.indexOf(u8, remainder, "$y")) |end| {
                const status_str = remainder[0..end];
                const status = std.fmt.parseInt(u8, status_str, 10) catch return null;

                // Remove the processed response from buffer
                const response_end = start + search_prefix.len + end + 2; // +2 for "$y"
                if (response_end <= buffer.len) {
                    const new_buffer = self.allocator.alloc(u8, buffer.len - response_end) catch return null;
                    defer self.allocator.free(new_buffer);
                    @memcpy(new_buffer, buffer[response_end..]);

                    self.query_system.response_buffer.clearRetainingCapacity();
                    self.query_system.response_buffer.appendSlice(self.allocator, new_buffer) catch {};
                }

                return switch (status) {
                    0 => .not_recognized,
                    1 => .set,
                    2 => .reset,
                    3 => .permanently_set,
                    4 => .permanently_reset,
                    else => .not_recognized,
                };
            }
        }

        return null;
    }

    /// Update capabilities based on DECRQM response
    fn updateCapabilityFromDECRQM(self: *Self, mode: MouseMode, status: DECRQMStatus) void {
        const is_supported = switch (status) {
            .set, .permanently_set => true,
            .reset, .permanently_reset, .not_recognized => false,
        };

        switch (mode) {
            .x10_mouse => self.capabilities.supports_x10_mouse = is_supported,
            .vt200_mouse => self.capabilities.supports_vt200_mouse = is_supported,
            .button_event => self.capabilities.supports_button_event = is_supported,
            .any_event => self.capabilities.supports_any_event = is_supported,
            .focus_event => self.capabilities.supports_focus_events = is_supported,
            .utf8_mouse => self.capabilities.supports_utf8_mouse = is_supported,
            .sgr_mouse => {
                self.capabilities.supports_sgr_mouse = is_supported;
                if (is_supported) {
                    // SGR mode supports unlimited coordinates
                    self.capabilities.max_x_coordinate = 65535;
                    self.capabilities.max_y_coordinate = 65535;
                }
            },
            .alternate_scroll => self.capabilities.supports_alternate_scroll = is_supported,
            .urxvt_mouse => {
                self.capabilities.supports_urxvt_mouse = is_supported;
                if (is_supported) {
                    // urxvt mode supports large coordinates
                    self.capabilities.max_x_coordinate = 2015;
                    self.capabilities.max_y_coordinate = 2015;
                }
            },
            .pixel_position => self.capabilities.supports_pixel_position = is_supported,
            .bracketed_paste => self.capabilities.supports_bracketed_paste = is_supported,
        }
    }

    /// Perform terminal-specific mouse capability queries
    fn performTerminalSpecificQueries(self: *Self) !void {
        switch (self.terminal_type) {
            .kitty => try self.queryKittyMouseSupport(),
            .iterm2 => try self.queryITerm2MouseSupport(),
            .wezterm => try self.queryWezTermMouseSupport(),
            else => {},
        }
    }

    /// Query Kitty-specific mouse support
    fn queryKittyMouseSupport(self: *Self) !void {
        // Kitty uses its own mouse protocol query: ESC[?2031$p
        const kitty_mouse_mode = 2031;
        var query_buf: [32]u8 = undefined;
        const query = try std.fmt.bufPrint(&query_buf, "\x1b[?{}$p", .{kitty_mouse_mode});

        const query_dup = try self.allocator.dupe(u8, query);
        defer self.allocator.free(query_dup);

        _ = try self.sendRawQuery(query_dup);

        // Check for Kitty mouse protocol support
        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(self.detection_timeout_ms));
        while (std.time.milliTimestamp() < deadline) {
            try self.query_system.pollResponses(10);

            const buffer = self.query_system.response_buffer.items;
            if (std.mem.indexOf(u8, buffer, "\x1b[?2031;")) |_| {
                self.capabilities.supports_kitty_mouse = true;
                break;
            }
        }
    }

    /// Query iTerm2-specific mouse support
    fn queryITerm2MouseSupport(self: *Self) !void {
        // iTerm2 supports standard SGR mouse mode but also has proprietary extensions
        // Query using iTerm2's proprietary sequence
        const query = "\x1b]1337;ReportVariable=mouse\x07";
        const query_dup = try self.allocator.dupe(u8, query);
        defer self.allocator.free(query_dup);

        _ = try self.sendRawQuery(query_dup);

        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(self.detection_timeout_ms));
        while (std.time.milliTimestamp() < deadline) {
            try self.query_system.pollResponses(10);

            const buffer = self.query_system.response_buffer.items;
            if (std.mem.indexOf(u8, buffer, "\x1b]1337;ReportVariable=")) |_| {
                self.capabilities.supports_iterm2_mouse = true;
                break;
            }
        }
    }

    /// Query WezTerm-specific mouse support
    fn queryWezTermMouseSupport(self: *Self) !void {
        // WezTerm supports SGR mouse mode and pixel positioning
        // It responds to standard DECRQM queries which we've already done
        // Just verify it supports the extended features
        if (self.capabilities.supports_sgr_mouse and self.capabilities.supports_pixel_position) {
            self.capabilities.supports_wezterm_mouse = true;
        }
    }

    /// Determine the preferred mouse protocol based on capabilities
    fn determinePreferredProtocol(self: *Self) void {
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
        } else if (self.capabilities.supports_any_event or
            self.capabilities.supports_button_event or
            self.capabilities.supports_vt200_mouse)
        {
            self.capabilities.preferred_protocol = .normal;
        } else if (self.capabilities.supports_x10_mouse) {
            self.capabilities.preferred_protocol = .x10;
        } else {
            self.capabilities.preferred_protocol = .none;
        }
    }

    /// Enable the best available mouse mode
    pub fn enableBestMouseMode(self: *Self, writer: anytype) !void {
        // First, ensure mouse reporting is enabled
        try self.enableMouseProtocol(writer);

        // Enable additional features if supported
        if (self.capabilities.supports_focus_events) {
            try writer.writeAll("\x1b[?1004h"); // Enable focus events
        }

        if (self.capabilities.supports_alternate_scroll) {
            try writer.writeAll("\x1b[?1007h"); // Enable alternate scroll
        }

        if (self.capabilities.supports_bracketed_paste) {
            try writer.writeAll("\x1b[?2004h"); // Enable bracketed paste
        }
    }

    /// Enable the preferred mouse protocol
    pub fn enableMouseProtocol(self: *Self, writer: anytype) !void {
        switch (self.capabilities.preferred_protocol) {
            .kitty => {
                // Enable Kitty mouse protocol
                try writer.writeAll("\x1b[>1u"); // Push current mouse mode
                try writer.writeAll("\x1b[?2031h"); // Enable Kitty mouse tracking
            },
            .pixel => {
                // Enable pixel position reporting with SGR
                try writer.writeAll("\x1b[?1002h"); // Enable button event tracking
                try writer.writeAll("\x1b[?1006h"); // Enable SGR mode
                try writer.writeAll("\x1b[?1016h"); // Enable pixel position
            },
            .sgr => {
                // Enable SGR extended mouse mode
                try writer.writeAll("\x1b[?1002h"); // Enable button event tracking
                try writer.writeAll("\x1b[?1006h"); // Enable SGR mode
            },
            .urxvt => {
                // Enable urxvt mouse mode
                try writer.writeAll("\x1b[?1002h"); // Enable button event tracking
                try writer.writeAll("\x1b[?1015h"); // Enable urxvt mode
            },
            .utf8 => {
                // Enable UTF-8 mouse mode
                try writer.writeAll("\x1b[?1002h"); // Enable button event tracking
                try writer.writeAll("\x1b[?1005h"); // Enable UTF-8 mode
            },
            .normal => {
                // Enable standard mouse tracking
                if (self.capabilities.supports_any_event) {
                    try writer.writeAll("\x1b[?1003h"); // Any event tracking
                } else if (self.capabilities.supports_button_event) {
                    try writer.writeAll("\x1b[?1002h"); // Button event tracking
                } else if (self.capabilities.supports_vt200_mouse) {
                    try writer.writeAll("\x1b[?1000h"); // VT200 mouse mode
                }
            },
            .x10 => {
                // Enable X10 mouse mode (most basic)
                try writer.writeAll("\x1b[?9h");
            },
            .none => {},
        }
    }

    /// Disable all mouse modes
    pub fn disableMouseMode(self: *Self, writer: anytype) !void {
        _ = self;

        // Disable all mouse tracking modes
        try writer.writeAll("\x1b[?9l"); // Disable X10
        try writer.writeAll("\x1b[?1000l"); // Disable VT200
        try writer.writeAll("\x1b[?1001l"); // Disable highlight
        try writer.writeAll("\x1b[?1002l"); // Disable button event
        try writer.writeAll("\x1b[?1003l"); // Disable any event

        // Disable extended protocols
        try writer.writeAll("\x1b[?1005l"); // Disable UTF-8
        try writer.writeAll("\x1b[?1006l"); // Disable SGR
        try writer.writeAll("\x1b[?1015l"); // Disable urxvt
        try writer.writeAll("\x1b[?1016l"); // Disable pixel position

        // Disable additional features
        try writer.writeAll("\x1b[?1004l"); // Disable focus events
        try writer.writeAll("\x1b[?1007l"); // Disable alternate scroll
        try writer.writeAll("\x1b[?2004l"); // Disable bracketed paste

        // Disable Kitty mouse if it was enabled
        try writer.writeAll("\x1b[?2031l"); // Disable Kitty mouse
        try writer.writeAll("\x1b[<1u"); // Pop mouse mode
    }

    /// Get a human-readable report of mouse capabilities
    pub fn getCapabilityReport(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayListUnmanaged(u8){};
        defer report.deinit(allocator);

        try report.appendSlice(allocator, "Mouse Capabilities Report\n");
        try report.appendSlice(allocator, "=========================\n\n");

        // Terminal identification
        try report.writer(allocator).print("Terminal Type: {s}\n", .{@tagName(self.terminal_type)});
        try report.writer(allocator).print("Preferred Protocol: {s}\n\n", .{@tagName(self.capabilities.preferred_protocol)});

        // Basic mouse support
        try report.appendSlice(allocator, "Basic Mouse Support:\n");
        try report.writer(allocator).print("  X10 Mouse: {}\n", .{self.capabilities.supports_x10_mouse});
        try report.writer(allocator).print("  VT200 Mouse: {}\n", .{self.capabilities.supports_vt200_mouse});
        try report.writer(allocator).print("  Button Events: {}\n", .{self.capabilities.supports_button_event});
        try report.writer(allocator).print("  Any Event (Motion): {}\n", .{self.capabilities.supports_any_event});

        // Extended protocols
        try report.appendSlice(allocator, "\nExtended Mouse Protocols:\n");
        try report.writer(allocator).print("  SGR Mouse: {}\n", .{self.capabilities.supports_sgr_mouse});
        try report.writer(allocator).print("  urxvt Mouse: {}\n", .{self.capabilities.supports_urxvt_mouse});
        try report.writer(allocator).print("  UTF-8 Mouse: {}\n", .{self.capabilities.supports_utf8_mouse});
        try report.writer(allocator).print("  Pixel Position: {}\n", .{self.capabilities.supports_pixel_position});

        // Terminal-specific
        try report.appendSlice(allocator, "\nTerminal-Specific Support:\n");
        try report.writer(allocator).print("  Kitty Mouse: {}\n", .{self.capabilities.supports_kitty_mouse});
        try report.writer(allocator).print("  iTerm2 Mouse: {}\n", .{self.capabilities.supports_iterm2_mouse});
        try report.writer(allocator).print("  WezTerm Mouse: {}\n", .{self.capabilities.supports_wezterm_mouse});

        // Additional features
        try report.appendSlice(allocator, "\nAdditional Features:\n");
        try report.writer(allocator).print("  Focus Events: {}\n", .{self.capabilities.supports_focus_events});
        try report.writer(allocator).print("  Alternate Scroll: {}\n", .{self.capabilities.supports_alternate_scroll});
        try report.writer(allocator).print("  Bracketed Paste: {}\n", .{self.capabilities.supports_bracketed_paste});

        // Coordinate limits
        try report.appendSlice(allocator, "\nCoordinate Limits:\n");
        try report.writer(allocator).print("  Max X: {}\n", .{self.capabilities.max_x_coordinate});
        try report.writer(allocator).print("  Max Y: {}\n", .{self.capabilities.max_y_coordinate});

        return try report.toOwnedSlice(allocator);
    }

    /// Test mouse functionality with runtime tests
    pub fn performRuntimeTests(self: *Self, writer: anytype, reader: anytype) !void {
        _ = reader; // For future interactive tests

        // Test 1: Enable and disable mouse modes
        try writer.writeAll("\n=== Testing Mouse Mode Enable/Disable ===\n");

        try self.enableBestMouseMode(writer);
        try writer.writeAll("Mouse mode enabled. Move mouse to test.\n");
        std.time.sleep(2 * std.time.ns_per_s);

        try self.disableMouseMode(writer);
        try writer.writeAll("Mouse mode disabled.\n");

        // Test 2: Test different protocols
        if (self.capabilities.supports_sgr_mouse) {
            try writer.writeAll("\n=== Testing SGR Mouse Protocol ===\n");
            try writer.writeAll("\x1b[?1002h\x1b[?1006h"); // Enable SGR
            try writer.writeAll("SGR mouse enabled. Click to test.\n");
            std.time.sleep(2 * std.time.ns_per_s);
            try writer.writeAll("\x1b[?1002l\x1b[?1006l"); // Disable
        }

        // Test 3: Test focus events if supported
        if (self.capabilities.supports_focus_events) {
            try writer.writeAll("\n=== Testing Focus Events ===\n");
            try writer.writeAll("\x1b[?1004h"); // Enable focus events
            try writer.writeAll("Focus events enabled. Switch windows to test.\n");
            std.time.sleep(3 * std.time.ns_per_s);
            try writer.writeAll("\x1b[?1004l"); // Disable
        }

        try writer.writeAll("\nRuntime tests complete.\n");
    }
};

/// Integration function for existing CapabilityDetector
pub fn enhanceCapabilityDetectorWithMouse(
    detector: *CapabilityDetector,
    query_system: *TerminalQuerySystem,
) !void {
    var mouse_detector = MouseCapabilityDetector.init(
        detector.allocator,
        query_system,
    );

    // Perform mouse capability detection
    try mouse_detector.detect();

    // Update the main capability detector with mouse results
    detector.capabilities.supports_mouse = mouse_detector.capabilities.supports_vt200_mouse or
        mouse_detector.capabilities.supports_x10_mouse;
    detector.capabilities.supports_mouse_sgr = mouse_detector.capabilities.supports_sgr_mouse;
    detector.capabilities.supports_mouse_pixel = mouse_detector.capabilities.supports_pixel_position;
    detector.capabilities.supports_mouse_motion = mouse_detector.capabilities.supports_any_event;
    detector.capabilities.supports_focus_events = mouse_detector.capabilities.supports_focus_events;
    detector.capabilities.supports_bracketed_paste = mouse_detector.capabilities.supports_bracketed_paste;

    // Set terminal type if detected
    detector.capabilities.terminal_type = mouse_detector.terminal_type;
}

// Tests
const testing = std.testing;

test "mouse mode enum values" {
    try testing.expectEqual(@as(u16, 9), @intFromEnum(MouseMode.x10_mouse));
    try testing.expectEqual(@as(u16, 1000), @intFromEnum(MouseMode.vt200_mouse));
    try testing.expectEqual(@as(u16, 1006), @intFromEnum(MouseMode.sgr_mouse));
    try testing.expectEqual(@as(u16, 2004), @intFromEnum(MouseMode.bracketed_paste));
}

test "DECRQM status parsing" {
    const status_values = [_]u8{ 0, 1, 2, 3, 4 };
    const expected = [_]DECRQMStatus{
        .not_recognized,
        .set,
        .reset,
        .permanently_set,
        .permanently_reset,
    };

    for (status_values, expected) |val, exp| {
        const status: DECRQMStatus = switch (val) {
            0 => .not_recognized,
            1 => .set,
            2 => .reset,
            3 => .permanently_set,
            4 => .permanently_reset,
            else => .not_recognized,
        };
        try testing.expectEqual(exp, status);
    }
}

test "preferred protocol determination" {
    const allocator = testing.allocator;

    // Create a dummy query system (won't actually be used in this test)
    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Test 1: No capabilities -> none
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.none, detector.capabilities.preferred_protocol);

    // Test 2: Only X10 -> x10
    detector.capabilities.supports_x10_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.x10, detector.capabilities.preferred_protocol);

    // Test 3: SGR available -> sgr preferred
    detector.capabilities.supports_sgr_mouse = true;
    detector.capabilities.supports_vt200_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.sgr, detector.capabilities.preferred_protocol);

    // Test 4: Kitty available -> kitty most preferred
    detector.capabilities.supports_kitty_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.kitty, detector.capabilities.preferred_protocol);
}

test "terminal type detection" {
    // This test would need environment variable mocking
    // For now, just verify the structure compiles correctly
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Apply known terminal capabilities
    detector.terminal_type = .kitty;
    detector.applyTerminalSpecificCapabilities();

    try testing.expect(detector.capabilities.supports_kitty_mouse);
    try testing.expect(detector.capabilities.supports_sgr_mouse);
    try testing.expect(detector.capabilities.supports_pixel_position);
    try testing.expectEqual(@as(u32, 65535), detector.capabilities.max_x_coordinate);
}

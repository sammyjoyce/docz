const std = @import("std");
const testing = std.testing;
const TerminalQuerySystem = @import("../src/shared/term/terminal_query_system.zig").TerminalQuerySystem;
const QueryType = @import("../src/shared/term/terminal_query_system.zig").QueryType;
const MouseCapabilityDetector = @import("../src/shared/term/mouse_capability_detector.zig").MouseCapabilityDetector;
const MouseMode = @import("../src/shared/term/mouse_capability_detector.zig").MouseMode;
const DECRQMStatus = @import("../src/shared/term/mouse_capability_detector.zig").DECRQMStatus;
const MouseProtocol = @import("../src/shared/term/mouse_capability_detector.zig").MouseProtocol;
const CapabilityDetector = @import("../src/shared/term/capability_detector.zig").CapabilityDetector;

test "mouse query types are properly defined" {
    // Verify that all mouse query types exist
    const mouse_queries = [_]QueryType{
        .mouse_x10_query,
        .mouse_vt200_query,
        .mouse_button_event_query,
        .mouse_any_event_query,
        .mouse_sgr_query,
        .mouse_urxvt_query,
        .mouse_pixel_query,
        .mouse_focus_query,
        .mouse_alternate_scroll_query,
    };

    for (mouse_queries) |query| {
        _ = query;
    }
}

test "DECRQM query sequence generation" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    const test_cases = [_]struct {
        query: QueryType,
        expected: []const u8,
    }{
        .{ .query = .mouse_x10_query, .expected = "\x1b[?9$p" },
        .{ .query = .mouse_vt200_query, .expected = "\x1b[?1000$p" },
        .{ .query = .mouse_sgr_query, .expected = "\x1b[?1006$p" },
        .{ .query = .bracketed_paste_test, .expected = "\x1b[?2004$p" },
    };

    for (test_cases) |tc| {
        const sequence = try query_system.buildQuerySequence(tc.query);
        defer allocator.free(sequence);
        try testing.expectEqualStrings(tc.expected, sequence);
    }
}

test "DECRQM response parsing" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    // Test parsing DECRQM responses
    const test_responses = [_]struct {
        data: []const u8,
        expected_mode: u16,
        expected_enabled: bool,
    }{
        .{ .data = "\x1b[?1006;1$y", .expected_mode = 1006, .expected_enabled = true }, // SGR enabled
        .{ .data = "\x1b[?1006;2$y", .expected_mode = 1006, .expected_enabled = false }, // SGR disabled
        .{ .data = "\x1b[?1000;3$y", .expected_mode = 1000, .expected_enabled = true }, // VT200 permanently set
        .{ .data = "\x1b[?1000;4$y", .expected_mode = 1000, .expected_enabled = false }, // VT200 permanently reset
    };

    for (test_responses) |tr| {
        const response = try query_system.parseDecReport(tr.data);
        defer allocator.free(response.raw_response);

        switch (response.parsed_data) {
            .boolean_result => |enabled| {
                try testing.expectEqual(tr.expected_enabled, enabled);
            },
            else => return error.UnexpectedResponseType,
        }
    }
}

test "mouse capability detection initialization" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    const detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Check initial state
    try testing.expectEqual(false, detector.capabilities.supports_sgr_mouse);
    try testing.expectEqual(MouseProtocol.none, detector.capabilities.preferred_protocol);
    try testing.expectEqual(@as(u32, 223), detector.capabilities.max_x_coordinate);
    try testing.expectEqual(@as(u32, 223), detector.capabilities.max_y_coordinate);
}

test "terminal-specific capability application" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Test Kitty terminal capabilities
    detector.terminal_type = .kitty;
    detector.applyTerminalSpecificCapabilities();

    try testing.expect(detector.capabilities.supports_kitty_mouse);
    try testing.expect(detector.capabilities.supports_sgr_mouse);
    try testing.expect(detector.capabilities.supports_pixel_position);
    try testing.expect(detector.capabilities.supports_focus_events);
    try testing.expect(detector.capabilities.supports_bracketed_paste);
    try testing.expectEqual(@as(u32, 65535), detector.capabilities.max_x_coordinate);

    // Test iTerm2 capabilities
    detector = MouseCapabilityDetector.init(allocator, &query_system);
    detector.terminal_type = .iterm2;
    detector.applyTerminalSpecificCapabilities();

    try testing.expect(detector.capabilities.supports_iterm2_mouse);
    try testing.expect(detector.capabilities.supports_sgr_mouse);
    try testing.expect(detector.capabilities.supports_focus_events);

    // Test basic xterm capabilities
    detector = MouseCapabilityDetector.init(allocator, &query_system);
    detector.terminal_type = .xterm;
    detector.applyTerminalSpecificCapabilities();

    try testing.expect(detector.capabilities.supports_vt200_mouse);
    try testing.expect(detector.capabilities.supports_button_event);
    try testing.expect(detector.capabilities.supports_sgr_mouse);
}

test "preferred protocol determination logic" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Test hierarchy: none -> x10 -> normal -> utf8 -> urxvt -> sgr -> pixel -> kitty

    // No capabilities
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.none, detector.capabilities.preferred_protocol);

    // Only X10
    detector.capabilities.supports_x10_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.x10, detector.capabilities.preferred_protocol);

    // Add VT200
    detector.capabilities.supports_vt200_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.normal, detector.capabilities.preferred_protocol);

    // Add UTF-8
    detector.capabilities.supports_utf8_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.utf8, detector.capabilities.preferred_protocol);

    // Add urxvt
    detector.capabilities.supports_urxvt_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.urxvt, detector.capabilities.preferred_protocol);

    // Add SGR (should now prefer SGR over urxvt)
    detector.capabilities.supports_sgr_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.sgr, detector.capabilities.preferred_protocol);

    // Add pixel positioning
    detector.capabilities.supports_pixel_position = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.pixel, detector.capabilities.preferred_protocol);

    // Add Kitty (highest priority)
    detector.capabilities.supports_kitty_mouse = true;
    detector.determinePreferredProtocol();
    try testing.expectEqual(MouseProtocol.kitty, detector.capabilities.preferred_protocol);
}

test "mouse mode enable/disable sequences" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Test buffer for capturing output
    var output_buffer = std.ArrayListUnmanaged(u8){};
    defer output_buffer.deinit(allocator);
    const writer = output_buffer.writer(allocator);

    // Test enabling SGR mouse mode
    detector.capabilities.preferred_protocol = .sgr;
    detector.capabilities.supports_sgr_mouse = true;
    detector.capabilities.supports_focus_events = true;
    detector.capabilities.supports_bracketed_paste = true;

    try detector.enableMouseProtocol(writer);
    const output = output_buffer.items;

    // Should contain SGR enable sequences
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[?1002h") != null); // Button events
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[?1006h") != null); // SGR mode

    // Test Kitty protocol
    output_buffer.clearRetainingCapacity();
    detector.capabilities.preferred_protocol = .kitty;
    try detector.enableMouseProtocol(writer);

    const kitty_output = output_buffer.items;
    try testing.expect(std.mem.indexOf(u8, kitty_output, "\x1b[>1u") != null); // Push mode
    try testing.expect(std.mem.indexOf(u8, kitty_output, "\x1b[?2031h") != null); // Kitty mouse
}

test "DECRQM status enum conversion" {
    const test_cases = [_]struct {
        value: u8,
        expected: DECRQMStatus,
    }{
        .{ .value = 0, .expected = .not_recognized },
        .{ .value = 1, .expected = .set },
        .{ .value = 2, .expected = .reset },
        .{ .value = 3, .expected = .permanently_set },
        .{ .value = 4, .expected = .permanently_reset },
    };

    for (test_cases) |tc| {
        const status: DECRQMStatus = switch (tc.value) {
            0 => .not_recognized,
            1 => .set,
            2 => .reset,
            3 => .permanently_set,
            4 => .permanently_reset,
            else => .not_recognized,
        };
        try testing.expectEqual(tc.expected, status);
    }
}

test "capability report generation" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Set some capabilities
    detector.terminal_type = .kitty;
    detector.capabilities.supports_sgr_mouse = true;
    detector.capabilities.supports_kitty_mouse = true;
    detector.capabilities.preferred_protocol = .kitty;
    detector.capabilities.max_x_coordinate = 65535;
    detector.capabilities.max_y_coordinate = 65535;

    const report = try detector.getCapabilityReport(allocator);
    defer allocator.free(report);

    // Verify report contains expected information
    try testing.expect(std.mem.indexOf(u8, report, "Mouse Capabilities Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Terminal Type: kitty") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Preferred Protocol: kitty") != null);
    try testing.expect(std.mem.indexOf(u8, report, "SGR Mouse: true") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Kitty Mouse: true") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Max X: 65535") != null);
}

test "integration with main capability detector" {
    const allocator = testing.allocator;

    var query_system = TerminalQuerySystem.init(allocator);
    defer query_system.deinit();

    var main_detector = CapabilityDetector.init(allocator);

    // Initially should have no mouse capabilities
    try testing.expect(!main_detector.capabilities.supports_mouse);
    try testing.expect(!main_detector.capabilities.supports_mouse_sgr);

    // Enhance with mouse detection
    var mouse_detector = MouseCapabilityDetector.init(allocator, &query_system);

    // Simulate detection results
    mouse_detector.capabilities.supports_vt200_mouse = true;
    mouse_detector.capabilities.supports_sgr_mouse = true;
    mouse_detector.capabilities.supports_focus_events = true;
    mouse_detector.capabilities.supports_bracketed_paste = true;
    mouse_detector.terminal_type = .xterm_256color;

    // Update main detector
    main_detector.capabilities.supports_mouse = mouse_detector.capabilities.supports_vt200_mouse or
        mouse_detector.capabilities.supports_x10_mouse;
    main_detector.capabilities.supports_mouse_sgr = mouse_detector.capabilities.supports_sgr_mouse;
    main_detector.capabilities.supports_focus_events = mouse_detector.capabilities.supports_focus_events;
    main_detector.capabilities.supports_bracketed_paste = mouse_detector.capabilities.supports_bracketed_paste;
    main_detector.capabilities.terminal_type = mouse_detector.terminal_type;

    // Verify enhancement worked
    try testing.expect(main_detector.capabilities.supports_mouse);
    try testing.expect(main_detector.capabilities.supports_mouse_sgr);
    try testing.expect(main_detector.capabilities.supports_focus_events);
    try testing.expect(main_detector.capabilities.supports_bracketed_paste);
    try testing.expectEqual(CapabilityDetector.Capabilities.TerminalType.xterm_256color, main_detector.capabilities.terminal_type);
}

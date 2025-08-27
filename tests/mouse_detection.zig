const std = @import("std");
const testing = std.testing;
const term = @import("../src/shared/term/mod.zig");
const TerminalQuerySystem = term.terminal_query_system.TerminalQuerySystem;
const QueryType = term.terminal_query_system.QueryType;
const MouseCapabilityDetector = term.mouse_capability_detector.MouseCapabilityDetector;
const MouseMode = term.mouse_capability_detector.MouseMode;
const DECRQMStatus = term.mouse_capability_detector.DECRQMStatus;
const MouseProtocol = term.mouse_capability_detector.MouseProtocol;
const CapabilityDetector = term.capability_detector.CapabilityDetector;

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

test "decrqmQuerySequenceGeneration" {
    const allocator = testing.allocator;

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

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
        const sequence = try querySystem.buildQuerySequence(tc.query);
        defer allocator.free(sequence);
        try testing.expectEqualStrings(tc.expected, sequence);
    }
}

test "decrqm_response parsing" {
    const allocator = testing.allocator;

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

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
        const response = try querySystem.parseDecReport(tr.data);
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

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

    const detector = MouseCapabilityDetector.init(allocator, &querySystem);

    // Check initial state
    try testing.expectEqual(false, detector.capabilities.supports_sgr_mouse);
    try testing.expectEqual(MouseProtocol.none, detector.capabilities.preferred_protocol);
    try testing.expectEqual(@as(u32, 223), detector.capabilities.max_x_coordinate);
    try testing.expectEqual(@as(u32, 223), detector.capabilities.max_y_coordinate);
}

test "terminal-specific capability application" {
    const allocator = testing.allocator;

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &querySystem);

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
    detector = MouseCapabilityDetector.init(allocator, &querySystem);
    detector.terminal_type = .iterm2;
    detector.applyTerminalSpecificCapabilities();

    try testing.expect(detector.capabilities.supports_iterm2_mouse);
    try testing.expect(detector.capabilities.supports_sgr_mouse);
    try testing.expect(detector.capabilities.supports_focus_events);

    // Test basic xterm capabilities
    detector = MouseCapabilityDetector.init(allocator, &querySystem);
    detector.terminal_type = .xterm;
    detector.applyTerminalSpecificCapabilities();

    try testing.expect(detector.capabilities.supports_vt200_mouse);
    try testing.expect(detector.capabilities.supports_button_event);
    try testing.expect(detector.capabilities.supports_sgr_mouse);
}

test "preferred protocol determination logic" {
    const allocator = testing.allocator;

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &querySystem);

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

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &querySystem);

    // Test buffer for capturing output
    var outputBuffer = std.ArrayListUnmanaged(u8){};
    defer outputBuffer.deinit(allocator);
    const writer = outputBuffer.writer(allocator);

    // Test enabling SGR mouse mode
    detector.capabilities.preferred_protocol = .sgr;
    detector.capabilities.supports_sgr_mouse = true;
    detector.capabilities.supports_focus_events = true;
    detector.capabilities.supports_bracketed_paste = true;

    try detector.enableMouseProtocol(writer);
    const output = outputBuffer.items;

    // Should contain SGR enable sequences
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[?1002h") != null); // Button events
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[?1006h") != null); // SGR mode

    // Test Kitty protocol
    outputBuffer.clearRetainingCapacity();
    detector.capabilities.preferred_protocol = .kitty;
    try detector.enableMouseProtocol(writer);

    const kittyOutput = outputBuffer.items;
    try testing.expect(std.mem.indexOf(u8, kittyOutput, "\x1b[>1u") != null); // Push mode
    try testing.expect(std.mem.indexOf(u8, kittyOutput, "\x1b[?2031h") != null); // Kitty mouse
}

test "decrqm_status enum conversion" {
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

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

    var detector = MouseCapabilityDetector.init(allocator, &querySystem);

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

    var querySystem = TerminalQuerySystem.init(allocator);
    defer querySystem.deinit();

    var mainDetector = CapabilityDetector.init(allocator);

    // Initially should have no mouse capabilities
    try testing.expect(!mainDetector.capabilities.supports_mouse);
    try testing.expect(!mainDetector.capabilities.supports_mouse_sgr);

    // Enhance with mouse detection
    var mouseDetector = MouseCapabilityDetector.init(allocator, &querySystem);

    // Simulate detection results
    mouseDetector.capabilities.supports_vt200_mouse = true;
    mouseDetector.capabilities.supports_sgr_mouse = true;
    mouseDetector.capabilities.supports_focus_events = true;
    mouseDetector.capabilities.supports_bracketed_paste = true;
    mouseDetector.terminal_type = .xterm_256color;

    // Update main detector
    mainDetector.capabilities.supports_mouse = mouseDetector.capabilities.supports_vt200_mouse or
        mouseDetector.capabilities.supports_x10_mouse;
    mainDetector.capabilities.supports_mouse_sgr = mouseDetector.capabilities.supports_sgr_mouse;
    mainDetector.capabilities.supports_focus_events = mouseDetector.capabilities.supports_focus_events;
    mainDetector.capabilities.supports_bracketed_paste = mouseDetector.capabilities.supports_bracketed_paste;
    mainDetector.capabilities.terminal_type = mouseDetector.terminal_type;

    // Verify enhancement worked
    try testing.expect(mainDetector.capabilities.supports_mouse);
    try testing.expect(mainDetector.capabilities.supports_mouse_sgr);
    try testing.expect(mainDetector.capabilities.supports_focus_events);
    try testing.expect(mainDetector.capabilities.supports_bracketed_paste);
    try testing.expectEqual(CapabilityDetector.Capabilities.TerminalType.xterm_256color, mainDetector.capabilities.terminal_type);
}

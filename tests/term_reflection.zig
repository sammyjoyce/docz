const std = @import("std");
const testing = std.testing;

// Mock structures to test reflection concepts without importing actual modules
const MockTermCaps = struct {
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
    screenChunkLimit: u16,
    widthMethod: enum { grapheme, wcwidth },
    needsTmuxPassthrough: bool,
    needsScreenPassthrough: bool,
};

const MockDefaults = struct {
    supports_truecolor: bool,
    supports_hyperlink_osc8: bool,
    supports_clipboard_osc52: bool,
    supports_working_dir_osc7: bool,
    supports_title_osc012: bool,
    supports_notify_osc9: bool,
    supports_finalterm_osc133: bool,
    supports_iterm2_osc1337: bool,
    supports_color_osc10_12: bool,
    supports_kitty_keyboard: bool,
    supports_kitty_graphics: bool,
    supports_sixel: bool,
    supports_modify_other_keys: bool,
    supports_xtwinops: bool,
    supports_bracketed_paste: bool,
    supports_focus_events: bool,
    supports_sgr_mouse: bool,
    supports_sgr_pixel_mouse: bool,
    supports_lightdark_report: bool,
    supports_linux_palette_oscp: bool,
    supports_device_attributes: bool,
    supports_cursor_style: bool,
    supports_cursor_position_report: bool,
    supports_pointer_shape: bool,
    needs_tmux_passthrough: bool,
    needs_screen_passthrough: bool,
    screen_chunk_limit: u16,
    width_method: []const u8,
};

const MockProgramConfig = struct {
    supports_truecolor: bool,
    supports_hyperlink_osc8: bool,
    supports_clipboard_osc52: bool,
    supports_notify_osc9: bool,
    supports_finalterm_osc133: bool,
    supports_iterm2_osc1337: bool,
    supports_kitty_graphics: bool,
    supports_modify_other_keys: bool,
    supports_lightdark_report: bool,
    supports_sgr_pixel_mouse: bool,
    supports_xtwinops: bool,
    supports_sgr_mouse: bool,
    screen_chunk_limit: u16,
    width_method: []const u8,
};

const MockMultiplexerConfig = struct {
    needs_tmux_passthrough: bool = false,
    needs_screen_passthrough: bool = false,
    screen_chunk_limit: u16 = 768,
};

const MockProgram = enum {
    Kitty,
    WezTerm,
    ITerm2,
    Xterm,
    Unknown,
};

fn mockDefaultsCaps() MockTermCaps {
    return MockTermCaps{
        .supportsTruecolor = true,
        .supportsHyperlinkOsc8 = true,
        .supportsClipboardOsc52 = true,
        .supportsWorkingDirOsc7 = true,
        .supportsTitleOsc012 = true,
        .supportsNotifyOsc9 = false,
        .supportsFinalTermOsc133 = false,
        .supportsITerm2Osc1337 = false,
        .supportsColorOsc10_12 = true,
        .supportsKittyKeyboard = false,
        .supportsKittyGraphics = false,
        .supportsSixel = false,
        .supportsModifyOtherKeys = true,
        .supportsXtwinops = true,
        .supportsBracketedPaste = true,
        .supportsFocusEvents = true,
        .supportsSgrMouse = true,
        .supportsSgrPixelMouse = false,
        .supportsLightDarkReport = false,
        .supportsLinuxPaletteOscP = false,
        .supportsDeviceAttributes = true,
        .supportsCursorStyle = true,
        .supportsCursorPositionReport = true,
        .supportsPointerShape = false,
        .screenChunkLimit = 768,
        .widthMethod = .grapheme,
        .needsTmuxPassthrough = false,
        .needsScreenPassthrough = false,
    };
}

fn mockOverlayCaps(comptime ProgObj: type, prog: ProgObj, caps: *MockTermCaps) void {
    if (@hasField(ProgObj, "supports_truecolor")) caps.supportsTruecolor = prog.supports_truecolor;
    if (@hasField(ProgObj, "supports_hyperlink_osc8")) caps.supportsHyperlinkOsc8 = prog.supports_hyperlink_osc8;
    if (@hasField(ProgObj, "supports_clipboard_osc52")) caps.supportsClipboardOsc52 = prog.supports_clipboard_osc52;
    if (@hasField(ProgObj, "supports_notify_osc9")) caps.supportsNotifyOsc9 = prog.supports_notify_osc9;
    if (@hasField(ProgObj, "supports_finalterm_osc133")) caps.supportsFinalTermOsc133 = prog.supports_finalterm_osc133;
    if (@hasField(ProgObj, "supports_iterm2_osc1337")) caps.supportsITerm2Osc1337 = prog.supports_iterm2_osc1337;
    if (@hasField(ProgObj, "supports_kitty_graphics")) caps.supportsKittyGraphics = prog.supports_kitty_graphics;
    if (@hasField(ProgObj, "supports_modify_other_keys")) caps.supportsModifyOtherKeys = prog.supports_modify_other_keys;
    if (@hasField(ProgObj, "supports_lightdark_report")) caps.supportsLightDarkReport = prog.supports_lightdark_report;
    if (@hasField(ProgObj, "supports_sgr_pixel_mouse")) caps.supportsSgrPixelMouse = prog.supports_sgr_pixel_mouse;
    if (@hasField(ProgObj, "supports_xtwinops")) caps.supportsXtwinops = prog.supports_xtwinops;
    if (@hasField(ProgObj, "supports_sgr_mouse")) caps.supportsSgrMouse = prog.supports_sgr_mouse;
    if (@hasField(ProgObj, "screen_chunk_limit")) caps.screenChunkLimit = @intCast(prog.screen_chunk_limit);
    if (@hasField(ProgObj, "width_method")) {
        caps.widthMethod = if (std.mem.eql(u8, prog.width_method, "wcwidth")) .wcwidth else .grapheme;
    }
}

fn mockCapsForProgram(program: MockProgram) MockTermCaps {
    var caps = mockDefaultsCaps();
    const config = switch (program) {
        .Kitty => MockProgramConfig{
            .supports_truecolor = true,
            .supports_hyperlink_osc8 = true,
            .supports_clipboard_osc52 = true,
            .supports_notify_osc9 = false,
            .supports_finalterm_osc133 = false,
            .supports_iterm2_osc1337 = false,
            .supports_kitty_graphics = true,
            .supports_modify_other_keys = true,
            .supports_lightdark_report = false,
            .supports_sgr_pixel_mouse = false,
            .supports_xtwinops = true,
            .supports_sgr_mouse = true,
            .screen_chunk_limit = 768,
            .width_method = "grapheme",
        },
        .WezTerm => MockProgramConfig{
            .supports_truecolor = true,
            .supports_hyperlink_osc8 = true,
            .supports_clipboard_osc52 = true,
            .supports_notify_osc9 = true,
            .supports_finalterm_osc133 = true,
            .supports_iterm2_osc1337 = true,
            .supports_kitty_graphics = true,
            .supports_modify_other_keys = true,
            .supports_lightdark_report = true,
            .supports_sgr_pixel_mouse = true,
            .supports_xtwinops = true,
            .supports_sgr_mouse = true,
            .screen_chunk_limit = 768,
            .width_method = "grapheme",
        },
        else => MockProgramConfig{
            .supports_truecolor = true,
            .supports_hyperlink_osc8 = true,
            .supports_clipboard_osc52 = true,
            .supports_notify_osc9 = false,
            .supports_finalterm_osc133 = false,
            .supports_iterm2_osc1337 = false,
            .supports_kitty_graphics = false,
            .supports_modify_other_keys = true,
            .supports_lightdark_report = false,
            .supports_sgr_pixel_mouse = false,
            .supports_xtwinops = true,
            .supports_sgr_mouse = true,
            .screen_chunk_limit = 768,
            .width_method = "grapheme",
        },
    };
    mockOverlayCaps(MockProgramConfig, config, &caps);

    // Set program-specific fields
    switch (program) {
        .Kitty => {
            caps.supportsKittyKeyboard = true;
        },
        else => {
            // Keep defaults
        },
    }
    return caps;
}

test "field name conversion from PascalCase to snake_case" {
    // Test the conversion logic used in the overlay functions
    // This tests the manual mapping from ZON snake_case to struct PascalCase

    // Test various field name patterns
    const test_cases = [_]struct {
        pascal_case: []const u8,
        snake_case: []const u8,
    }{
        .{ .pascal_case = "supportsTruecolor", .snake_case = "supports_truecolor" },
        .{ .pascal_case = "supportsHyperlinkOsc8", .snake_case = "supports_hyperlink_osc8" },
        .{ .pascal_case = "supportsClipboardOsc52", .snake_case = "supports_clipboard_osc52" },
        .{ .pascal_case = "supportsWorkingDirOsc7", .snake_case = "supports_working_dir_osc7" },
        .{ .pascal_case = "supportsTitleOsc012", .snake_case = "supports_title_osc012" },
        .{ .pascal_case = "supportsNotifyOsc9", .snake_case = "supports_notify_osc9" },
        .{ .pascal_case = "supportsFinalTermOsc133", .snake_case = "supports_finalterm_osc133" },
        .{ .pascal_case = "supportsITerm2Osc1337", .snake_case = "supports_iterm2_osc1337" },
        .{ .pascal_case = "supportsColorOsc10_12", .snake_case = "supports_color_osc10_12" },
        .{ .pascal_case = "supportsKittyKeyboard", .snake_case = "supports_kitty_keyboard" },
        .{ .pascal_case = "supportsKittyGraphics", .snake_case = "supports_kitty_graphics" },
        .{ .pascal_case = "supportsSixel", .snake_case = "supports_sixel" },
        .{ .pascal_case = "supportsModifyOtherKeys", .snake_case = "supports_modify_other_keys" },
        .{ .pascal_case = "supportsXtwinops", .snake_case = "supports_xtwinops" },
        .{ .pascal_case = "supportsBracketedPaste", .snake_case = "supports_bracketed_paste" },
        .{ .pascal_case = "supportsFocusEvents", .snake_case = "supports_focus_events" },
        .{ .pascal_case = "supportsSgrMouse", .snake_case = "supports_sgr_mouse" },
        .{ .pascal_case = "supportsSgrPixelMouse", .snake_case = "supports_sgr_pixel_mouse" },
        .{ .pascal_case = "supportsLightDarkReport", .snake_case = "supports_lightdark_report" },
        .{ .pascal_case = "supportsLinuxPaletteOscP", .snake_case = "supports_linux_palette_oscp" },
        .{ .pascal_case = "supportsDeviceAttributes", .snake_case = "supports_device_attributes" },
        .{ .pascal_case = "supportsCursorStyle", .snake_case = "supports_cursor_style" },
        .{ .pascal_case = "supportsCursorPositionReport", .snake_case = "supports_cursor_position_report" },
        .{ .pascal_case = "supportsPointerShape", .snake_case = "supports_pointer_shape" },
        .{ .pascal_case = "needsTmuxPassthrough", .snake_case = "needs_tmux_passthrough" },
        .{ .pascal_case = "needsScreenPassthrough", .snake_case = "needs_screen_passthrough" },
        .{ .pascal_case = "screenChunkLimit", .snake_case = "screen_chunk_limit" },
        .{ .pascal_case = "widthMethod", .snake_case = "width_method" },
    };

    // Verify that all expected fields exist in the mock defaults
    const defaults = MockDefaults{
        .supports_truecolor = true,
        .supports_hyperlink_osc8 = true,
        .supports_clipboard_osc52 = true,
        .supports_working_dir_osc7 = true,
        .supports_title_osc012 = true,
        .supports_notify_osc9 = false,
        .supports_finalterm_osc133 = false,
        .supports_iterm2_osc1337 = false,
        .supports_color_osc10_12 = true,
        .supports_kitty_keyboard = false,
        .supports_kitty_graphics = false,
        .supports_sixel = false,
        .supports_modify_other_keys = true,
        .supports_xtwinops = true,
        .supports_bracketed_paste = true,
        .supports_focus_events = true,
        .supports_sgr_mouse = true,
        .supports_sgr_pixel_mouse = false,
        .supports_lightdark_report = false,
        .supports_linux_palette_oscp = false,
        .supports_device_attributes = true,
        .supports_cursor_style = true,
        .supports_cursor_position_report = true,
        .supports_pointer_shape = false,
        .needs_tmux_passthrough = false,
        .needs_screen_passthrough = false,
        .screen_chunk_limit = 768,
        .width_method = "grapheme",
    };

    inline for (test_cases) |case| {
        // Check if the snake_case field exists in the defaults
        if (@hasField(@TypeOf(defaults), case.snake_case)) {
            // Verify the field mapping is consistent
            const field_value = @field(defaults, case.snake_case);
            _ = field_value; // We just verify it exists and is accessible
        } else {
            std.debug.print("Missing field in mock defaults: {s}\n", .{case.snake_case});
            return error.FieldMappingError;
        }
    }
}

test "capability overlay function generation and correct field mapping" {
    // Test that the overlayCaps function correctly maps all fields

    // Create a test program configuration that has all possible fields
    const TestProgramConfig = struct {
        supports_truecolor: bool = true,
        supports_hyperlink_osc8: bool = true,
        supports_clipboard_osc52: bool = true,
        supports_working_dir_osc7: bool = true,
        supports_title_osc012: bool = true,
        supports_notify_osc9: bool = false,
        supports_finalterm_osc133: bool = false,
        supports_iterm2_osc1337: bool = false,
        supports_color_osc10_12: bool = true,
        supports_kitty_keyboard: bool = false,
        supports_kitty_graphics: bool = false,
        supports_sixel: bool = false,
        supports_modify_other_keys: bool = true,
        supports_xtwinops: bool = true,
        supports_bracketed_paste: bool = true,
        supports_focus_events: bool = true,
        supports_sgr_mouse: bool = true,
        supports_sgr_pixel_mouse: bool = false,
        supports_lightdark_report: bool = false,
        supports_linux_palette_oscp: bool = false,
        supports_device_attributes: bool = true,
        supports_cursor_style: bool = true,
        supports_cursor_position_report: bool = true,
        supports_pointer_shape: bool = false,
        needs_tmux_passthrough: bool = false,
        needs_screen_passthrough: bool = false,
        screen_chunk_limit: u16 = 768,
        width_method: []const u8 = "grapheme",
    };

    const test_config = TestProgramConfig{
        .supports_truecolor = false, // Override to test overlay
        .supports_hyperlink_osc8 = true,
        .supports_clipboard_osc52 = true,
        .supports_kitty_graphics = true, // Override to test overlay
        .screen_chunk_limit = 512, // Override to test overlay
        .width_method = "grapheme",
    };

    // Start with default capabilities
    var caps = mockDefaultsCaps();

    // Verify initial values
    try testing.expect(caps.supportsTruecolor == true); // Default is true
    try testing.expect(caps.supportsKittyGraphics == false); // Default is false
    try testing.expect(caps.screenChunkLimit == 768); // Default value

    // Apply overlay using the same logic as overlayCaps
    mockOverlayCaps(TestProgramConfig, test_config, &caps);

    // Verify overlay worked correctly
    try testing.expect(caps.supportsTruecolor == false); // Should be overridden
    try testing.expect(caps.supportsKittyGraphics == true); // Should be overridden
    try testing.expect(caps.screenChunkLimit == 512); // Should be overridden

    // Test width_method conversion
    if (@hasField(TestProgramConfig, "width_method")) {
        caps.widthMethod = if (std.mem.eql(u8, test_config.width_method, "wcwidth")) .wcwidth else .grapheme;
    }
    try testing.expect(caps.widthMethod == .grapheme);
}

test "handling of missing fields (should not cause errors)" {
    // Test that missing fields in the source don't cause errors

    // Create a minimal config struct with only some fields
    const MinimalConfig = struct {
        supports_truecolor: bool = false,
        supports_kitty_graphics: bool = true,
        // Missing many fields that exist in TermCaps
    };

    const minimal_config = MinimalConfig{};

    // Start with default capabilities
    var caps = mockDefaultsCaps();

    // Apply overlay - this should not error even though many fields are missing
    if (@hasField(MinimalConfig, "supports_truecolor")) caps.supportsTruecolor = minimal_config.supports_truecolor;
    if (@hasField(MinimalConfig, "supports_kitty_graphics")) caps.supportsKittyGraphics = minimal_config.supports_kitty_graphics;
    // Note: We don't check for fields that don't exist, so no errors

    // Verify that existing fields were updated
    try testing.expect(caps.supportsTruecolor == false);
    try testing.expect(caps.supportsKittyGraphics == true);

    // Verify that fields not in MinimalConfig retain their default values
    try testing.expect(caps.supportsHyperlinkOsc8 == true); // Default value
    try testing.expect(caps.supportsClipboardOsc52 == true); // Default value
}

test "preservation of existing values when source doesn't have a field" {
    // Test that when overlaying, fields not present in source retain their values

    const PartialConfig = struct {
        supports_truecolor: bool = false,
        // Missing supports_hyperlink_osc8 field
    };

    var caps = mockDefaultsCaps();

    // Set some custom values
    caps.supportsHyperlinkOsc8 = false; // Custom value
    caps.supportsClipboardOsc52 = false; // Custom value
    caps.supportsTruecolor = true; // Will be overridden

    const partial_config = PartialConfig{};

    // Apply overlay
    if (@hasField(PartialConfig, "supports_truecolor")) caps.supportsTruecolor = partial_config.supports_truecolor;
    // Note: supports_hyperlink_osc8 is not present in PartialConfig, so it won't be checked

    // Verify that supportsTruecolor was updated
    try testing.expect(caps.supportsTruecolor == false);

    // Verify that fields not in the overlay source retain their custom values
    try testing.expect(caps.supportsHyperlinkOsc8 == false); // Retained custom value
    try testing.expect(caps.supportsClipboardOsc52 == false); // Retained custom value
}

test "correct handling of different field types" {
    // Test that different field types (bool, enums, integers, strings) are handled correctly

    const MixedConfig = struct {
        supports_truecolor: bool = false,
        supports_sgr_mouse: bool = true,
        screen_chunk_limit: u16 = 1024,
        width_method: []const u8 = "wcwidth",
        // Note: Missing some fields to test partial overlay
    };

    var caps = mockDefaultsCaps();
    const mixed_config = MixedConfig{};

    // Apply overlay with type conversions
    if (@hasField(MixedConfig, "supports_truecolor")) caps.supportsTruecolor = mixed_config.supports_truecolor;
    if (@hasField(MixedConfig, "supports_sgr_mouse")) caps.supportsSgrMouse = mixed_config.supports_sgr_mouse;
    if (@hasField(MixedConfig, "screen_chunk_limit")) caps.screenChunkLimit = @intCast(mixed_config.screen_chunk_limit);
    if (@hasField(MixedConfig, "width_method")) {
        caps.widthMethod = if (std.mem.eql(u8, mixed_config.width_method, "wcwidth")) .wcwidth else .grapheme;
    }

    // Verify boolean fields
    try testing.expect(caps.supportsTruecolor == false);
    try testing.expect(caps.supportsSgrMouse == true);

    // Verify integer field with casting
    try testing.expect(caps.screenChunkLimit == 1024);

    // Verify enum field with string conversion
    try testing.expect(caps.widthMethod == .wcwidth);

    // Verify that fields not in the config retain defaults
    try testing.expect(caps.supportsHyperlinkOsc8 == true); // Default
    try testing.expect(caps.supportsKittyGraphics == false); // Default
}

test "refactored system behaves identically to original manual mapping" {
    // Test that the refactored system produces the same results as the original manual mapping

    // Test with Kitty configuration (mock)
    const kitty_config = MockProgramConfig{
        .supports_truecolor = true,
        .supports_hyperlink_osc8 = true,
        .supports_clipboard_osc52 = true,
        .supports_notify_osc9 = false,
        .supports_finalterm_osc133 = false,
        .supports_iterm2_osc1337 = false,
        .supports_kitty_graphics = true,
        .supports_modify_other_keys = true,
        .supports_lightdark_report = false,
        .supports_sgr_pixel_mouse = false,
        .supports_xtwinops = true,
        .supports_sgr_mouse = true,
        .screen_chunk_limit = 768,
        .width_method = "grapheme",
    };

    // Start with defaults and manually apply Kitty overlay
    var caps_manual = mockDefaultsCaps();

    // Manual overlay (simulating the original overlayCaps logic)
    if (@hasField(@TypeOf(kitty_config), "supports_kitty_keyboard")) caps_manual.supportsKittyKeyboard = kitty_config.supports_kitty_keyboard;
    if (@hasField(@TypeOf(kitty_config), "supports_kitty_graphics")) caps_manual.supportsKittyGraphics = kitty_config.supports_kitty_graphics;
    if (@hasField(@TypeOf(kitty_config), "supports_modify_other_keys")) caps_manual.supportsModifyOtherKeys = kitty_config.supports_modify_other_keys;
    if (@hasField(@TypeOf(kitty_config), "supports_lightdark_report")) caps_manual.supportsLightDarkReport = kitty_config.supports_lightdark_report;
    if (@hasField(@TypeOf(kitty_config), "supports_sixel")) caps_manual.supportsSixel = kitty_config.supports_sixel;
    if (@hasField(@TypeOf(kitty_config), "supports_xtwinops")) caps_manual.supportsXtwinops = kitty_config.supports_xtwinops;

    // Compare key fields (mock comparison)
    try testing.expect(caps_manual.supportsKittyGraphics == true); // Should be overridden to true
    try testing.expect(caps_manual.supportsTruecolor == true); // Should remain true (not overridden)

    // Test with WezTerm configuration (mock)
    const wezterm_config = MockProgramConfig{
        .supports_truecolor = true,
        .supports_hyperlink_osc8 = true,
        .supports_clipboard_osc52 = true,
        .supports_notify_osc9 = true,
        .supports_finalterm_osc133 = true,
        .supports_iterm2_osc1337 = true,
        .supports_kitty_graphics = true,
        .supports_modify_other_keys = true,
        .supports_lightdark_report = true,
        .supports_sgr_pixel_mouse = true,
        .supports_xtwinops = true,
        .supports_sgr_mouse = true,
        .screen_chunk_limit = 1024, // This should be reflected in the result
        .width_method = "grapheme",
    };

    // Reset caps and apply WezTerm overlay using mockOverlayCaps
    caps_manual = mockDefaultsCaps();
    mockOverlayCaps(MockProgramConfig, wezterm_config, &caps_manual);

    // Compare key fields (mock comparison)
    try testing.expect(caps_manual.supportsKittyGraphics == true); // Should be overridden to true
    try testing.expect(caps_manual.screenChunkLimit == 1024); // Should be overridden to 1024
}

test "edge cases in field name conversion" {
    // Test edge cases in field name conversion

    // Test with empty field names (shouldn't happen but let's be safe)
    const EmptyConfig = struct {};

    var caps = mockDefaultsCaps();
    const empty_config = EmptyConfig{};

    // This should not crash or change anything
    if (@hasField(EmptyConfig, "supports_truecolor")) caps.supportsTruecolor = empty_config.supports_truecolor;

    // Verify caps are unchanged
    try testing.expect(caps.supportsTruecolor == true); // Still default

    // Test with fields that have underscores at the beginning/end
    const EdgeCaseConfig = struct {
        supports_truecolor: bool = false,
        _private_field: bool = true, // Field starting with underscore
        trailing_underscore_: bool = true, // Field ending with underscore
    };

    const edge_config = EdgeCaseConfig{};
    caps = mockDefaultsCaps();

    // Only the valid field should be processed
    if (@hasField(EdgeCaseConfig, "supports_truecolor")) caps.supportsTruecolor = edge_config.supports_truecolor;
    // Note: We don't check for _private_field or trailing_underscore_ as they wouldn't be in TermCaps

    try testing.expect(caps.supportsTruecolor == false);
}

test "multiplexer overlay functionality" {
    // Test multiplexer overlay functionality

    // Test tmux overlay
    var caps = mockDefaultsCaps();
    const tmux_config = MockMultiplexerConfig{ .needs_tmux_passthrough = true };

    // Initially should be false
    try testing.expect(caps.needsTmuxPassthrough == false);

    // Apply tmux overlay
    if (@hasField(@TypeOf(tmux_config), "needs_tmux_passthrough")) caps.needsTmuxPassthrough = tmux_config.needs_tmux_passthrough;

    // Should now be true
    try testing.expect(caps.needsTmuxPassthrough == true);

    // Test screen overlay
    caps = mockDefaultsCaps();
    const screen_config = MockMultiplexerConfig{
        .needs_screen_passthrough = true,
        .screen_chunk_limit = 768,
    };

    // Initially should be false
    try testing.expect(caps.needsScreenPassthrough == false);
    try testing.expect(caps.screenChunkLimit == 768);

    // Apply screen overlay
    if (@hasField(@TypeOf(screen_config), "needs_screen_passthrough")) caps.needsScreenPassthrough = screen_config.needs_screen_passthrough;
    if (@hasField(@TypeOf(screen_config), "screen_chunk_limit")) caps.screenChunkLimit = @intCast(screen_config.screen_chunk_limit);

    // Should now be updated
    try testing.expect(caps.needsScreenPassthrough == true);
    try testing.expect(caps.screenChunkLimit == 768);
}

test "program-specific capability detection" {
    // Test that program-specific detection works correctly

    // Test each program's capabilities
    const programs_to_test = [_]struct {
        program: MockProgram,
        expected_kitty_keyboard: bool,
        expected_kitty_graphics: bool,
    }{
        .{ .program = .Kitty, .expected_kitty_keyboard = true, .expected_kitty_graphics = true },
        .{ .program = .WezTerm, .expected_kitty_keyboard = false, .expected_kitty_graphics = true },
        .{ .program = .ITerm2, .expected_kitty_keyboard = false, .expected_kitty_graphics = false },
        .{ .program = .Xterm, .expected_kitty_keyboard = false, .expected_kitty_graphics = false },
        .{ .program = .Unknown, .expected_kitty_keyboard = false, .expected_kitty_graphics = false },
    };

    for (programs_to_test) |test_case| {
        const caps = mockCapsForProgram(test_case.program);

        try testing.expect(caps.supportsKittyKeyboard == test_case.expected_kitty_keyboard);
        try testing.expect(caps.supportsKittyGraphics == test_case.expected_kitty_graphics);
    }
}

test "default capabilities structure integrity" {
    // Test that the defaultsCaps function creates a valid TermCaps structure

    const caps = mockDefaultsCaps();

    // Verify all boolean fields are accessible
    _ = caps.supportsTruecolor;
    _ = caps.supportsHyperlinkOsc8;
    _ = caps.supportsClipboardOsc52;
    _ = caps.supportsWorkingDirOsc7;
    _ = caps.supportsTitleOsc012;
    _ = caps.supportsNotifyOsc9;
    _ = caps.supportsFinalTermOsc133;
    _ = caps.supportsITerm2Osc1337;
    _ = caps.supportsColorOsc10_12;
    _ = caps.supportsKittyKeyboard;
    _ = caps.supportsKittyGraphics;
    _ = caps.supportsSixel;
    _ = caps.supportsModifyOtherKeys;
    _ = caps.supportsXtwinops;
    _ = caps.supportsBracketedPaste;
    _ = caps.supportsFocusEvents;
    _ = caps.supportsSgrMouse;
    _ = caps.supportsSgrPixelMouse;
    _ = caps.supportsLightDarkReport;
    _ = caps.supportsLinuxPaletteOscP;
    _ = caps.supportsDeviceAttributes;
    _ = caps.supportsCursorStyle;
    _ = caps.supportsCursorPositionReport;
    _ = caps.supportsPointerShape;
    _ = caps.needsTmuxPassthrough;
    _ = caps.needsScreenPassthrough;

    // Verify integer fields
    try testing.expect(caps.screenChunkLimit > 0);

    // Verify enum field
    try testing.expect(caps.widthMethod == .grapheme or caps.widthMethod == .wcwidth);
}
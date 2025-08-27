//! Unified Terminal Module with Feature Gating and Backward Compatibility
//!
//! This module provides a consolidated interface to all terminal functionality
//! with feature gating for optional modules and backward compatibility aliases.
//!
//! ## Architecture
//!
//! The module is organized into logical submodules:
//! - **Core**: Always available (capabilities, cellbuf, screen, etc.)
//! - **ANSI**: ANSI escape sequences and terminal control
//! - **Color**: Color management and conversion
//! - **Control**: Cursor and screen control
//! - **Input**: Keyboard, mouse, and input handling
//! - **Graphics**: Optional graphics capabilities (feature-gated)
//! - **Shell**: Optional shell integration (feature-gated)
//! - **Unicode**: Optional Unicode handling (feature-gated)
//! - **Query**: Terminal querying capabilities
//!
//! ## Feature Gating
//!
//! Optional modules are conditionally exported based on build options:
//! - `graphics`: Enable with `-Dterm_graphics`
//! - `shell`: Enable with `-Dterm_shell`
//! - `unicode`: Enable with `-Dterm_unicode`
//!
//! ## Backward Compatibility
//!
//! Legacy import paths are maintained through aliases:
//! - `ansi/*` modules available as `term.ansi.*`
//! - Old submodule names preserved where possible

const std = @import("std");

// ============================================================================
// CORE FUNCTIONALITY (Always Available)
// ============================================================================

// Core terminal capabilities and detection
pub const capabilities = @import("capabilities.zig");
pub const caps = capabilities; // Alias for backward compatibility

// Terminal management and utilities
pub const cellbuf = @import("cellbuf.zig");
pub const pty = @import("pty.zig");
pub const writer = @import("writer.zig");
pub const reader = @import("reader.zig");
pub const screen = @import("screen.zig");
pub const term = @import("term.zig");
pub const termcaps = @import("termcaps.zon");
pub const terminfo = @import("terminfo.zig");
pub const termios = @import("termios.zig");

// Terminal features
pub const bracketed_paste = @import("bracketed_paste.zig");
pub const grapheme = @import("grapheme.zig");
pub const wcwidth = @import("wcwidth.zig");
pub const reflection = @import("reflection.zig");
pub const state = @import("state.zig");
pub const tab_processor = @import("tab_processor.zig");

// ============================================================================
// ANSI SUBMODULE (Always Available)
// ============================================================================

// ANSI escape sequence handling
pub const ansi = @import("ansi/mod.zig");

// ============================================================================
// COLOR SUBMODULE (Always Available)
// ============================================================================

// Color management system
pub const color = @import("color/mod.zig");

// ============================================================================
// CONTROL SUBMODULE (Always Available)
// ============================================================================

// Cursor and screen control
pub const control = @import("control/mod.zig");

// ============================================================================
// INPUT SUBMODULE (Always Available)
// ============================================================================

// Input handling system
pub const input = @import("input/mod.zig");

// ============================================================================
// QUERY SUBMODULE (Always Available)
// ============================================================================

// Terminal querying capabilities
pub const query = @import("query/mod.zig");

// ============================================================================
// FEATURE FLAGS (Can be overridden by build system)
// ============================================================================

/// Enable graphics capabilities (can be overridden by build system)
pub const graphics_enabled = if (@hasDecl(std.builtin, "term_graphics"))
    std.builtin.term_graphics
else
    true; // Default to enabled

/// Enable shell integration (can be overridden by build system)
pub const shell_enabled = if (@hasDecl(std.builtin, "term_shell"))
    std.builtin.term_shell
else
    true; // Default to enabled

/// Enable unicode handling (can be overridden by build system)
pub const unicode_enabled = if (@hasDecl(std.builtin, "term_unicode"))
    std.builtin.term_unicode
else
    true; // Default to enabled

// ============================================================================
// OPTIONAL MODULES (Feature-Gated)
// ============================================================================

// Graphics capabilities - conditionally exported based on feature flag
pub const graphics = if (graphics_enabled)
    @import("graphics/mod.zig")
else
    // Provide stub implementation when graphics is disabled
    struct {
        pub const Graphics = struct {
            pub fn init() !Graphics {
                return error.GraphicsNotEnabled;
            }
        };
        pub const Error = error{GraphicsNotEnabled};
    };

// Shell integration - conditionally exported based on feature flag
pub const shell = if (shell_enabled)
    @import("shell_integration.zig")
else
    // Provide stub implementation when shell integration is disabled
    struct {
        pub const ShellIntegration = struct {
            pub fn init() !ShellIntegration {
                return error.ShellIntegrationNotEnabled;
            }
        };
        pub const Error = error{ShellIntegrationNotEnabled};
    };

// Unicode handling - conditionally exported based on feature flag
pub const unicode = if (unicode_enabled)
    struct {
        pub const detector = @import("unicode_detector.zig");
        pub const image_renderer = @import("unicode_image_renderer.zig");
        pub const width = wcwidth; // Alias for backward compatibility
    }
else
    // Provide stub implementation when unicode is disabled
    struct {
        pub const detector = struct {
            pub const UnicodeDetector = struct {
                pub fn init() !UnicodeDetector {
                    return error.UnicodeNotEnabled;
                }
            };
            pub const Error = error{UnicodeNotEnabled};
        };
        pub const image_renderer = detector; // Same stub
        pub const width = wcwidth; // Always available
    };

// ============================================================================
// BACKWARD COMPATIBILITY ALIASES
// ============================================================================

// Legacy ANSI submodule access
pub const ansi_color = ansi.color;
pub const ansi_control = ansi.screen_control;
pub const ansi_graphics = ansi.graphics;
pub const ansi_sixel = ansi.sixel_graphics;
pub const ansi_hyperlink = ansi.hyperlink;
pub const ansi_notification = ansi.notification;
pub const ansi_mode = ansi.mode;
pub const ansi_reset = ansi.reset;
pub const ansi_charset = ansi.charset;
pub const ansi_control_chars = ansi.control_chars;
pub const ansi_device_attributes = ansi.device_attributes;
pub const ansi_focus = ansi.focus;
pub const ansi_keypad = ansi.keypad;
pub const ansi_palette = ansi.palette;
pub const ansi_pointer = ansi.pointer;
pub const ansi_sgr = ansi.sgr;
pub const ansi_status = ansi.status;
pub const ansi_title = ansi.title;
pub const ansi_width = ansi.width;
pub const ansi_wrap = ansi.wrap;
pub const ansi_xterm = ansi.xterm;
pub const ansi_kitty = ansi.kitty;
pub const ansi_iterm2 = ansi.iterm2;
pub const ansi_iterm2_images = ansi.iterm2_images;
pub const ansi_iterm2_shell_integration = ansi.iterm2_shell_integration;
pub const ansi_finalterm = ansi.finalterm;
pub const ansi_ghostty = ansi.ghostty;
pub const ansi_background = ansi.background;
pub const ansi_bidirectional_text = ansi.bidirectional_text;
pub const ansi_cwd = ansi.cwd;
pub const ansi_keys = ansi.keys;
pub const ansi_kitty_graphics = ansi.kitty_graphics;
pub const ansi_advanced_features = ansi.advanced_features;
pub const ansi_passthrough = ansi.passthrough;
pub const ansi_shell_integration = ansi.shell_integration;
pub const ansi_color_structures = ansi.color_structures;
pub const ansi_background_control = ansi.background_control;
pub const ansi_color_control = ansi.color_control;
pub const ansi_truncate = ansi.truncate;
pub const ansi_winop = ansi.winop;
pub const ansi_queries = ansi.queries;

// Legacy color submodule access
pub const color_conversions = color.conversions;
pub const color_types = color.types;

// Legacy control submodule access
pub const cursor = control.cursor;
pub const screen_control = control.screen;

// Legacy input submodule access
pub const input_types = input.types;
pub const input_parser = input.parser;
pub const input_key_mapping = input.key_mapping;
pub const input_kitty_keyboard = input.kitty_keyboard;
pub const input_mouse = input.mouse;
pub const input_color_events = input.color_events;
pub const input_focus = input.focus;
pub const input_paste = input.paste;
pub const input_mouse_events = input.mouse_events;
pub const input_input_events = input.input_events;

// Legacy query submodule access
pub const query_system = query.system;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Initialize terminal capabilities detection
pub fn initTermCaps() !void {
    // Initialize core capabilities
    try capabilities.init();
}

/// Deinitialize terminal capabilities
pub fn deinitTermCaps() void {
    capabilities.deinit();
}

/// Get current terminal capabilities
pub fn getTermCaps() capabilities.TermCaps {
    return capabilities.getTermCaps();
}

/// Check if a feature is available
pub fn hasFeature(feature: capabilities.Feature) bool {
    return capabilities.hasFeature(feature);
}

// ============================================================================
// TESTS
// ============================================================================

test "term module exports" {
    // Test core exports
    std.testing.refAllDecls(capabilities);
    std.testing.refAllDecls(cellbuf);
    std.testing.refAllDecls(pty);
    std.testing.refAllDecls(writer);
    std.testing.refAllDecls(reader);
    std.testing.refAllDecls(screen);
    std.testing.refAllDecls(term);
    std.testing.refAllDecls(bracketed_paste);
    std.testing.refAllDecls(grapheme);
    std.testing.refAllDecls(wcwidth);
    std.testing.refAllDecls(reflection);
    std.testing.refAllDecls(state);
    std.testing.refAllDecls(tab_processor);

    // Test ANSI submodule
    std.testing.refAllDecls(ansi);

    // Test color submodule
    std.testing.refAllDecls(color);

    // Test control submodule
    std.testing.refAllDecls(control);

    // Test input submodule
    std.testing.refAllDecls(input);

    // Test query submodule
    std.testing.refAllDecls(query);

    // Test backward compatibility aliases
    std.testing.refAllDecls(ansi_color);
    std.testing.refAllDecls(ansi_control);
    std.testing.refAllDecls(color_conversions);
    std.testing.refAllDecls(cursor);
    std.testing.refAllDecls(input_types);
}

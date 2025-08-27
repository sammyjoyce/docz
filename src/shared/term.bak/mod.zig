//! Terminal Module - Consolidated Structure
//!
//! This module provides a clean, organized interface to all terminal functionality
//! following the newly consolidated architecture.
//!
//! ## Architecture
//!
//! The module is organized into logical subsystems:
//! - **Core**: Always available (capabilities, cellbuf, screen, term, etc.)
//! - **ANSI**: ANSI escape sequences and terminal control
//! - **Color**: Color management, conversion, and palettes
//! - **Graphics**: Graphics protocols (Kitty, Unicode blocks)
//! - **Control**: Cursor and screen control
//! - **Input**: Keyboard, mouse, and all input event handling
//! - **Shell**: Shell integration (iTerm2, FinalTerm, prompts)
//! - **Query**: Terminal querying capabilities
//!
//! ## Feature Gating
//!
//! Optional modules can be conditionally disabled via build options:
//! - `graphics`: Disable with `-Dno_term_graphics`
//! - `shell`: Disable with `-Dno_term_shell`
//! - `unicode`: Disable with `-Dno_term_unicode`
//!
//! ## Backward Compatibility
//!
//! Legacy import paths are maintained through aliases where possible.
//! Some modules have been reorganized for better structure.

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
pub const bracketed_paste = @import("BracketedPaste.zig");
pub const grapheme = @import("grapheme.zig");
pub const wcwidth = @import("wcwidth.zig");
pub const reflection = @import("reflection.zig");
pub const state = @import("state.zig");
pub const tab = @import("tab.zig");

// ============================================================================
// SUBSYSTEMS (Always Available)
// ============================================================================

/// ANSI escape sequence handling
pub const ansi = @import("ansi/mod.zig");

/// Color management system (types, conversions, palettes, terminal colors)
/// Updated to use the new consolidated ANSI color module from term/ansi/color/
pub const color = @import("ansi/color/mod.zig");

/// Graphics protocols and capabilities (Kitty, Unicode blocks)
pub const graphics = @import("graphics/mod.zig");

/// Cursor and screen control
pub const control = @import("control/mod.zig");

/// Input handling system (keyboard, mouse, events)
pub const input = @import("input/mod.zig");

/// Shell integration (iTerm2, Term, prompts)
pub const shell = @import("shell/mod.zig");

/// Terminal querying capabilities
pub const query = @import("query/mod.zig");

// ============================================================================
// HIGH-LEVEL APIs (Always Available)
// ============================================================================

/// Cursor module (high-level API combining control and query)
pub const cursor = @import("cursor.zig");

// ============================================================================
// OPTIONAL MODULES (Feature-Gated if needed)
// ============================================================================

/// Unicode detection and rendering
pub const unicode = struct {
    pub const detector = @import("unicode.zig");
    pub const image_renderer = @import("UnicodeImage.zig");
    pub const width = wcwidth; // Alias for backward compatibility
};

// ============================================================================
// BACKWARD COMPATIBILITY ALIASES
// ============================================================================

// Legacy ANSI submodule access (maintaining backward compatibility)
pub const ansi_hyperlink = ansi.hyperlink;
pub const ansi_notification = ansi.notification;
pub const ansi_mode = ansi.mode;
pub const ansi_reset = ansi.reset;
pub const ansi_charset = ansi.charset;
pub const ansi_control_chars = ansi.control_chars;
pub const ansi_device_attributes = ansi.device_attributes;
pub const ansi_keypad = ansi.keypad;
pub const ansi_palette = ansi.color.osc_palette;
pub const ansi_pointer = ansi.pointer;
pub const ansi_sgr = ansi.sgr;
pub const ansi_status = ansi.status;
pub const ansi_title = ansi.title;
pub const ansi_width = ansi.width;
pub const ansi_wrap = ansi.wrap;
pub const ansi_xterm = ansi.xterm;
pub const ansi_kitty = ansi.kitty;
pub const ansi_iterm2 = ansi.iterm2;
pub const ansi_ghostty = ansi.ghostty;
pub const ansi_bidirectional_text = ansi.bidirectional_text;
pub const ansi_cwd = ansi.cwd;
pub const ansi_keys = ansi.keys;
pub const ansi_recent = ansi.recent;
pub const ansi_passthrough = ansi.passthrough;
pub const ansi_queries = ansi.queries;
pub const ansi_truncate = ansi.truncate;
pub const ansi_winop = ansi.winop;

// Shell integration modules have moved to shell/
pub const shell_iterm2 = shell.iterm2;
pub const shell_term = shell.term;
pub const shell_integration = shell.integration;
pub const shell_prompt = shell.prompt;

// Legacy color submodule access
pub const color_conversions = color.conversions;
pub const color_types = color.types;

// Legacy control submodule access (for backward compatibility)
pub const control_cursor = control.cursor;
pub const screen_control = control.screen;

// Legacy input submodule access
pub const input_types = input.types;
pub const input_parser = input.parser;
pub const input_key = input.key;
pub const KeyMapping = input.KeyMapping;
pub const Input = input.Input;
pub const input_kitty = input.kitty;
pub const KittyProtocol = input.KittyProtocol;
pub const Kitty = input.Kitty;
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
    std.testing.refAllDecls(tab);

    // Test subsystems
    std.testing.refAllDecls(ansi);
    std.testing.refAllDecls(color);
    std.testing.refAllDecls(graphics);
    std.testing.refAllDecls(control);
    std.testing.refAllDecls(input);
    std.testing.refAllDecls(shell);
    std.testing.refAllDecls(query);

    // Test high-level APIs
    std.testing.refAllDecls(cursor);
    std.testing.refAllDecls(unicode);

    // Test backward compatibility aliases
    std.testing.refAllDecls(color_conversions);
    std.testing.refAllDecls(color_types);
    std.testing.refAllDecls(control_cursor);
    std.testing.refAllDecls(input_types);
    std.testing.refAllDecls(input_parser);
    std.testing.refAllDecls(input_mouse);
}

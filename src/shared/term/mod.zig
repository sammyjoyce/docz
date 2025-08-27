//! Terminal capabilities module aggregator.
//! Provides access to terminal functionality including ANSI control sequences,
//! input handling, and terminal detection capabilities.
//!
//! This module organizes terminal functionality into logical submodules:
//! - ansi: ANSI escape sequences, colors, cursor control
//! - input: Keyboard, mouse, and clipboard input handling
//! - Core utilities: Terminal detection, capabilities, and management

const std = @import("std");

// Core terminal capabilities and detection - capabilities system
pub const capabilities = @import("capabilities.zig");
pub const caps = capabilities; // Alias for backward compatibility

// Terminal management
pub const cellbuf = @import("cellbuf.zig");
pub const graphics = @import("graphics.zig");
pub const editor = @import("editor.zig");
pub const pty = @import("pty.zig");
pub const writer = @import("writer.zig");
pub const reader = @import("reader.zig");

// Clipboard support is available through ansi/clipboard.zig (consolidated implementation)

// Terminal features
pub const bracketed_paste = @import("bracketed_paste.zig");
pub const grapheme = @import("grapheme.zig");
pub const wcwidth = @import("wcwidth.zig");

// Terminal color management
pub const terminal_color_management = @import("ansi/terminal_color_management.zig");
pub const precise_ansi_palette = @import("precise_ansi_palette.zig");

// ANSI submodule - All ANSI escape sequence handling
pub const ansi = @import("ansi/mod.zig");

// Input submodule - All input handling (keyboard, mouse, events)
pub const input = @import("input/mod.zig");

// Unified terminal interface
pub const term = @import("term.zig");

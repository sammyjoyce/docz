//! Terminal capabilities module aggregator.
//! Provides unified access to terminal functionality including ANSI control sequences,
//! input handling, and terminal detection capabilities.
//!
//! This module organizes terminal functionality into logical submodules:
//! - ansi: ANSI escape sequences, colors, cursor control
//! - input: Keyboard, mouse, and clipboard input handling
//! - Core utilities: Terminal detection, capabilities, and management

const std = @import("std");

// Core terminal capabilities and detection
pub const caps = @import("caps.zig");
pub const capability_detector = @import("capability_detector.zig");
pub const modern_terminal_detection = @import("modern_terminal_detection.zig");
pub const advanced_terminal_features = @import("advanced_terminal_features.zig");

// Terminal management
pub const cellbuf = @import("cellbuf.zig");
pub const enhanced_cellbuf = @import("enhanced_cellbuf.zig");
pub const graphics_manager = @import("graphics_manager.zig");
pub const editor = @import("editor.zig");
pub const pty = @import("pty.zig");
pub const unified = @import("unified.zig");

// Clipboard support
pub const enhanced_clipboard = @import("enhanced_clipboard.zig");

// Terminal features
pub const bracketed_paste = @import("bracketed_paste.zig");
pub const enhanced_terminal_capabilities = @import("enhanced_terminal_capabilities.zig");
pub const wcwidth = @import("wcwidth.zig");

// Terminal color management
// TODO: Implement terminal color management
// pub const terminal_color_management = @import("terminal_color_management.zig");
// TODO: Implement terminal query system
// pub const terminal_query_system = @import("terminal_query_system.zig");
pub const precise_ansi_palette = @import("precise_ansi_palette.zig");

// ANSI submodule - All ANSI escape sequence handling
pub const ansi = @import("ansi/mod.zig");

// Input submodule - All input handling (keyboard, mouse, events)
pub const input = @import("input/mod.zig");

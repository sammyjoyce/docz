//! Low-level Terminal Input Primitives
//!
//! This module provides the foundation layer for terminal input handling,
//! containing raw parsers, key definitions, mouse protocol handlers, and
//! other primitive input processing components.
//!
//! Architecture Layer: LOW-LEVEL PRIMITIVES
//! - Raw input parsing and protocol handling
//! - Key code definitions and mappings
//! - Mouse event protocol decoding
//! - Terminal capability detection
//! - Basic input stream processing
//!
//! This layer serves as the foundation for higher-level input abstraction
//! and should not be used directly by applications. Instead, use the
//!  input system from src/shared/components/input.zig.

const std = @import("std");

// Core type definitions - single source of truth
pub const types = @import("types.zig");
pub const Modifiers = types.Modifiers;
pub const Key = types.Key;
pub const KeyEvent = types.KeyEvent;
pub const KeyPressEvent = types.KeyPressEvent;
pub const KeyReleaseEvent = types.KeyReleaseEvent;
pub const MouseButton = types.MouseButton;
pub const MouseAction = types.MouseAction;
pub const MouseEvent = types.MouseEvent;
pub const CursorPositionEvent = types.CursorPositionEvent;
pub const FocusEvent = types.FocusEvent;

// Parser - input parsing implementation
pub const parser = @import("parser.zig");
pub const InputEvent = parser.InputEvent;
pub const InputParser = parser.InputParser;

// Additional low-level input module exports
pub const key_mapping = @import("key_mapping.zig");
pub const kitty_keyboard = @import("kitty_keyboard.zig");

pub const cursor = @import("../control/cursor.zig");
pub const color_events = @import("color_events.zig");
pub const focus = @import("focus.zig");
pub const paste = @import("paste.zig");
pub const mouse_events = @import("mouse_events.zig");
pub const input_events = @import("input_events.zig");
// Export mouse protocol module for higher-level imports
pub const mouse = @import("mouse.zig");

test "input module exports" {
    // Basic test to ensure module compiles
    std.testing.refAllDecls(@This());
}

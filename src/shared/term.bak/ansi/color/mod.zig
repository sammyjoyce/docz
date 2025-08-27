//! ANSI Color System - Consolidated color management for terminals
//!
//! This module provides a comprehensive color system supporting:
//! - RGB, HSL, HSV color representations and conversions
//! - ANSI 16 and 256 color palette management
//! - Color scheme definitions with semantic colors
//! - Accessibility features including color blindness simulation
//! - Terminal-specific color operations and OSC palette commands

/// Core color types (RGB, HSL, HSV, HexColor, Ansi16, Ansi256)
pub const types = @import("types.zig");

/// Color space conversions between RGB, HSL, HSV, and ANSI color codes
pub const conversions = @import("conversions.zig");

/// Color distance calculations for palette optimization and color matching
pub const distance = @import("distance.zig");

/// Predefined color palettes including ANSI standards and popular themes
pub const palettes = @import("palettes.zig");

/// Terminal-specific color formatting and ANSI escape sequence generation
pub const terminal = @import("terminal.zig");

/// Unified Color type with automatic ANSI conversion and manipulation methods
pub const color = @import("color.zig");

/// Color scheme definitions with complete theme management and serialization
pub const schemes = @import("schemes.zig");

/// Color blindness simulation and theme adaptation for accessibility
pub const accessibility = @import("accessibility.zig");

/// OSC palette commands for setting Linux console color registers
pub const osc_palette = @import("OscPalette.zig");

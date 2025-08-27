//! Graphics protocol implementations
//!
//! This module provides implementations for various terminal graphics protocols.

const std = @import("std");

// Protocol implementations
pub const sixel = @import("sixel.zig");
pub const kitty = @import("kitty.zig");
pub const iterm2 = @import("iterm2.zig");
pub const unicode = @import("unicode.zig");

// Re-export main types
pub const SixelRenderer = sixel.SixelRenderer;
pub const KittyRenderer = kitty.KittyRenderer;
pub const ITerm2Renderer = iterm2.ITerm2Renderer;
pub const UnicodeRenderer = unicode.UnicodeRenderer;

// Re-export protocol-specific options
pub const SixelOptions = sixel.SixelOptions;
pub const KittyOptions = kitty.KittyOptions;
pub const ITerm2Options = iterm2.ITerm2Options;
pub const UnicodeOptions = unicode.UnicodeOptions;
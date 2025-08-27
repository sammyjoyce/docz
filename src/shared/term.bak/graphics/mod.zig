//! Terminal Graphics Module
//!
//! This module provides graphics capabilities for terminals that support
//! graphics protocols like Sixel, Kitty graphics, and iTerm2 images.
//!
//! ## Supported Protocols
//!
//! - **Sixel**: HP's sixel graphics format for bitmap images
//! - **Kitty Graphics**: Modern graphics protocol with compression
//! - **iTerm2 Images**: Inline image display protocol
//! - **Block Graphics**: Unicode block characters for simple graphics

const std = @import("std");

// Re-export graphics modules from ansi submodule
pub const sixel = @import("../ansi/sixel_graphics.zig");
pub const kitty = @import("../ansi/kitty_graphics.zig");
pub const iterm2 = @import("../ansi/iterm2_images.zig");

// Additional graphics utilities
pub const graphics = @import("../graphics.zig");

// ============================================================================
// TYPE EXPORTS
// ============================================================================

pub const SixelGraphics = sixel.SixelGraphics;
pub const KittyGraphics = kitty.KittyGraphics;
pub const ITerm2Images = iterm2.ITerm2Images;
pub const Graphics = graphics.Graphics;

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Initialize graphics support with automatic protocol detection
pub fn init(allocator: std.mem.Allocator) !Graphics {
    return Graphics.init(allocator);
}

/// Check if graphics are supported by the current terminal
pub fn isSupported() bool {
    return graphics.isSupported();
}

/// Get the best graphics protocol for the current terminal
pub fn getBestProtocol() graphics.GraphicsProtocol {
    return graphics.getBestProtocol();
}

// ============================================================================
// TESTS
// ============================================================================

test "graphics module exports" {
    std.testing.refAllDecls(sixel);
    std.testing.refAllDecls(kitty);
    std.testing.refAllDecls(iterm2);
    std.testing.refAllDecls(graphics);
}

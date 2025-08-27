//! Graphics capability detection
//!
//! This module handles detection of terminal graphics capabilities
//! and selection of the best available protocol.

const std = @import("std");
const types = @import("types.zig");
const term_caps = @import("../capabilities.zig");

pub const GraphicsProtocol = types.GraphicsProtocol;
pub const TermCaps = term_caps.TermCaps;

/// Graphics capabilities structure
pub const GraphicsCapabilities = struct {
    kitty_graphics: bool = false,
    sixel_graphics: bool = false,
    iterm2_images: bool = false,
    unicode_blocks: bool = true,  // Almost always supported
    ascii_art: bool = true,       // Always supported
    
    /// Maximum image dimensions supported
    max_width: ?u32 = null,
    max_height: ?u32 = null,
    
    /// Color capabilities
    true_color: bool = false,
    palette_size: u16 = 16,
    
    /// Feature support
    supports_transparency: bool = false,
    supports_animation: bool = false,
    supports_compression: bool = false,
    supports_persistence: bool = false,
};

/// Detect graphics capabilities from terminal capabilities
pub fn detectCapabilities(caps: TermCaps) GraphicsCapabilities {
    return GraphicsCapabilities{
        .kitty_graphics = caps.supportsKittyGraphics,
        .sixel_graphics = caps.supportsSixel,
        .iterm2_images = caps.supportsITerm2Osc1337,
        .unicode_blocks = true, // Assume Unicode support in modern terminals
        .true_color = caps.supportsRgb,
        .palette_size = if (caps.supportsRgb) 16777216 else 256,
        .supports_transparency = caps.supportsKittyGraphics or caps.supportsITerm2Osc1337,
        .supports_animation = caps.supportsKittyGraphics or caps.supportsITerm2Osc1337,
        .supports_compression = caps.supportsKittyGraphics or caps.supportsITerm2Osc1337,
        .supports_persistence = caps.supportsKittyGraphics,
    };
}

/// Select the best graphics protocol based on capabilities
pub fn selectBestProtocol(caps: GraphicsCapabilities) GraphicsProtocol {
    // Priority order: Kitty > iTerm2 > Sixel > Unicode > ASCII
    if (caps.kitty_graphics) return .kitty;
    if (caps.iterm2_images) return .iterm2;
    if (caps.sixel_graphics) return .sixel;
    if (caps.unicode_blocks) return .unicode;
    if (caps.ascii_art) return .ascii;
    return .none;
}

/// Check if a specific protocol is supported
pub fn isProtocolSupported(caps: GraphicsCapabilities, protocol: GraphicsProtocol) bool {
    return switch (protocol) {
        .kitty => caps.kitty_graphics,
        .sixel => caps.sixel_graphics,
        .iterm2 => caps.iterm2_images,
        .unicode => caps.unicode_blocks,
        .ascii => caps.ascii_art,
        .none => false,
    };
}

/// Get protocol-specific limitations
pub fn getProtocolLimitations(protocol: GraphicsProtocol) ProtocolLimitations {
    return switch (protocol) {
        .kitty => ProtocolLimitations{
            .max_payload_size = 4096 * 1024, // 4MB chunks
            .supports_multiple_frames = true,
            .supports_scaling = true,
            .supports_cropping = true,
            .supports_z_index = true,
        },
        .sixel => ProtocolLimitations{
            .max_colors = 256,
            .max_width = 1000,
            .max_height = 1000,
            .supports_transparency = false,
        },
        .iterm2 => ProtocolLimitations{
            .max_payload_size = 1024 * 1024, // 1MB recommended
            .supports_inline = true,
            .supports_scaling = true,
        },
        .unicode => ProtocolLimitations{
            .max_width = 200,  // Terminal width limit
            .max_height = 100, // Terminal height limit
            .color_depth = 8,  // Limited by ANSI colors
        },
        .ascii => ProtocolLimitations{
            .max_width = 80,
            .max_height = 24,
            .color_depth = 0, // No color
        },
        .none => ProtocolLimitations{},
    };
}

/// Protocol-specific limitations
pub const ProtocolLimitations = struct {
    max_width: ?u32 = null,
    max_height: ?u32 = null,
    max_colors: ?u16 = null,
    max_payload_size: ?usize = null,
    color_depth: ?u8 = null,
    supports_transparency: bool = false,
    supports_multiple_frames: bool = false,
    supports_scaling: bool = false,
    supports_cropping: bool = false,
    supports_inline: bool = false,
    supports_z_index: bool = false,
};

/// Test if environment suggests graphics support
pub fn checkEnvironment() GraphicsCapabilities {
    var caps = GraphicsCapabilities{};
    
    // Check TERM environment variable
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM")) |term| {
        defer std.heap.page_allocator.free(term);
        
        if (std.mem.indexOf(u8, term, "kitty") != null) {
            caps.kitty_graphics = true;
        }
        if (std.mem.indexOf(u8, term, "xterm") != null or
            std.mem.indexOf(u8, term, "mlterm") != null) {
            caps.sixel_graphics = true;
        }
        if (std.mem.indexOf(u8, term, "256color") != null) {
            caps.palette_size = 256;
        }
        if (std.mem.indexOf(u8, term, "truecolor") != null or
            std.mem.indexOf(u8, term, "24bit") != null) {
            caps.true_color = true;
        }
    } else |_| {}
    
    // Check for specific terminal programs
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM_PROGRAM")) |prog| {
        defer std.heap.page_allocator.free(prog);
        
        if (std.mem.eql(u8, prog, "iTerm.app")) {
            caps.iterm2_images = true;
        }
    } else |_| {}
    
    // Check KITTY_WINDOW_ID for Kitty terminal
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "KITTY_WINDOW_ID")) |_| {
        caps.kitty_graphics = true;
    } else |_| {}
    
    return caps;
}
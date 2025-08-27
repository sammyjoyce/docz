//! Common types for terminal graphics
//!
//! This module defines shared types used across all graphics protocols
//! and rendering implementations.

const std = @import("std");

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn fromU32(value: u32) Color {
        return Color{
            .r = @truncate((value >> 24) & 0xFF),
            .g = @truncate((value >> 16) & 0xFF),
            .b = @truncate((value >> 8) & 0xFF),
            .a = @truncate(value & 0xFF),
        };
    }

    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.r) << 24) | 
               (@as(u32, self.g) << 16) | 
               (@as(u32, self.b) << 8) | 
               @as(u32, self.a);
    }

    pub fn luminance(self: Color) f32 {
        return 0.299 * @as(f32, @floatFromInt(self.r)) +
               0.587 * @as(f32, @floatFromInt(self.g)) +
               0.114 * @as(f32, @floatFromInt(self.b));
    }

    pub fn distance(self: Color, other: Color) f32 {
        const dr = @as(f32, @floatFromInt(self.r)) - @as(f32, @floatFromInt(other.r));
        const dg = @as(f32, @floatFromInt(self.g)) - @as(f32, @floatFromInt(other.g));
        const db = @as(f32, @floatFromInt(self.b)) - @as(f32, @floatFromInt(other.b));
        return @sqrt(dr * dr + dg * dg + db * db);
    }

    pub fn mix(self: Color, other: Color, weight: f32) Color {
        const w = std.math.clamp(weight, 0.0, 1.0);
        const inv_w = 1.0 - w;
        return Color{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * inv_w + @as(f32, @floatFromInt(other.r)) * w),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * inv_w + @as(f32, @floatFromInt(other.g)) * w),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * inv_w + @as(f32, @floatFromInt(other.b)) * w),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) * inv_w + @as(f32, @floatFromInt(other.a)) * w),
        };
    }
};

/// Point in terminal coordinates
pub const Point = struct {
    x: i32,
    y: i32,
};

/// Size dimensions
pub const Size = struct {
    width: u32,
    height: u32,
};

/// Rectangle region
pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.x and 
               point.x < self.x + @as(i32, @intCast(self.width)) and
               point.y >= self.y and 
               point.y < self.y + @as(i32, @intCast(self.height));
    }
};

/// Image format types
pub const ImageFormat = enum {
    png,
    jpeg,
    gif,
    bmp,
    rgb24,   // Raw RGB data
    rgba32,  // Raw RGBA data
    
    pub fn isRaw(self: ImageFormat) bool {
        return self == .rgb24 or self == .rgba32;
    }

    pub fn bytesPerPixel(self: ImageFormat) u8 {
        return switch (self) {
            .rgb24 => 3,
            .rgba32 => 4,
            else => 0, // Compressed formats
        };
    }
};

/// Image data structure
pub const Image = struct {
    data: []const u8,
    width: u32,
    height: u32,
    format: ImageFormat,
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *Image) void {
        if (self.allocator) |alloc| {
            alloc.free(self.data);
        }
    }

    pub fn getPixel(self: Image, x: u32, y: u32) ?Color {
        if (!self.format.isRaw()) return null;
        if (x >= self.width or y >= self.height) return null;

        const bpp = self.format.bytesPerPixel();
        const idx = (y * self.width + x) * bpp;
        
        return switch (self.format) {
            .rgb24 => Color{
                .r = self.data[idx],
                .g = self.data[idx + 1],
                .b = self.data[idx + 2],
                .a = 255,
            },
            .rgba32 => Color{
                .r = self.data[idx],
                .g = self.data[idx + 1],
                .b = self.data[idx + 2],
                .a = self.data[idx + 3],
            },
            else => null,
        };
    }
};

/// Graphics rendering options
pub const RenderOptions = struct {
    /// Target size (null = use image size)
    size: ?Size = null,
    /// Preserve aspect ratio when scaling
    preserve_aspect_ratio: bool = true,
    /// Background color for transparency
    background: ?Color = null,
    /// Keep image in terminal memory (protocol-specific)
    persistent: bool = false,
    /// Dithering for color reduction
    dither: bool = false,
    /// Quality level (0-100)
    quality: u8 = 85,
};

/// Chart/graph types
pub const ChartType = enum {
    bar,
    line,
    pie,
    scatter,
    area,
};

/// Chart configuration
pub const Chart = struct {
    type: ChartType,
    title: ?[]const u8 = null,
    data_points: []const DataPoint,
    size: Size,
    colors: ?[]const Color = null,
    
    pub const DataPoint = struct {
        value: f32,
        label: ?[]const u8 = null,
        color: ?Color = null,
    };
};

/// Progress visualization styles
pub const ProgressStyle = enum {
    bar,
    circular,
    gradient,
    dots,
    spinner,
};

/// Progress configuration  
pub const ProgressOptions = struct {
    style: ProgressStyle = .bar,
    size: Size,
    show_percentage: bool = true,
    gradient_start: ?Color = null,
    gradient_end: ?Color = null,
};

/// Graphics protocol types
pub const GraphicsProtocol = enum {
    kitty,      // Kitty graphics protocol
    sixel,      // Sixel graphics
    iterm2,     // iTerm2 inline images
    unicode,    // Unicode block characters
    ascii,      // ASCII art fallback
    none,       // No graphics support
    
    pub fn supportsCompression(self: GraphicsProtocol) bool {
        return self == .kitty or self == .iterm2;
    }

    pub fn supportsAnimation(self: GraphicsProtocol) bool {
        return self == .kitty or self == .iterm2;
    }

    pub fn supportsTransparency(self: GraphicsProtocol) bool {
        return self == .kitty or self == .iterm2;
    }
};

/// Error types for graphics operations
pub const GraphicsError = error{
    Unsupported,
    InvalidFormat,
    InvalidDimensions,
    OutOfMemory,
    EncodingFailed,
    ProtocolError,
    ImageNotFound,
    InvalidOptions,
};
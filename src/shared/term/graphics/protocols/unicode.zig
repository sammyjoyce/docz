//! Unicode block character renderer
//!
//! Renders images using Unicode block characters for wide compatibility.
//! Supports various block types from simple half-blocks to complex quadrants.

const std = @import("std");
const types = @import("../types.zig");
const term_caps = @import("../../capabilities.zig");

pub const Image = types.Image;
pub const Color = types.Color;
pub const RenderOptions = types.RenderOptions;
pub const GraphicsError = types.GraphicsError;
pub const TermCaps = term_caps.TermCaps;

/// Unicode block types for different detail levels
pub const BlockType = enum {
    half,    // Half blocks only (▀▄█)
    quarter, // Quarter blocks (▘▝▖▗▌▐)
    all,     // All block characters

    pub fn getBlocks(self: BlockType) []const Block {
        return switch (self) {
            .half => &HALF_BLOCKS,
            .quarter => &QUARTER_BLOCKS,
            .all => &ALL_BLOCKS,
        };
    }
};

/// Unicode-specific options
pub const UnicodeOptions = struct {
    block_type: BlockType = .all,
    use_color: bool = true,
    dither: bool = false,
    brightness_adjustment: f32 = 1.0,
};

/// Block character definition
pub const Block = struct {
    char: u21,
    coverage: [4]bool, // [upper_left, upper_right, lower_left, lower_right]
    description: []const u8,

    pub fn matches(self: Block, coverage: [4]bool) bool {
        return std.mem.eql(bool, &self.coverage, &coverage);
    }
};

/// Half block characters (most compatible)
const HALF_BLOCKS = [_]Block{
    .{ .char = '▀', .coverage = .{ true, true, false, false }, .description = "Upper half" },
    .{ .char = '▄', .coverage = .{ false, false, true, true }, .description = "Lower half" },
    .{ .char = ' ', .coverage = .{ false, false, false, false }, .description = "Space" },
    .{ .char = '█', .coverage = .{ true, true, true, true }, .description = "Full block" },
};

/// Quarter block characters
const QUARTER_BLOCKS = HALF_BLOCKS ++ [_]Block{
    .{ .char = '▘', .coverage = .{ true, false, false, false }, .description = "Upper left" },
    .{ .char = '▝', .coverage = .{ false, true, false, false }, .description = "Upper right" },
    .{ .char = '▖', .coverage = .{ false, false, true, false }, .description = "Lower left" },
    .{ .char = '▗', .coverage = .{ false, false, false, true }, .description = "Lower right" },
    .{ .char = '▌', .coverage = .{ true, false, true, false }, .description = "Left half" },
    .{ .char = '▐', .coverage = .{ false, true, false, true }, .description = "Right half" },
};

/// All available block characters
const ALL_BLOCKS = QUARTER_BLOCKS ++ [_]Block{
    .{ .char = '▙', .coverage = .{ true, false, true, true }, .description = "Missing upper right" },
    .{ .char = '▟', .coverage = .{ false, true, true, true }, .description = "Missing upper left" },
    .{ .char = '▛', .coverage = .{ true, true, true, false }, .description = "Missing lower right" },
    .{ .char = '▜', .coverage = .{ true, true, false, true }, .description = "Missing lower left" },
    .{ .char = '▚', .coverage = .{ true, false, false, true }, .description = "Diagonal \\" },
    .{ .char = '▞', .coverage = .{ false, true, true, false }, .description = "Diagonal /" },
};

/// Unicode block renderer
pub const UnicodeRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UnicodeRenderer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *UnicodeRenderer) void {
        _ = self;
    }

    /// Render an image using Unicode block characters
    pub fn render(
        self: *UnicodeRenderer,
        writer: anytype,
        caps: TermCaps,
        image: Image,
        options: RenderOptions,
        unicode_opts: UnicodeOptions,
    ) !void {
        // Unicode blocks are universally supported, but we check color support later

        // Calculate output dimensions (each char represents 2x2 pixels)
        const target_width = if (options.size) |size| size.width else image.width;
        const target_height = if (options.size) |size| size.height else image.height;
        
        const char_width = (target_width + 1) / 2;
        const char_height = (target_height + 1) / 2;

        const blocks = unicode_opts.block_type.getBlocks();
        
        // Render each character position
        var y: u32 = 0;
        while (y < char_height) : (y += 1) {
            var line = std.ArrayList(u8).init(self.allocator);
            defer line.deinit();

            var x: u32 = 0;
            while (x < char_width) : (x += 1) {
                // Sample 2x2 pixel block from image
                const block = self.sampleBlock(image, x, y, target_width, target_height);
                
                // Find best matching block character
                const best_block = self.findBestBlock(block, blocks, unicode_opts);
                
                // Add color if supported
                if (unicode_opts.use_color and caps.supportsColor) {
                    const fg_color = block.foreground;
                    const bg_color = block.background;
                    
                    // ANSI color escape sequences
                    if (caps.supportsRgb) {
                        try std.fmt.format(line.writer(),
                            "\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m",
                            .{ fg_color.r, fg_color.g, fg_color.b,
                               bg_color.r, bg_color.g, bg_color.b });
                    }
                }
                
                // Add the block character
                var char_buf: [4]u8 = undefined;
                const char_len = std.unicode.utf8Encode(best_block.char, &char_buf) catch 1;
                try line.appendSlice(char_buf[0..char_len]);
                
                // Reset colors
                if (unicode_opts.use_color and caps.supportsColor) {
                    try line.appendSlice("\x1b[0m");
                }
            }
            
            try writer.writeAll(line.items);
            if (y < char_height - 1) {
                try writer.writeAll("\n");
            }
        }
    }

    /// Sample a 2x2 pixel block from the image
    fn sampleBlock(
        self: *UnicodeRenderer,
        block_x: u32,
        block_y: u32,
        target_width: u32,
        target_height: u32,
    ) PixelBlock {
        _ = self;
        _ = block_x;
        _ = block_y;
        _ = target_width;
        _ = target_height;
        
        // TODO: Implement actual sampling from image
        // For now, return a simple pattern
        return PixelBlock{
            .pixels = .{
                .{ Color{ .r = 255, .g = 255, .b = 255 }, Color{ .r = 128, .g = 128, .b = 128 } },
                .{ Color{ .r = 64, .g = 64, .b = 64 }, Color{ .r = 0, .g = 0, .b = 0 } },
            },
            .foreground = Color{ .r = 200, .g = 200, .b = 200 },
            .background = Color{ .r = 50, .g = 50, .b = 50 },
        };
    }

    /// Find the best matching block character for the pixel data
    fn findBestBlock(
        self: *UnicodeRenderer,
        block: PixelBlock,
        blocks: []const Block,
        options: UnicodeOptions,
    ) Block {
        _ = self;
        _ = options;
        
        // Calculate coverage for each quadrant
        const threshold = block.getAverageBrightness();
        var coverage: [4]bool = undefined;
        
        coverage[0] = block.pixels[0][0].luminance() > threshold; // Upper left
        coverage[1] = block.pixels[0][1].luminance() > threshold; // Upper right
        coverage[2] = block.pixels[1][0].luminance() > threshold; // Lower left
        coverage[3] = block.pixels[1][1].luminance() > threshold; // Lower right
        
        // Find exact match
        for (blocks) |b| {
            if (b.matches(coverage)) {
                return b;
            }
        }
        
        // Fallback to closest match
        return blocks[0];
    }
};

/// Pixel block for 2x2 sampling
const PixelBlock = struct {
    pixels: [2][2]Color,
    foreground: Color,
    background: Color,

    pub fn getAverageBrightness(self: PixelBlock) f32 {
        var sum: f32 = 0;
        for (self.pixels) |row| {
            for (row) |pixel| {
                sum += pixel.luminance();
            }
        }
        return sum / 4.0;
    }
};

/// ASCII art renderer (fallback)
pub const AsciiRenderer = struct {
    allocator: std.mem.Allocator,
    
    const ASCII_CHARS = " .:-=+*#%@";

    pub fn init(allocator: std.mem.Allocator) AsciiRenderer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AsciiRenderer) void {
        _ = self;
    }

    pub fn render(
        self: *AsciiRenderer,
        writer: anytype,
        image: Image,
        options: RenderOptions,
    ) !void {
        _ = self;
        
        const target_width = if (options.size) |size| @min(size.width, 80) else @min(image.width, 80);
        const target_height = if (options.size) |size| @min(size.height, 24) else @min(image.height, 24);
        
        var y: u32 = 0;
        while (y < target_height) : (y += 1) {
            var x: u32 = 0;
            while (x < target_width) : (x += 1) {
                // Sample pixel from image
                const sample_x = (x * image.width) / target_width;
                const sample_y = (y * image.height) / target_height;
                
                const pixel = image.getPixel(sample_x, sample_y) orelse Color{ .r = 0, .g = 0, .b = 0 };
                const brightness = pixel.luminance() / 255.0;
                
                const char_idx = @min(
                    ASCII_CHARS.len - 1,
                    @as(usize, @intFromFloat(brightness * @as(f32, @floatFromInt(ASCII_CHARS.len))))
                );
                
                try writer.print("{c}", .{ASCII_CHARS[char_idx]});
            }
            if (y < target_height - 1) {
                try writer.writeAll("\n");
            }
        }
    }
};
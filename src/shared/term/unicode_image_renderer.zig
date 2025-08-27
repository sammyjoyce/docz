/// Unicode Image Renderer (Mosaic) for Terminal Applications
///
/// This module provides functionality to render images in terminals using Unicode block characters.
/// Implemented using Unicode block characters for wide terminal compatibility.
///
/// The renderer analyzes 2x2 pixel blocks from images and maps them to the best matching
/// Unicode block characters with appropriate foreground and background colors.
///
/// Example usage:
/// ```zig
/// var img = try Image.init(allocator, 64, 32);
/// defer img.deinit();
/// // ... populate image with pixels ...
///
/// const output = try UnicodeImageRenderer
///     .init(allocator)
///     .width(32)
///     .height(16)
///     .symbolType(.all)
///     .render(img);
/// defer allocator.free(output);
///
/// std.log.info("{s}", .{output});
/// ```
const std = @import("std");
const math = std.math;

/// RGB color structure for image processing
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn fromU32(value: u32) RGB {
        return RGB{
            .r = @truncate((value >> 16) & 0xFF),
            .g = @truncate((value >> 8) & 0xFF),
            .b = @truncate(value & 0xFF),
        };
    }

    pub fn toU32(self: RGB) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    /// Calculate luminance for color comparison
    pub fn luminance(self: RGB) f32 {
        return 0.299 * @as(f32, @floatFromInt(self.r)) +
            0.587 * @as(f32, @floatFromInt(self.g)) +
            0.114 * @as(f32, @floatFromInt(self.b));
    }

    /// Calculate color distance between two colors
    pub fn distance(self: RGB, other: RGB) f32 {
        const dr = @as(f32, @floatFromInt(self.r)) - @as(f32, @floatFromInt(other.r));
        const dg = @as(f32, @floatFromInt(self.g)) - @as(f32, @floatFromInt(other.g));
        const db = @as(f32, @floatFromInt(self.b)) - @as(f32, @floatFromInt(other.b));
        return @sqrt(dr * dr + dg * dg + db * db);
    }

    /// Mix two colors based on weight (0.0 - 1.0)
    pub fn mix(self: RGB, other: RGB, weight: f32) RGB {
        const w = math.clamp(weight, 0.0, 1.0);
        const inv_w = 1.0 - w;
        return RGB{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * inv_w + @as(f32, @floatFromInt(other.r)) * w),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * inv_w + @as(f32, @floatFromInt(other.g)) * w),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * inv_w + @as(f32, @floatFromInt(other.b)) * w),
        };
    }
};

/// Unicode block character definition
pub const Block = struct {
    char: u21,
    coverage: [4]bool, // [upper_left, upper_right, lower_left, lower_right]
    description: []const u8,

    pub fn matches(self: Block, coverage: [4]bool) bool {
        return std.mem.eql(bool, &self.coverage, &coverage);
    }
};

/// Symbol type for rendering complexity
pub const SymbolType = enum {
    half, // Only half blocks (▀▄ █)
    quarter, // Quarter blocks + half blocks
    all, // All available block characters

    pub fn getBlocks(self: SymbolType) []const Block {
        return switch (self) {
            .half => &HALF_BLOCKS,
            .quarter => &QUARTER_BLOCKS,
            .all => &ALL_BLOCKS,
        };
    }
};

/// Half block characters (most compatible)
const HALF_BLOCKS = [_]Block{
    .{ .char = '▀', .coverage = .{ true, true, false, false }, .description = "Upper half block" },
    .{ .char = '▄', .coverage = .{ false, false, true, true }, .description = "Lower half block" },
    .{ .char = ' ', .coverage = .{ false, false, false, false }, .description = "Space" },
    .{ .char = '█', .coverage = .{ true, true, true, true }, .description = "Full block" },
};

/// Quarter block characters
const QUARTER_BLOCKS = [_]Block{
    // Include half blocks
    .{ .char = '▀', .coverage = .{ true, true, false, false }, .description = "Upper half block" },
    .{ .char = '▄', .coverage = .{ false, false, true, true }, .description = "Lower half block" },
    .{ .char = ' ', .coverage = .{ false, false, false, false }, .description = "Space" },
    .{ .char = '█', .coverage = .{ true, true, true, true }, .description = "Full block" },
    // Quarter blocks
    .{ .char = '▘', .coverage = .{ true, false, false, false }, .description = "Quadrant upper left" },
    .{ .char = '▝', .coverage = .{ false, true, false, false }, .description = "Quadrant upper right" },
    .{ .char = '▖', .coverage = .{ false, false, true, false }, .description = "Quadrant lower left" },
    .{ .char = '▗', .coverage = .{ false, false, false, true }, .description = "Quadrant lower right" },
    .{ .char = '▌', .coverage = .{ true, false, true, false }, .description = "Left half block" },
    .{ .char = '▐', .coverage = .{ false, true, false, true }, .description = "Right half block" },
};

/// All available block characters
const ALL_BLOCKS = [_]Block{
    // Include quarter blocks
    .{ .char = '▀', .coverage = .{ true, true, false, false }, .description = "Upper half block" },
    .{ .char = '▄', .coverage = .{ false, false, true, true }, .description = "Lower half block" },
    .{ .char = ' ', .coverage = .{ false, false, false, false }, .description = "Space" },
    .{ .char = '█', .coverage = .{ true, true, true, true }, .description = "Full block" },
    .{ .char = '▘', .coverage = .{ true, false, false, false }, .description = "Quadrant upper left" },
    .{ .char = '▝', .coverage = .{ false, true, false, false }, .description = "Quadrant upper right" },
    .{ .char = '▖', .coverage = .{ false, false, true, false }, .description = "Quadrant lower left" },
    .{ .char = '▗', .coverage = .{ false, false, false, true }, .description = "Quadrant lower right" },
    .{ .char = '▌', .coverage = .{ true, false, true, false }, .description = "Left half block" },
    .{ .char = '▐', .coverage = .{ false, true, false, true }, .description = "Right half block" },
    // Complex blocks
    .{ .char = '▙', .coverage = .{ true, false, true, true }, .description = "Quadrant upper left and lower half" },
    .{ .char = '▟', .coverage = .{ false, true, true, true }, .description = "Quadrant upper right and lower half" },
    .{ .char = '▛', .coverage = .{ true, true, true, false }, .description = "Quadrant upper half and lower left" },
    .{ .char = '▜', .coverage = .{ true, true, false, true }, .description = "Quadrant upper half and lower right" },
    .{ .char = '▚', .coverage = .{ true, false, false, true }, .description = "Quadrant upper left and lower right" },
    .{ .char = '▞', .coverage = .{ false, true, true, false }, .description = "Quadrant upper right and lower left" },
};

/// Simple image representation for processing
pub const Image = struct {
    pixels: []RGB,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Image {
        const pixels = try allocator.alloc(RGB, width * height);
        return Image{
            .pixels = pixels,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.pixels);
    }

    pub fn getPixel(self: Image, x: u32, y: u32) ?RGB {
        if (x >= self.width or y >= self.height) return null;
        return self.pixels[y * self.width + x];
    }

    pub fn setPixel(self: *Image, x: u32, y: u32, color: RGB) void {
        if (x >= self.width or y >= self.height) return;
        self.pixels[y * self.width + x] = color;
    }
};

/// Pixel block represents a 2x2 region of the image
const PixelBlock = struct {
    pixels: [2][2]RGB,
    avg_fg: RGB,
    avg_bg: RGB,
    best_symbol: u21,
    best_fg_color: RGB,
    best_bg_color: RGB,

    pub fn fromImage(img: Image, block_x: u32, block_y: u32) PixelBlock {
        // Extract 2x2 pixel block
        var pixels: [2][2]RGB = undefined;
        for (0..2) |dy| {
            for (0..2) |dx| {
                const x = block_x * 2 + @as(u32, @intCast(dx));
                const y = block_y * 2 + @as(u32, @intCast(dy));
                pixels[dy][dx] = img.getPixel(x, y) orelse RGB{ .r = 0, .g = 0, .b = 0 };
            }
        }

        return PixelBlock{
            .pixels = pixels,
            .avg_fg = RGB{ .r = 0, .g = 0, .b = 0 },
            .avg_bg = RGB{ .r = 0, .g = 0, .b = 0 },
            .best_symbol = ' ',
            .best_fg_color = RGB{ .r = 255, .g = 255, .b = 255 },
            .best_bg_color = RGB{ .r = 0, .g = 0, .b = 0 },
        };
    }
};

/// Unicode Image Renderer configuration and state
pub const UnicodeImageRenderer = struct {
    output_width: u32 = 0,
    output_height: u32 = 0,
    threshold_level: u8 = 128, // Middle threshold for binary decisions
    symbol_type: SymbolType = .half,
    use_color: bool = true,
    invert_colors: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UnicodeImageRenderer {
        return UnicodeImageRenderer{
            .allocator = allocator,
        };
    }

    pub fn width(self: UnicodeImageRenderer, w: u32) UnicodeImageRenderer {
        var new_self = self;
        new_self.output_width = w;
        return new_self;
    }

    pub fn height(self: UnicodeImageRenderer, h: u32) UnicodeImageRenderer {
        var new_self = self;
        new_self.output_height = h;
        return new_self;
    }

    pub fn symbolType(self: UnicodeImageRenderer, sym_type: SymbolType) UnicodeImageRenderer {
        var new_self = self;
        new_self.symbol_type = sym_type;
        return new_self;
    }

    pub fn threshold(self: UnicodeImageRenderer, threshold_val: u8) UnicodeImageRenderer {
        var new_self = self;
        new_self.threshold_level = threshold_val;
        return new_self;
    }

    pub fn invertColors(self: UnicodeImageRenderer, invert: bool) UnicodeImageRenderer {
        var new_self = self;
        new_self.invert_colors = invert;
        return new_self;
    }

    /// Find the best matching block character for a given coverage pattern
    fn findBestBlock(self: UnicodeImageRenderer, coverage: [4]bool) Block {
        const blocks = self.symbol_type.getBlocks();

        // First try to find exact match
        for (blocks) |block| {
            if (block.matches(coverage)) {
                return block;
            }
        }

        // If no exact match, find closest match by counting matching bits
        var best_block = blocks[0];
        var best_score: u8 = 0;

        for (blocks) |block| {
            var score: u8 = 0;
            for (0..4) |i| {
                if (block.coverage[i] == coverage[i]) {
                    score += 1;
                }
            }
            if (score > best_score) {
                best_score = score;
                best_block = block;
            }
        }

        return best_block;
    }

    /// Analyze a 2x2 pixel block and determine the best representation
    fn analyzePixelBlock(self: UnicodeImageRenderer, block: PixelBlock) PixelBlock {
        var result = block;

        // Determine which quadrants should be "on" based on luminance threshold
        var coverage: [4]bool = undefined;
        var fg_pixels = std.ArrayListUnmanaged(RGB){};
        var bg_pixels = std.ArrayListUnmanaged(RGB){};
        defer fg_pixels.deinit(self.allocator);
        defer bg_pixels.deinit(self.allocator);

        for (0..2) |y| {
            for (0..2) |x| {
                const pixel = block.pixels[y][x];
                const lum = pixel.luminance();
                const is_fg = lum >= @as(f32, @floatFromInt(self.threshold_level));

                coverage[y * 2 + x] = if (self.invert_colors) !is_fg else is_fg;

                if (coverage[y * 2 + x]) {
                    fg_pixels.append(self.allocator, pixel) catch {};
                } else {
                    bg_pixels.append(self.allocator, pixel) catch {};
                }
            }
        }

        // Calculate average colors
        result.avg_fg = averageColor(fg_pixels.items);
        result.avg_bg = averageColor(bg_pixels.items);
        result.best_fg_color = result.avg_fg;
        result.best_bg_color = result.avg_bg;

        // Find best matching block character
        const best_block = self.findBestBlock(coverage);
        result.best_symbol = best_block.char;

        return result;
    }

    /// Calculate average color from a list of colors
    fn averageColor(colors: []const RGB) RGB {
        if (colors.len == 0) return RGB{ .r = 0, .g = 0, .b = 0 };

        var sum_r: u32 = 0;
        var sum_g: u32 = 0;
        var sum_b: u32 = 0;

        for (colors) |color| {
            sum_r += color.r;
            sum_g += color.g;
            sum_b += color.b;
        }

        return RGB{
            .r = @truncate(sum_r / @as(u32, @intCast(colors.len))),
            .g = @truncate(sum_g / @as(u32, @intCast(colors.len))),
            .b = @truncate(sum_b / @as(u32, @intCast(colors.len))),
        };
    }

    /// Scale image to target dimensions
    fn scaleImage(self: UnicodeImageRenderer, src: Image, target_width: u32, target_height: u32) !Image {
        var scaled = try Image.init(self.allocator, target_width, target_height);

        const scale_x = @as(f32, @floatFromInt(src.width)) / @as(f32, @floatFromInt(target_width));
        const scale_y = @as(f32, @floatFromInt(src.height)) / @as(f32, @floatFromInt(target_height));

        for (0..target_height) |y| {
            for (0..target_width) |x| {
                const src_x = @as(u32, @intFromFloat(@as(f32, @floatFromInt(x)) * scale_x));
                const src_y = @as(u32, @intFromFloat(@as(f32, @floatFromInt(y)) * scale_y));

                const color = src.getPixel(src_x, src_y) orelse RGB{ .r = 0, .g = 0, .b = 0 };
                scaled.setPixel(@intCast(x), @intCast(y), color);
            }
        }

        return scaled;
    }

    /// Render an image to Unicode block art
    pub fn render(self: UnicodeImageRenderer, img: Image) ![]u8 {
        // Determine output dimensions
        var render_width = self.output_width;
        var render_height = self.output_height;

        if (render_width == 0 and render_height == 0) {
            // Default to image dimensions divided by 2 (since each char represents 2x2 pixels)
            render_width = img.width / 2;
            render_height = img.height / 2;
        } else if (render_width == 0) {
            // Calculate width based on aspect ratio
            const aspect_ratio = @as(f32, @floatFromInt(img.width)) / @as(f32, @floatFromInt(img.height));
            render_width = @intFromFloat(@as(f32, @floatFromInt(render_height)) * aspect_ratio);
        } else if (render_height == 0) {
            // Calculate height based on aspect ratio
            const aspect_ratio = @as(f32, @floatFromInt(img.height)) / @as(f32, @floatFromInt(img.width));
            render_height = @intFromFloat(@as(f32, @floatFromInt(render_width)) * aspect_ratio);
        }

        // Scale image to match render dimensions (accounting for 2x2 pixel blocks)
        const pixel_width = render_width * 2;
        const pixel_height = render_height * 2;
        var scaled_img = try self.scaleImage(img, pixel_width, pixel_height);
        defer scaled_img.deinit();

        // Process image in 2x2 blocks
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(self.allocator);

        for (0..render_height) |block_y| {
            for (0..render_width) |block_x| {
                const pixel_block = PixelBlock.fromImage(scaled_img, @intCast(block_x), @intCast(block_y));
                const analyzed = self.analyzePixelBlock(pixel_block);

                // Add ANSI color codes if color support is enabled
                if (self.use_color) {
                    // Foreground color
                    const fg_ansi = try std.fmt.allocPrint(self.allocator, "\x1b[38;2;{d};{d};{d}m", .{ analyzed.best_fg_color.r, analyzed.best_fg_color.g, analyzed.best_fg_color.b });
                    defer self.allocator.free(fg_ansi);
                    try output.appendSlice(self.allocator, fg_ansi);

                    // Background color
                    const bg_ansi = try std.fmt.allocPrint(self.allocator, "\x1b[48;2;{d};{d};{d}m", .{ analyzed.best_bg_color.r, analyzed.best_bg_color.g, analyzed.best_bg_color.b });
                    defer self.allocator.free(bg_ansi);
                    try output.appendSlice(self.allocator, bg_ansi);
                }

                // Add the Unicode character
                var utf8_buf: [4]u8 = undefined;
                const char_len = std.unicode.utf8Encode(analyzed.best_symbol, &utf8_buf) catch 1;
                try output.appendSlice(self.allocator, utf8_buf[0..char_len]);

                // Reset colors after each character if using color
                if (self.use_color) {
                    try output.appendSlice(self.allocator, "\x1b[0m");
                }
            }

            // Add newline at end of each row
            try output.append(self.allocator, '\n');
        }

        return output.toOwnedSlice(self.allocator);
    }
};

/// Convenience function for quick rendering with default settings
pub fn render(allocator: std.mem.Allocator, img: Image, width: u32, height: u32) ![]u8 {
    const renderer = UnicodeImageRenderer.init(allocator).width(width).height(height);
    return renderer.render(img);
}

/// Create a test image with a simple pattern
pub fn createTestImage(allocator: std.mem.Allocator) !Image {
    var img = try Image.init(allocator, 32, 32);

    // Create a simple gradient pattern
    for (0..32) |y| {
        for (0..32) |x| {
            const intensity = @as(u8, @intCast((x + y) * 255 / 63));
            img.setPixel(@intCast(x), @intCast(y), RGB{ .r = intensity, .g = intensity, .b = intensity });
        }
    }

    return img;
}

// Tests
test "RGB color operations" {
    const testing = std.testing;

    const red = RGB{ .r = 255, .g = 0, .b = 0 };
    const blue = RGB{ .r = 0, .g = 0, .b = 255 };

    // Test luminance calculation
    try testing.expect(red.luminance() > blue.luminance());

    // Test color mixing
    const purple = red.mix(blue, 0.5);
    try testing.expect(purple.r > 0 and purple.b > 0 and purple.g == 0);
}

test "Unicode image renderer basic functionality" {
    const testing = std.testing;

    var test_img = try createTestImage(testing.allocator);
    defer test_img.deinit();

    const renderer = UnicodeImageRenderer.init(testing.allocator);
    const output = try renderer.width(16).height(16).render(test_img);
    defer testing.allocator.free(output);

    // Output should contain Unicode block characters and newlines
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "\n") != null);
}

test "Block character matching" {
    const testing = std.testing;

    const renderer = UnicodeImageRenderer.init(testing.allocator);

    // Test exact match
    const upper_half = [4]bool{ true, true, false, false };
    const block = renderer.findBestBlock(upper_half);
    try testing.expect(block.char == '▀');

    // Test full block
    const full = [4]bool{ true, true, true, true };
    const full_block = renderer.findBestBlock(full);
    try testing.expect(full_block.char == '█');
}

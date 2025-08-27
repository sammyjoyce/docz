const std = @import("std");
const wcwidth = @import("wcwidth.zig");

/// Cell-based terminal display buffer for efficient TUI rendering
/// Tracks character data and attributes for each terminal position
/// Provides differential rendering to minimize escape sequence output
/// Terminal cell representing a single character position
pub const Cell = struct {
    /// Unicode codepoint for the character (0 = empty cell)
    codepoint: u21 = 0,
    /// Display width (0, 1, or 2) - important for wide characters
    width: u8 = 0,
    /// Foreground color
    fg_color: CellColor = .default,
    /// Background color
    bg_color: CellColor = .default,
    /// Text attributes (bold, italic, etc.)
    attrs: CellAttrs = .{},
    /// Whether this cell is a continuation of a wide character
    is_continuation: bool = false,

    /// Check if cell is empty (no visible character)
    pub fn isEmpty(self: Cell) bool {
        return self.codepoint == 0;
    }

    /// Check if this cell represents a wide character (occupies 2 columns)
    pub fn isWide(self: Cell) bool {
        return self.width == 2;
    }

    /// Reset cell to empty state
    pub fn clear(self: *Cell) void {
        self.* = Cell{};
    }

    /// Check if two cells have identical content and attributes
    pub fn eql(self: Cell, other: Cell) bool {
        return self.codepoint == other.codepoint and
            self.width == other.width and
            self.fg_color.eql(other.fg_color) and
            self.bg_color.eql(other.bg_color) and
            self.attrs.eql(other.attrs) and
            self.is_continuation == other.is_continuation;
    }
};

/// Color representation that can be default, indexed, or RGB
pub const CellColor = union(enum) {
    default, // Use terminal's default color
    indexed: u8, // ANSI 256-color palette (0-255)
    rgb: struct { r: u8, g: u8, b: u8 }, // True color RGB

    pub fn eql(self: CellColor, other: CellColor) bool {
        return switch (self) {
            .default => other == .default,
            .indexed => |idx| other == .indexed and other.indexed == idx,
            .rgb => |rgb| other == .rgb and
                other.rgb.r == rgb.r and
                other.rgb.g == rgb.g and
                other.rgb.b == rgb.b,
        };
    }
};

/// Text attributes for styling
pub const CellAttrs = struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,

    pub fn eql(self: CellAttrs, other: CellAttrs) bool {
        return self.bold == other.bold and
            self.dim == other.dim and
            self.italic == other.italic and
            self.underline == other.underline and
            self.blink == other.blink and
            self.reverse == other.reverse and
            self.strikethrough == other.strikethrough;
    }

    /// Check if any attributes are set
    pub fn hasAttrs(self: CellAttrs) bool {
        return self.bold or self.dim or self.italic or
            self.underline or self.blink or self.reverse or
            self.strikethrough;
    }
};

/// Terminal cell buffer for efficient screen management
pub const CellBuffer = struct {
    allocator: std.mem.Allocator,
    /// Current terminal dimensions
    width: usize,
    height: usize,
    /// Cell data stored as width * height array
    cells: []Cell,
    /// Previous frame for differential rendering
    previous_cells: []Cell,
    /// Current cursor position
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    /// Whether buffer needs full redraw
    dirty: bool = true,

    const Self = @This();

    /// Initialize cell buffer with given dimensions
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Self {
        const total_cells = width * height;
        const cells = try allocator.alloc(Cell, total_cells);
        const previous_cells = try allocator.alloc(Cell, total_cells);

        // Initialize all cells as empty
        for (cells) |*cell| {
            cell.clear();
        }
        for (previous_cells) |*cell| {
            cell.clear();
        }

        return Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .cells = cells,
            .previous_cells = previous_cells,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cells);
        self.allocator.free(self.previous_cells);
    }

    /// Resize buffer to new dimensions
    pub fn resize(self: *Self, new_width: usize, new_height: usize) !void {
        const new_total = new_width * new_height;
        const new_cells = try self.allocator.alloc(Cell, new_total);
        const new_previous = try self.allocator.alloc(Cell, new_total);

        // Initialize new cells
        for (new_cells) |*cell| {
            cell.clear();
        }
        for (new_previous) |*cell| {
            cell.clear();
        }

        // Copy existing content if possible
        const copy_height = @min(self.height, new_height);
        const copy_width = @min(self.width, new_width);

        for (0..copy_height) |y| {
            for (0..copy_width) |x| {
                const old_idx = y * self.width + x;
                const new_idx = y * new_width + x;
                new_cells[new_idx] = self.cells[old_idx];
                new_previous[new_idx] = self.previous_cells[old_idx];
            }
        }

        // Replace old arrays
        self.allocator.free(self.cells);
        self.allocator.free(self.previous_cells);
        self.cells = new_cells;
        self.previous_cells = new_previous;
        self.width = new_width;
        self.height = new_height;
        self.dirty = true;

        // Clamp cursor position to new bounds
        self.cursor_x = @min(self.cursor_x, new_width - 1);
        self.cursor_y = @min(self.cursor_y, new_height - 1);
    }

    /// Get cell at position (bounds-checked)
    pub fn getCell(self: Self, x: usize, y: usize) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        return &self.cells[y * self.width + x];
    }

    /// Set cell at position with character and attributes
    pub fn setCell(self: *Self, x: usize, y: usize, codepoint: u21, fg: CellColor, bg: CellColor, attrs: CellAttrs) !void {
        if (x >= self.width or y >= self.height) return;

        const cell = &self.cells[y * self.width + x];
        const char_width = wcwidth.codepointWidth(codepoint, .{});

        // Handle wide characters
        if (char_width == 2 and x + 1 < self.width) {
            // First cell contains the character
            cell.codepoint = codepoint;
            cell.width = 2;
            cell.fg_color = fg;
            cell.bg_color = bg;
            cell.attrs = attrs;
            cell.is_continuation = false;

            // Second cell is marked as continuation
            const continuation_cell = &self.cells[y * self.width + x + 1];
            continuation_cell.codepoint = 0;
            continuation_cell.width = 0;
            continuation_cell.fg_color = fg;
            continuation_cell.bg_color = bg;
            continuation_cell.attrs = attrs;
            continuation_cell.is_continuation = true;
        } else if (char_width == 0) {
            // Zero-width character - combine with previous cell if possible
            if (x > 0 and !self.cells[y * self.width + x - 1].isEmpty()) {
                // Don't replace the previous character, just update attributes if needed
                return;
            }
            // Otherwise treat as empty cell
            cell.codepoint = 0;
            cell.width = 0;
            cell.fg_color = fg;
            cell.bg_color = bg;
            cell.attrs = attrs;
            cell.is_continuation = false;
        } else {
            // Normal single-width character
            cell.codepoint = codepoint;
            cell.width = char_width;
            cell.fg_color = fg;
            cell.bg_color = bg;
            cell.attrs = attrs;
            cell.is_continuation = false;
        }
    }

    /// Write UTF-8 text at position with attributes
    pub fn writeText(self: *Self, x: usize, y: usize, text: []const u8, fg: CellColor, bg: CellColor, attrs: CellAttrs) !usize {
        var pos_x = x;
        var i: usize = 0;

        while (i < text.len and pos_x < self.width) {
            const seq_len = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
            if (i + seq_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i .. i + seq_len]) catch {
                i += 1;
                continue;
            };

            try self.setCell(pos_x, y, codepoint, fg, bg, attrs);

            const char_width = wcwidth.codepointWidth(codepoint, .{});
            pos_x += @max(1, char_width); // Always advance at least 1 for wide chars
            i += seq_len;
        }

        return pos_x - x; // Return number of columns written
    }

    /// Clear entire buffer
    pub fn clear(self: *Self) void {
        for (self.cells) |*cell| {
            cell.clear();
        }
        self.dirty = true;
    }

    /// Clear specific rectangular area
    pub fn clearRect(self: *Self, x: usize, y: usize, width: usize, height: usize) void {
        const end_x = @min(x + width, self.width);
        const end_y = @min(y + height, self.height);

        for (y..end_y) |row| {
            for (x..end_x) |col| {
                if (self.getCell(col, row)) |cell| {
                    cell.clear();
                }
            }
        }
    }

    /// Set cursor position
    pub fn setCursor(self: *Self, x: usize, y: usize) void {
        self.cursor_x = @min(x, self.width - 1);
        self.cursor_y = @min(y, self.height - 1);
    }

    /// Get differences between current and previous frame
    /// Returns list of changed cells for efficient rendering
    pub const CellDiff = struct {
        x: usize,
        y: usize,
        cell: Cell,
    };

    pub fn getDifferences(self: *Self, allocator: std.mem.Allocator) ![]CellDiff {
        var diffs = std.ArrayList(CellDiff).init(allocator);
        errdefer diffs.deinit();

        if (self.dirty) {
            // Full redraw needed - return all cells
            for (self.cells, 0..) |cell, idx| {
                const x = idx % self.width;
                const y = idx / self.width;
                try diffs.append(.{ .x = x, .y = y, .cell = cell });
            }
        } else {
            // Differential rendering - only changed cells
            for (self.cells, 0..) |cell, idx| {
                if (!cell.eql(self.previous_cells[idx])) {
                    const x = idx % self.width;
                    const y = idx / self.width;
                    try diffs.append(.{ .x = x, .y = y, .cell = cell });
                }
            }
        }

        return try diffs.toOwnedSlice();
    }

    /// Mark current frame as rendered (copies current to previous)
    pub fn swapBuffers(self: *Self) void {
        std.mem.copy(Cell, self.previous_cells, self.cells);
        self.dirty = false;
    }

    /// Force full redraw on next render
    pub fn markDirty(self: *Self) void {
        self.dirty = true;
    }

    /// Fill area with character and attributes
    pub fn fillRect(self: *Self, x: usize, y: usize, width: usize, height: usize, codepoint: u21, fg: CellColor, bg: CellColor, attrs: CellAttrs) !void {
        const end_x = @min(x + width, self.width);
        const end_y = @min(y + height, self.height);

        for (y..end_y) |row| {
            for (x..end_x) |col| {
                try self.setCell(col, row, codepoint, fg, bg, attrs);
            }
        }
    }

    /// Draw box with optional borders
    pub const BoxStyle = struct {
        top_left: u21 = '┌',
        top_right: u21 = '┐',
        bottom_left: u21 = '└',
        bottom_right: u21 = '┘',
        horizontal: u21 = '─',
        vertical: u21 = '│',
        fill: ?u21 = null, // Optional fill character
    };

    pub fn drawBox(self: *Self, x: usize, y: usize, width: usize, height: usize, style: BoxStyle, fg: CellColor, bg: CellColor, attrs: CellAttrs) !void {
        if (width < 2 or height < 2) return;

        // Fill interior if requested
        if (style.fill) |fill_char| {
            try self.fillRect(x + 1, y + 1, width - 2, height - 2, fill_char, fg, bg, attrs);
        }

        // Draw corners
        try self.setCell(x, y, style.top_left, fg, bg, attrs);
        try self.setCell(x + width - 1, y, style.top_right, fg, bg, attrs);
        try self.setCell(x, y + height - 1, style.bottom_left, fg, bg, attrs);
        try self.setCell(x + width - 1, y + height - 1, style.bottom_right, fg, bg, attrs);

        // Draw horizontal borders
        for (1..width - 1) |col| {
            try self.setCell(x + col, y, style.horizontal, fg, bg, attrs);
            try self.setCell(x + col, y + height - 1, style.horizontal, fg, bg, attrs);
        }

        // Draw vertical borders
        for (1..height - 1) |row| {
            try self.setCell(x, y + row, style.vertical, fg, bg, attrs);
            try self.setCell(x + width - 1, y + row, style.vertical, fg, bg, attrs);
        }
    }
};

// Convenience functions for common colors
pub fn defaultColor() CellColor {
    return .default;
}
pub fn indexedColor(index: u8) CellColor {
    return .{ .indexed = index };
}
pub fn rgbColor(r: u8, g: u8, b: u8) CellColor {
    return .{ .rgb = .{ .r = r, .g = g, .b = b } };
}

// Common attribute combinations
pub const BOLD = CellAttrs{ .bold = true };
pub const ITALIC = CellAttrs{ .italic = true };
pub const UNDERLINE = CellAttrs{ .underline = true };
pub const REVERSE = CellAttrs{ .reverse = true };

// Tests
test "cell buffer creation and basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 80, 24);
    defer buf.deinit();

    try testing.expect(buf.width == 80);
    try testing.expect(buf.height == 24);

    // Test setting a cell
    try buf.setCell(0, 0, 'A', defaultColor(), defaultColor(), .{});
    const cell = buf.getCell(0, 0).?;
    try testing.expect(cell.codepoint == 'A');
}

test "wide character handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 10, 5);
    defer buf.deinit();

    // Test wide character (CJK ideograph)
    try buf.setCell(0, 0, 0x4E00, defaultColor(), defaultColor(), .{}); // 一

    const cell1 = buf.getCell(0, 0).?;
    const cell2 = buf.getCell(1, 0).?;

    try testing.expect(cell1.codepoint == 0x4E00);
    try testing.expect(cell1.width == 2);
    try testing.expect(cell2.is_continuation);
}

test "text writing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 20, 5);
    defer buf.deinit();

    const written = try buf.writeText(0, 0, "Hello, 世界!", defaultColor(), defaultColor(), .{});
    try testing.expect(written > 6); // Should be longer due to wide characters

    // Check first few characters
    try testing.expect(buf.getCell(0, 0).?.codepoint == 'H');
    try testing.expect(buf.getCell(1, 0).?.codepoint == 'e');
}

test "buffer resize" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 10, 5);
    defer buf.deinit();

    // Set some content
    try buf.setCell(5, 2, 'X', defaultColor(), defaultColor(), .{});

    // Resize larger
    try buf.resize(20, 10);
    try testing.expect(buf.width == 20);
    try testing.expect(buf.height == 10);

    // Content should be preserved
    try testing.expect(buf.getCell(5, 2).?.codepoint == 'X');
}

test "box drawing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 10, 5);
    defer buf.deinit();

    try buf.drawBox(1, 1, 5, 3, .{}, defaultColor(), defaultColor(), .{});

    // Check corners
    try testing.expect(buf.getCell(1, 1).?.codepoint == '┌');
    try testing.expect(buf.getCell(5, 1).?.codepoint == '┐');
    try testing.expect(buf.getCell(1, 3).?.codepoint == '└');
    try testing.expect(buf.getCell(5, 3).?.codepoint == '┘');
}

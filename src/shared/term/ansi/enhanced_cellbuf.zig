const std = @import("std");

// Enhanced CellBuffer implementation with advanced terminal features
// Supports hyperlinks, combining characters, advanced styling, and buffer operations

/// Hyperlink representation in terminal cells
pub const Link = struct {
    url: []const u8 = "",
    params: []const u8 = "",

    pub fn isEmpty(self: Link) bool {
        return self.url.len == 0 and self.params.len == 0;
    }

    pub fn equal(self: Link, other: Link) bool {
        return std.mem.eql(u8, self.url, other.url) and
            std.mem.eql(u8, self.params, other.params);
    }

    pub fn reset(self: *Link) void {
        self.url = "";
        self.params = "";
    }
};

/// Text attribute mask for efficient attribute storage
pub const AttrMask = packed struct {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    slow_blink: bool = false,
    rapid_blink: bool = false,
    reverse: bool = false,
    conceal: bool = false,
    strikethrough: bool = false,

    pub fn isEmpty(self: AttrMask) bool {
        const val: u8 = @bitCast(self);
        return val == 0;
    }

    pub fn contains(self: AttrMask, attr: AttrMask) bool {
        const self_val: u8 = @bitCast(self);
        const attr_val: u8 = @bitCast(attr);
        return (self_val & attr_val) == attr_val;
    }
};

/// Underline styles following ANSI standards
pub const UnderlineStyle = enum(u8) {
    none = 0,
    single = 1,
    double = 2,
    curly = 3,
    dotted = 4,
    dashed = 5,
};

/// Enhanced style system with underline colors and styles
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    ul: ?Color = null, // Underline color
    attrs: AttrMask = .{},
    ul_style: UnderlineStyle = .none,

    pub fn isEmpty(self: Style) bool {
        return self.fg == null and
            self.bg == null and
            self.ul == null and
            self.attrs.isEmpty() and
            self.ul_style == .none;
    }

    pub fn equal(self: Style, other: Style) bool {
        return colorEqual(self.fg, other.fg) and
            colorEqual(self.bg, other.bg) and
            colorEqual(self.ul, other.ul) and
            std.meta.eql(self.attrs, other.attrs) and
            self.ul_style == other.ul_style;
    }

    pub fn reset(self: *Style) void {
        self.fg = null;
        self.bg = null;
        self.ul = null;
        self.attrs = .{};
        self.ul_style = .none;
    }

    /// Check if style only has attributes that don't affect space appearance
    pub fn isClear(self: Style) bool {
        return self.ul_style == .none and
            !self.attrs.reverse and
            !self.attrs.conceal and
            self.fg == null and
            self.bg == null and
            self.ul == null;
    }

    // Builder pattern methods for styling
    pub fn bold(self: Style, enabled: bool) Style {
        var result = self;
        result.attrs.bold = enabled;
        return result;
    }

    pub fn italic(self: Style, enabled: bool) Style {
        var result = self;
        result.attrs.italic = enabled;
        return result;
    }

    pub fn underline(self: Style, enabled: bool) Style {
        var result = self;
        result.ul_style = if (enabled) .single else .none;
        return result;
    }

    pub fn underlineStyle(self: Style, style: UnderlineStyle) Style {
        var result = self;
        result.ul_style = style;
        return result;
    }

    pub fn foreground(self: Style, color: Color) Style {
        var result = self;
        result.fg = color;
        return result;
    }

    pub fn background(self: Style, color: Color) Style {
        var result = self;
        result.bg = color;
        return result;
    }

    pub fn underlineColor(self: Style, color: Color) Style {
        var result = self;
        result.ul = color;
        return result;
    }
};

/// Enhanced color system supporting various color types
pub const Color = union(enum) {
    basic: BasicColor,
    indexed: u8, // 0-255
    rgb: RGBColor,

    pub fn equal(self: ?Color, other: ?Color) bool {
        if (self == null and other == null) return true;
        if (self == null or other == null) return false;

        const s = self.?;
        const o = other.?;

        return switch (s) {
            .basic => |c| o == .basic and o.basic == c,
            .indexed => |c| o == .indexed and o.indexed == c,
            .rgb => |c| o == .rgb and
                o.rgb.r == c.r and
                o.rgb.g == c.g and
                o.rgb.b == c.b,
        };
    }
};

fn colorEqual(a: ?Color, b: ?Color) bool {
    return Color.equal(a, b);
}

/// Basic ANSI colors (0-15)
pub const BasicColor = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};

/// RGB color representation
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// Enhanced terminal cell with hyperlinks and combining characters
pub const Cell = struct {
    /// Main rune of the cell (0 = empty)
    rune: u21 = 0,
    /// Combining characters for complex grapheme clusters
    comb: ?[]const u21 = null,
    /// Display width (0, 1, or 2)
    width: u8 = 0,
    /// Cell styling
    style: Style = .{},
    /// Hyperlink information
    link: Link = .{},

    /// Blank cell (space character)
    pub const BLANK = Cell{ .rune = ' ', .width = 1 };

    /// Empty cell (zero width, used for wide character placeholders)
    pub const EMPTY = Cell{};

    pub fn isEmpty(self: Cell) bool {
        return self.rune == 0 and self.width == 0 and (self.comb == null or self.comb.?.len == 0);
    }

    pub fn equal(self: Cell, other: Cell) bool {
        return self.rune == other.rune and
            self.width == other.width and
            runesEqual(self.comb, other.comb) and
            self.style.equal(other.style) and
            self.link.equal(other.link);
    }

    pub fn reset(self: *Cell) void {
        self.rune = 0;
        self.comb = null;
        self.width = 0;
        self.style.reset();
        self.link.reset();
    }

    /// Check if cell is a clear space (space with no visible attributes)
    pub fn isClear(self: Cell) bool {
        return self.rune == ' ' and
            (self.comb == null or self.comb.?.len == 0) and
            self.width == 1 and
            self.style.isClear() and
            self.link.isEmpty();
    }

    /// Create a blank cell with the same style
    pub fn makeBlank(self: Cell) Cell {
        return Cell{
            .rune = ' ',
            .width = 1,
            .style = self.style,
            .link = self.link,
        };
    }

    /// Clone the cell
    pub fn clone(self: Cell, allocator: std.mem.Allocator) !Cell {
        var result = self;
        if (self.comb) |comb| {
            result.comb = try allocator.dupe(u21, comb);
        }
        return result;
    }

    /// Get string representation of the cell content
    pub fn toString(self: Cell, allocator: std.mem.Allocator) ![]u8 {
        if (self.rune == 0) return try allocator.dupe(u8, "");

        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        // Add main rune
        var utf8_buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(self.rune, &utf8_buf) catch return try allocator.dupe(u8, "");
        try result.appendSlice(utf8_buf[0..len]);

        // Add combining characters
        if (self.comb) |comb| {
            for (comb) |c| {
                const comb_len = std.unicode.utf8Encode(c, &utf8_buf) catch continue;
                try result.appendSlice(utf8_buf[0..comb_len]);
            }
        }

        return try result.toOwnedSlice();
    }

    /// Append runes to the cell (for combining characters)
    pub fn append(self: *Cell, allocator: std.mem.Allocator, runes: []const u21) !void {
        if (runes.len == 0) return;

        if (self.rune == 0 and runes.len > 0) {
            self.rune = runes[0];
            if (runes.len == 1) return;

            if (runes.len > 1) {
                self.comb = try allocator.dupe(u21, runes[1..]);
            }
        } else {
            // Append to combining characters
            var new_comb = std.ArrayList(u21).init(allocator);
            defer new_comb.deinit();

            if (self.comb) |existing| {
                try new_comb.appendSlice(existing);
                allocator.free(existing);
            }

            try new_comb.appendSlice(runes);
            self.comb = try new_comb.toOwnedSlice();
        }
    }
};

fn runesEqual(a: ?[]const u21, b: ?[]const u21) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;

    const slice_a = a.?;
    const slice_b = b.?;

    if (slice_a.len != slice_b.len) return false;

    for (slice_a, slice_b) |ra, rb| {
        if (ra != rb) return false;
    }

    return true;
}

/// Rectangle for clipping operations
pub const Rectangle = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,

    pub fn contains(self: Rectangle, x: usize, y: usize) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn intersection(self: Rectangle, other: Rectangle) ?Rectangle {
        const left = @max(self.x, other.x);
        const top = @max(self.y, other.y);
        const right = @min(self.x + self.width, other.x + other.width);
        const bottom = @min(self.y + self.height, other.y + other.height);

        if (left >= right or top >= bottom) return null;

        return Rectangle{
            .x = left,
            .y = top,
            .width = right - left,
            .height = bottom - top,
        };
    }
};

/// Line in the terminal buffer
pub const Line = struct {
    cells: []Cell,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, line_width: usize) !Line {
        const cells = try allocator.alloc(Cell, line_width);
        for (cells) |*cell| {
            cell.* = Cell.EMPTY;
        }
        return Line{ .cells = cells, .allocator = allocator };
    }

    pub fn deinit(self: *Line) void {
        // Free combining characters in cells
        for (self.cells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
        }
        self.allocator.free(self.cells);
    }

    pub fn width(self: Line) usize {
        return self.cells.len;
    }

    pub fn at(self: Line, x: usize) ?*Cell {
        if (x >= self.cells.len) return null;
        return &self.cells[x];
    }

    pub fn setCell(self: *Line, x: usize, cell: Cell) !bool {
        if (x >= self.cells.len) return false;

        const target = &self.cells[x];

        // Clean up old cell
        if (target.comb) |old_comb| {
            self.allocator.free(old_comb);
        }

        // Copy new cell
        target.* = cell;

        // Handle wide characters
        if (cell.width > 1) {
            // Mark continuation cells as empty
            var j: usize = 1;
            while (j < cell.width and x + j < self.cells.len) : (j += 1) {
                if (self.cells[x + j].comb) |old_comb| {
                    self.allocator.free(old_comb);
                }
                self.cells[x + j] = Cell.EMPTY;
            }
        }

        return true;
    }

    /// Get string representation of the line
    pub fn toString(self: Line, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        for (self.cells) |cell| {
            if (cell.isEmpty()) {
                continue;
            } else {
                const cell_str = try cell.toString(allocator);
                defer allocator.free(cell_str);
                try result.appendSlice(cell_str);
            }
        }

        // Trim trailing spaces
        while (result.items.len > 0 and result.items[result.items.len - 1] == ' ') {
            _ = result.pop();
        }

        return try result.toOwnedSlice();
    }
};

/// Enhanced buffer with advanced operations
pub const Buffer = struct {
    lines: []Line,
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer_width: usize, buffer_height: usize) !Buffer {
        const lines = try allocator.alloc(Line, buffer_height);
        errdefer allocator.free(lines);

        for (lines, 0..) |*line_ptr, i| {
            line_ptr.* = Line.init(allocator, buffer_width) catch |err| {
                // Cleanup on error
                for (lines[0..i]) |*cleanup_line| {
                    cleanup_line.deinit();
                }
                return err;
            };
        }

        return Buffer{
            .lines = lines,
            .width = buffer_width,
            .height = buffer_height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines) |*line_ptr| {
            line_ptr.deinit();
        }
        self.allocator.free(self.lines);
    }

    pub fn line(self: *Buffer, y: usize) ?*Line {
        if (y >= self.height) return null;
        return &self.lines[y];
    }

    pub fn cell(self: *Buffer, x: usize, y: usize) ?*Cell {
        const target_line = self.line(y) orelse return null;
        return target_line.at(x);
    }

    pub fn setCell(self: *Buffer, x: usize, y: usize, new_cell: Cell) !bool {
        const target_line = self.line(y) orelse return false;
        return try target_line.setCell(x, new_cell);
    }

    pub fn bounds(self: Buffer) Rectangle {
        return Rectangle{
            .x = 0,
            .y = 0,
            .width = self.width,
            .height = self.height,
        };
    }

    /// Resize buffer maintaining content where possible
    pub fn resize(self: *Buffer, new_width: usize, new_height: usize) !void {
        if (new_width == 0 or new_height == 0) {
            // Clean up existing
            for (self.lines) |*line_ptr| {
                line_ptr.deinit();
            }
            self.allocator.free(self.lines);
            self.lines = &[_]Line{};
            self.width = 0;
            self.height = 0;
            return;
        }

        // Create new lines
        const new_lines = try self.allocator.alloc(Line, new_height);
        errdefer self.allocator.free(new_lines);

        for (new_lines, 0..) |*line_ptr, i| {
            line_ptr.* = Line.init(self.allocator, new_width) catch |err| {
                // Cleanup on error
                for (new_lines[0..i]) |*cleanup_line| {
                    cleanup_line.deinit();
                }
                return err;
            };
        }

        // Copy existing content
        const copy_height = @min(self.height, new_height);
        const copy_width = @min(self.width, new_width);

        for (0..copy_height) |y| {
            for (0..copy_width) |x| {
                if (self.cell(x, y)) |old_cell| {
                    _ = try new_lines[y].setCell(x, old_cell.*);
                }
            }
        }

        // Replace old lines
        for (self.lines) |*line_ptr| {
            line_ptr.deinit();
        }
        self.allocator.free(self.lines);

        self.lines = new_lines;
        self.width = new_width;
        self.height = new_height;
    }

    /// Fill rectangle with given cell
    pub fn fillRect(self: *Buffer, rect: Rectangle, fill_cell: Cell) !void {
        const clipped = rect.intersection(self.bounds()) orelse return;

        for (clipped.y..clipped.y + clipped.height) |y| {
            for (clipped.x..clipped.x + clipped.width) |x| {
                _ = try self.setCell(x, y, fill_cell);
            }
        }
    }

    /// Clear rectangle to blank cells
    pub fn clearRect(self: *Buffer, rect: Rectangle) !void {
        try self.fillRect(rect, Cell.BLANK);
    }

    /// Insert lines at given position within rectangle rect_bounds
    pub fn insertLines(self: *Buffer, y: usize, n: usize, fill_cell: Cell, rect_bounds: Rectangle) !void {
        if (n == 0 or y < rect_bounds.y or y >= rect_bounds.y + rect_bounds.height) return;

        // Limit insertion to available space
        const max_lines = (rect_bounds.y + rect_bounds.height) - y;
        const lines_to_insert = @min(n, max_lines);

        // Move existing lines down
        var i = rect_bounds.y + rect_bounds.height - 1;
        while (i >= y + lines_to_insert) : (i -= 1) {
            if (i < lines_to_insert) break;

            // Move cells within horizontal rect_bounds
            for (rect_bounds.x..rect_bounds.x + rect_bounds.width) |x| {
                if (self.cell(x, i - lines_to_insert)) |source_cell| {
                    _ = try self.setCell(x, i, source_cell.*);
                }
            }

            if (i == 0) break;
        }

        // Fill new lines
        for (y..y + lines_to_insert) |row| {
            for (rect_bounds.x..rect_bounds.x + rect_bounds.width) |x| {
                _ = try self.setCell(x, row, fill_cell);
            }
        }
    }

    /// Delete lines at given position within rectangle rect_bounds
    pub fn deleteLines(self: *Buffer, y: usize, n: usize, fill_cell: Cell, rect_bounds: Rectangle) !void {
        if (n == 0 or y < rect_bounds.y or y >= rect_bounds.y + rect_bounds.height) return;

        // Limit deletion to available space
        const max_lines = (rect_bounds.y + rect_bounds.height) - y;
        const lines_to_delete = @min(n, max_lines);

        // Move lines up
        for (y..rect_bounds.y + rect_bounds.height - lines_to_delete) |dst_y| {
            const src_y = dst_y + lines_to_delete;
            for (rect_bounds.x..rect_bounds.x + rect_bounds.width) |x| {
                if (self.cell(x, src_y)) |source_cell| {
                    _ = try self.setCell(x, dst_y, source_cell.*);
                }
            }
        }

        // Fill bottom lines
        const fill_start = rect_bounds.y + rect_bounds.height - lines_to_delete;
        for (fill_start..rect_bounds.y + rect_bounds.height) |row| {
            for (rect_bounds.x..rect_bounds.x + rect_bounds.width) |x| {
                _ = try self.setCell(x, row, fill_cell);
            }
        }
    }

    /// Insert cells at given position within rect_bounds
    pub fn insertCells(self: *Buffer, x: usize, y: usize, n: usize, fill_cell: Cell, rect_bounds: Rectangle) !void {
        if (n == 0 or !rect_bounds.contains(x, y)) return;

        const line_obj = self.line(y) orelse return;

        // Limit insertion to line rect_bounds
        const max_cells = (rect_bounds.x + rect_bounds.width) - x;
        const cells_to_insert = @min(n, max_cells);

        // Move existing cells right
        var i = rect_bounds.x + rect_bounds.width - 1;
        while (i >= x + cells_to_insert) : (i -= 1) {
            if (i < cells_to_insert) break;

            if (line_obj.at(i - cells_to_insert)) |source_cell| {
                _ = try line_obj.setCell(i, source_cell.*);
            }

            if (i == 0) break;
        }

        // Fill new cells
        for (x..x + cells_to_insert) |col| {
            _ = try line_obj.setCell(col, fill_cell);
        }
    }

    /// Delete cells at given position within rect_bounds
    pub fn deleteCells(self: *Buffer, x: usize, y: usize, n: usize, fill_cell: Cell, rect_bounds: Rectangle) !void {
        if (n == 0 or !rect_bounds.contains(x, y)) return;

        const line_obj = self.line(y) orelse return;

        // Limit deletion to available space
        const max_cells = (rect_bounds.x + rect_bounds.width) - x;
        const cells_to_delete = @min(n, max_cells);

        // Move cells left
        for (x..rect_bounds.x + rect_bounds.width - cells_to_delete) |dst_x| {
            const src_x = dst_x + cells_to_delete;
            if (line_obj.at(src_x)) |source_cell| {
                _ = try line_obj.setCell(dst_x, source_cell.*);
            }
        }

        // Fill remaining cells
        const fill_start = rect_bounds.x + rect_bounds.width - cells_to_delete;
        for (fill_start..rect_bounds.x + rect_bounds.width) |col| {
            _ = try line_obj.setCell(col, fill_cell);
        }
    }

    /// Get string representation of the buffer
    pub fn toString(self: Buffer, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        for (self.lines, 0..) |line_obj, i| {
            const line_str = try line_obj.toString(allocator);
            defer allocator.free(line_str);

            try result.appendSlice(line_str);
            if (i < self.lines.len - 1) {
                try result.appendSlice("\r\n");
            }
        }

        return try result.toOwnedSlice();
    }
};

/// Convenience constructors
pub fn newCell(rune: u21, style: Style) Cell {
    return Cell{ .rune = rune, .width = if (rune == ' ') 1 else calculateWidth(rune), .style = style };
}

pub fn newCellWithLink(rune: u21, style: Style, link: Link) Cell {
    return Cell{
        .rune = rune,
        .width = if (rune == ' ') 1 else calculateWidth(rune),
        .style = style,
        .link = link,
    };
}

// Placeholder for width calculation - would use proper wcwidth implementation
fn calculateWidth(rune: u21) u8 {
    // Simplified width calculation
    if (rune < 0x20) return 0; // Control characters
    if (rune == 0x7F) return 0; // DEL
    if (rune >= 0x1100 and rune <= 0x115F) return 2; // Hangul Jamo
    if (rune >= 0x2E80 and rune <= 0x9FFF) return 2; // CJK
    if (rune >= 0xA960 and rune <= 0xA97F) return 2; // Hangul Jamo Extended-A
    if (rune >= 0xAC00 and rune <= 0xD7AF) return 2; // Hangul Syllables
    if (rune >= 0xF900 and rune <= 0xFAFF) return 2; // CJK Compatibility Ideographs
    if (rune >= 0xFE10 and rune <= 0xFE19) return 2; // Vertical forms
    if (rune >= 0xFE30 and rune <= 0xFE6F) return 2; // CJK Compatibility Forms
    if (rune >= 0xFF00 and rune <= 0xFF60) return 2; // Fullwidth Forms
    if (rune >= 0xFFE0 and rune <= 0xFFE6) return 2; // Fullwidth Forms

    return 1;
}

// Tests
test "enhanced cell with combining characters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cell = Cell{ .rune = 'e', .width = 1 };
    try cell.append(allocator, &[_]u21{0x301}); // Combining acute accent
    defer if (cell.comb) |comb| allocator.free(comb);

    try testing.expect(cell.rune == 'e');
    try testing.expect(cell.comb != null);
    try testing.expect(cell.comb.?.len == 1);
    try testing.expect(cell.comb.?[0] == 0x301);
}

test "hyperlink support" {
    const testing = std.testing;

    const link = Link{ .url = "https://example.com", .params = "id=test" };
    const cell = newCellWithLink('A', .{}, link);

    try testing.expect(cell.rune == 'A');
    try testing.expect(std.mem.eql(u8, cell.link.url, "https://example.com"));
    try testing.expect(std.mem.eql(u8, cell.link.params, "id=test"));
}

test "buffer operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    // Set some content
    _ = try buffer.setCell(2, 2, newCell('X', .{}));

    // Test bounds
    const buf_bounds = buffer.bounds();
    try testing.expect(buf_bounds.width == 10);
    try testing.expect(buf_bounds.height == 5);

    // Test cell retrieval
    const retrieved = buffer.cell(2, 2).?;
    try testing.expect(retrieved.rune == 'X');
}

test "line insert and delete operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    // Fill with test content
    for (0..10) |y| {
        for (0..10) |x| {
            _ = try buffer.setCell(x, y, newCell(@as(u21, @intCast('A' + y)), .{}));
        }
    }

    // Insert 2 lines at position 3
    const rect_bounds = Rectangle{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try buffer.insertLines(3, 2, Cell.BLANK, rect_bounds);

    // Check that line that was at position 3 is now at position 5
    const cell_at_5 = buffer.cell(0, 5).?;
    try testing.expect(cell_at_5.rune == @as(u21, @intCast('A' + 3)));
}

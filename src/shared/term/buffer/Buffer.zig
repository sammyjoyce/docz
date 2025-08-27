const std = @import("std");

// Unicode width calculation for cell buffer
fn codepointWidth(codepoint: u21, options: anytype) u8 {
    _ = options; // For now, ignore options

    // Handle common ASCII range quickly
    if (codepoint < 0x80) {
        if (codepoint < 0x20 or codepoint == 0x7F) {
            return 0; // Control characters
        }
        return 1; // Normal ASCII
    }

    // Check for zero-width characters (combining marks, etc.)
    if ((codepoint >= 0x0300 and codepoint <= 0x036F) or // Combining Diacritical Marks
        (codepoint >= 0x1AB0 and codepoint <= 0x1AFF) or // Combining Diacritical Marks Extended
        (codepoint >= 0x1DC0 and codepoint <= 0x1DFF) or // Combining Diacritical Marks Supplement
        (codepoint >= 0x20D0 and codepoint <= 0x20FF) or // Combining Diacritical Marks for Symbols
        (codepoint >= 0xFE20 and codepoint <= 0xFE2F))
    { // Combining Half Marks
        return 0;
    }

    // Check for wide characters (CJK ideographs, etc.)
    if ((codepoint >= 0x1100 and codepoint <= 0x115F) or // Hangul Jamo
        (codepoint >= 0x2E80 and codepoint <= 0x2EFF) or // CJK Radicals Supplement
        (codepoint >= 0x2F00 and codepoint <= 0x2FDF) or // Kangxi Radicals
        (codepoint >= 0x3000 and codepoint <= 0x303F) or // CJK Symbols and Punctuation
        (codepoint >= 0x3040 and codepoint <= 0x309F) or // Hiragana
        (codepoint >= 0x30A0 and codepoint <= 0x30FF) or // Katakana
        (codepoint >= 0x3100 and codepoint <= 0x312F) or // Bopomofo
        (codepoint >= 0x3130 and codepoint <= 0x318F) or // Hangul Compatibility Jamo
        (codepoint >= 0x3190 and codepoint <= 0x319F) or // Kanbun
        (codepoint >= 0x31A0 and codepoint <= 0x31BF) or // Bopomofo Extended
        (codepoint >= 0x31C0 and codepoint <= 0x31EF) or // CJK Strokes
        (codepoint >= 0x31F0 and codepoint <= 0x31FF) or // Katakana Phonetic Extensions
        (codepoint >= 0x3200 and codepoint <= 0x32FF) or // Enclosed CJK Letters and Months
        (codepoint >= 0x3300 and codepoint <= 0x33FF) or // CJK Compatibility
        (codepoint >= 0x3400 and codepoint <= 0x4DBF) or // CJK Unified Ideographs Extension A
        (codepoint >= 0x4DC0 and codepoint <= 0x4DFF) or // Yijing Hexagram Symbols
        (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or // CJK Unified Ideographs
        (codepoint >= 0xA000 and codepoint <= 0xA48F) or // Yi Syllables
        (codepoint >= 0xA490 and codepoint <= 0xA4CF) or // Yi Radicals
        (codepoint >= 0xAC00 and codepoint <= 0xD7AF) or // Hangul Syllables
        (codepoint >= 0xD7B0 and codepoint <= 0xD7FF) or // Hangul Jamo Extended-B
        (codepoint >= 0xD800 and codepoint <= 0xDB7F) or // High Surrogates (invalid but treat as wide)
        (codepoint >= 0xDB80 and codepoint <= 0xDBFF) or // High Private Use Surrogates
        (codepoint >= 0xDC00 and codepoint <= 0xDFFF) or // Low Surrogates
        (codepoint >= 0xE000 and codepoint <= 0xF8FF) or // Private Use Area
        (codepoint >= 0xF900 and codepoint <= 0xFAFF) or // CJK Compatibility Ideographs
        (codepoint >= 0xFB00 and codepoint <= 0xFB4F) or // Alphabetic Presentation Forms (some wide)
        (codepoint >= 0xFE10 and codepoint <= 0xFE1F) or // Vertical Forms
        (codepoint >= 0xFE30 and codepoint <= 0xFE4F) or // CJK Compatibility Forms
        (codepoint >= 0xFE50 and codepoint <= 0xFE6F) or // Small Form Variants
        (codepoint >= 0xFE70 and codepoint <= 0xFEFF) or // Arabic Presentation Forms-B
        (codepoint >= 0xFF00 and codepoint <= 0xFF60) or // Fullwidth ASCII variants
        (codepoint >= 0xFFE0 and codepoint <= 0xFFE6) or // Fullwidth symbol variants
        codepoint == 0x20000 or codepoint == 0x2A6DF or codepoint == 0x2B738 or codepoint == 0x2B739 or codepoint == 0x2B73A)
    {
        return 2;
    }

    // Default to narrow (1 width) for all other characters
    return 1;
}

/// Cell-based terminal display buffer
/// Combines cell buffer functionality for optimal performance
/// Supports differential rendering, styling, combining characters, and hyperlinks
/// Underline style for text
pub const UnderlineStyle = enum(u8) {
    none = 0,
    single = 1,
    double = 2,
    curly = 3,
    dotted = 4,
    dashed = 5,

    pub fn toAnsiCode(self: UnderlineStyle) []const u8 {
        return switch (self) {
            .none => "24",
            .single => "4",
            .double => "21",
            .curly => "4:3",
            .dotted => "4:4",
            .dashed => "4:5",
        };
    }
};

/// Text attributes bitmask for styling
pub const AttrMask = packed struct {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    slowBlink: bool = false,
    rapidBlink: bool = false,
    reverse: bool = false,
    conceal: bool = false,
    strikethrough: bool = false,

    pub fn isEmpty(self: AttrMask) bool {
        const asInt: u8 = @bitCast(self);
        return asInt == 0;
    }

    pub fn eql(self: AttrMask, other: AttrMask) bool {
        const selfInt: u8 = @bitCast(self);
        const otherInt: u8 = @bitCast(other);
        return selfInt == otherInt;
    }
};

/// Color representation that supports ANSI colors and RGB
pub const Color = union(enum) {
    default,
    ansi: u8, // 0-15 ANSI colors
    ansi256: u8, // 0-255 extended palette
    rgb: struct { r: u8, g: u8, b: u8 },

    pub fn eql(self: Color, other: Color) bool {
        return switch (self) {
            .default => other == .default,
            .ansi => |c| other == .ansi and other.ansi == c,
            .ansi256 => |c| other == .ansi256 and other.ansi256 == c,
            .rgb => |rgb| other == .rgb and
                other.rgb.r == rgb.r and
                other.rgb.g == rgb.g and
                other.rgb.b == rgb.b,
        };
    }

    /// Convert to ANSI escape sequence
    pub fn toAnsiSeq(self: Color, allocator: std.mem.Allocator, isBg: bool) ![]u8 {
        var seq = std.ArrayList(u8).init(allocator);
        errdefer seq.deinit();

        const prefix = if (isBg) "48" else "38";

        switch (self) {
            .default => return allocator.dupe(u8, if (isBg) "49" else "39"),
            .ansi => |c| {
                if (c < 8) {
                    try seq.writer().print("{s};5;{d}", .{ prefix, c });
                } else {
                    try seq.writer().print("{s};5;{d}", .{ prefix, c });
                }
            },
            .ansi256 => |c| {
                try seq.writer().print("{s};5;{d}", .{ prefix, c });
            },
            .rgb => |rgb| {
                try seq.writer().print("{s};2;{d};{d};{d}", .{ prefix, rgb.r, rgb.g, rgb.b });
            },
        }

        return seq.toOwnedSlice();
    }
};

/// Hyperlink information for cells
pub const Link = struct {
    url: ?[]const u8 = null,
    params: ?[]const u8 = null,

    pub fn isEmpty(self: Link) bool {
        return self.url == null and self.params == null;
    }

    pub fn eql(self: Link, other: Link) bool {
        const urlMatch = blk: {
            if (self.url == null and other.url == null) break :blk true;
            if (self.url == null or other.url == null) break :blk false;
            break :blk std.mem.eql(u8, self.url.?, other.url.?);
        };

        const paramsMatch = blk: {
            if (self.params == null and other.params == null) break :blk true;
            if (self.params == null or other.params == null) break :blk false;
            break :blk std.mem.eql(u8, self.params.?, other.params.?);
        };

        return urlMatch and paramsMatch;
    }

    pub fn reset(self: *Link) void {
        self.url = null;
        self.params = null;
    }
};

/// Cell style combining colors and attributes
pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    ulColor: Color = .default, // Underline color
    attrs: AttrMask = .{},
    ulStyle: UnderlineStyle = .none,

    pub fn eql(self: Style, other: Style) bool {
        return self.fg.eql(other.fg) and
            self.bg.eql(other.bg) and
            self.ulColor.eql(other.ulColor) and
            self.attrs.eql(other.attrs) and
            self.ulStyle == other.ulStyle;
    }

    pub fn isEmpty(self: Style) bool {
        return self.fg == .default and
            self.bg == .default and
            self.ulColor == .default and
            self.attrs.isEmpty() and
            self.ulStyle == .none;
    }

    pub fn reset(self: *Style) void {
        self.* = Style{};
    }

    /// Generate ANSI sequence for this style
    pub fn toAnsiSeq(self: Style, allocator: std.mem.Allocator) ![]u8 {
        if (self.isEmpty()) {
            return allocator.dupe(u8, "\x1b[0m");
        }

        var seq = std.ArrayList(u8).init(allocator);
        errdefer seq.deinit();

        try seq.appendSlice("\x1b[");
        var first = true;

        // Attributes
        if (self.attrs.bold) {
            if (!first) try seq.append(';');
            try seq.appendSlice("1");
            first = false;
        }
        if (self.attrs.faint) {
            if (!first) try seq.append(';');
            try seq.appendSlice("2");
            first = false;
        }
        if (self.attrs.italic) {
            if (!first) try seq.append(';');
            try seq.appendSlice("3");
            first = false;
        }
        if (self.attrs.slowBlink) {
            if (!first) try seq.append(';');
            try seq.appendSlice("5");
            first = false;
        }
        if (self.attrs.rapidBlink) {
            if (!first) try seq.append(';');
            try seq.appendSlice("6");
            first = false;
        }
        if (self.attrs.reverse) {
            if (!first) try seq.append(';');
            try seq.appendSlice("7");
            first = false;
        }
        if (self.attrs.conceal) {
            if (!first) try seq.append(';');
            try seq.appendSlice("8");
            first = false;
        }
        if (self.attrs.strikethrough) {
            if (!first) try seq.append(';');
            try seq.appendSlice("9");
            first = false;
        }

        // Underline style
        if (self.ulStyle != .none) {
            if (!first) try seq.append(';');
            try seq.appendSlice(self.ulStyle.toAnsiCode());
            first = false;
        }

        // Colors
        if (self.fg != .default) {
            if (!first) try seq.append(';');
            const fgSeq = try self.fg.toAnsiSeq(allocator, false);
            defer allocator.free(fgSeq);
            try seq.appendSlice(fgSeq);
            first = false;
        }

        if (self.bg != .default) {
            if (!first) try seq.append(';');
            const bgSeq = try self.bg.toAnsiSeq(allocator, true);
            defer allocator.free(bgSeq);
            try seq.appendSlice(bgSeq);
            first = false;
        }

        if (self.ulColor != .default) {
            if (!first) try seq.append(';');
            try seq.appendSlice("58;5;");
            if (self.ulColor == .rgb) {
                try seq.writer().print("{d};{d};{d}", .{ self.ulColor.rgb.r, self.ulColor.rgb.g, self.ulColor.rgb.b });
            }
            first = false;
        }

        try seq.append('m');
        return seq.toOwnedSlice();
    }
};

/// Terminal cell with comprehensive features
pub const Cell = struct {
    /// Primary rune (0 = empty cell)
    rune: u21 = 0,
    /// Combining characters for complex graphemes
    comb: ?[]u21 = null,
    /// Display width (0, 1, or 2+ for wide chars)
    width: u8 = 0,
    /// Visual style
    style: Style = .{},
    /// Hyperlink data
    link: Link = .{},
    /// Whether this cell is a continuation of a wide character
    isContinuation: bool = false,

    pub fn isEmpty(self: Cell) bool {
        return self.rune == 0 and self.width == 0 and
            (self.comb == null or self.comb.?.len == 0);
    }

    pub fn isWide(self: Cell) bool {
        return self.width > 1;
    }

    pub fn isBlank(self: Cell) bool {
        return self.rune == ' ' and
            (self.comb == null or self.comb.?.len == 0) and
            self.width == 1 and self.style.isEmpty() and self.link.isEmpty();
    }

    pub fn eql(self: Cell, other: Cell) bool {
        const combMatch = blk: {
            if (self.comb == null and other.comb == null) break :blk true;
            if (self.comb == null or other.comb == null) break :blk false;
            if (self.comb.?.len != other.comb.?.len) break :blk false;
            for (self.comb.?, other.comb.?) |a, b| {
                if (a != b) break :blk false;
            }
            break :blk true;
        };

        return self.rune == other.rune and
            self.width == other.width and
            self.style.eql(other.style) and
            self.link.eql(other.link) and
            combMatch;
    }

    pub fn reset(self: *Cell) void {
        self.rune = 0;
        self.comb = null;
        self.width = 0;
        self.style.reset();
        self.link.reset();
        self.isContinuation = false;
    }

    pub fn clear(self: *Cell) void {
        self.reset();
    }

    pub fn makeBlank(self: *Cell) void {
        self.rune = ' ';
        self.comb = null;
        self.width = 1;
        self.isContinuation = false;
        // Keep style and link
    }

    /// Convert cell content to string
    pub fn toString(self: Cell, allocator: std.mem.Allocator) ![]u8 {
        if (self.isEmpty()) return allocator.dupe(u8, "");

        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(self.rune, &buf) catch return result.toOwnedSlice();
        try result.appendSlice(buf[0..len]);

        if (self.comb) |comb| {
            for (comb) |c| {
                const comb_len = std.unicode.utf8Encode(c, &buf) catch continue;
                try result.appendSlice(buf[0..comb_len]);
            }
        }

        return result.toOwnedSlice();
    }

    /// Add combining character to this cell
    pub fn addCombining(self: *Cell, allocator: std.mem.Allocator, combining_char: u21) !void {
        if (self.comb == null) {
            self.comb = try allocator.alloc(u21, 1);
            self.comb.?[0] = combining_char;
        } else {
            const comb = try allocator.realloc(self.comb.?, self.comb.?.len + 1);
            comb[self.comb.?.len] = combining_char;
            self.comb = comb;
        }
    }
};

/// Rectangle for bounded operations
pub const Rectangle = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn contains(self: Rectangle, px: i32, py: i32) bool {
        return px >= self.x and px < self.x + @as(i32, @intCast(self.width)) and
            py >= self.y and py < self.y + @as(i32, @intCast(self.height));
    }

    pub fn intersect(self: Rectangle, other: Rectangle) Rectangle {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + @as(i32, @intCast(self.width)), other.x + @as(i32, @intCast(other.width)));
        const y2 = @min(self.y + @as(i32, @intCast(self.height)), other.y + @as(i32, @intCast(other.height)));

        if (x2 <= x1 or y2 <= y1) {
            return Rectangle{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }

        return Rectangle{
            .x = x1,
            .y = y1,
            .width = @intCast(x2 - x1),
            .height = @intCast(y2 - y1),
        };
    }
};

/// Cell buffer with comprehensive functionality
pub const CellBuffer = struct {
    allocator: std.mem.Allocator,
    /// Current terminal dimensions
    width: usize,
    height: usize,
    /// Cell data stored as width * height array
    cells: []Cell,
    /// Previous frame for differential rendering
    previousCells: []Cell,
    /// Current cursor position
    cursorX: usize = 0,
    cursorY: usize = 0,
    /// Whether buffer needs full redraw
    dirty: bool = true,

    const Self = @This();

    /// Initialize cell buffer with given dimensions
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Self {
        const total_cells = width * height;
        const cells = try allocator.alloc(Cell, total_cells);
        const previousCells = try allocator.alloc(Cell, total_cells);

        // Initialize all cells as empty
        for (cells) |*cell| {
            cell.reset();
        }
        for (previousCells) |*cell| {
            cell.reset();
        }

        return Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .cells = cells,
            .previousCells = previousCells,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *Self) void {
        // Free combining characters
        for (self.cells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
        }
        for (self.previousCells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
        }
        self.allocator.free(self.cells);
        self.allocator.free(self.previousCells);
    }

    /// Resize buffer to new dimensions
    pub fn resize(self: *Self, width: usize, height: usize) !void {
        const total = width * height;
        const cells = try self.allocator.alloc(Cell, total);
        const previous = try self.allocator.alloc(Cell, total);

        // Initialize new cells
        for (cells) |*cell| {
            cell.reset();
        }
        for (previous) |*cell| {
            cell.reset();
        }

        // Copy existing content if possible
        const copy_height = @min(self.height, height);
        const copy_width = @min(self.width, width);

        for (0..copy_height) |y| {
            for (0..copy_width) |x| {
                const idx = y * self.width + x;
                const new_idx = y * width + x;
                cells[new_idx] = self.cells[idx];
                previous[new_idx] = self.previousCells[idx];
                // Don't free old combining chars, they're moved
                self.cells[idx].comb = null;
                self.previousCells[idx].comb = null;
            }
        }

        // Free old arrays
        self.allocator.free(self.cells);
        self.allocator.free(self.previousCells);
        self.cells = cells;
        self.previousCells = previous;
        self.width = width;
        self.height = height;
        self.dirty = true;

        // Clamp cursor position to new bounds
        self.cursorX = @min(self.cursorX, width - 1);
        self.cursorY = @min(self.cursorY, height - 1);
    }

    /// Get cell at position (bounds-checked)
    pub fn getCell(self: Self, x: usize, y: usize) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        return &self.cells[y * self.width + x];
    }

    /// Set cell at position with character and style
    pub fn setCell(self: *Self, x: usize, y: usize, rune: u21, style: Style) !void {
        if (x >= self.width or y >= self.height) return;

        const cell = &self.cells[y * self.width + x];
        const charWidth = codepointWidth(rune, .{});

        cell.* = Cell{ .rune = rune, .width = @intCast(codepointWidth(rune, .{})), .style = style, .link = .{}, .comb = null };
        if (charWidth == 2 and x + 1 < self.width) {
            // First cell contains the character
            cell.rune = rune;
            cell.width = 2;
            cell.style = style;
            cell.isContinuation = false;

            // Second cell is marked as continuation
            const continuation_cell = &self.cells[y * self.width + x + 1];
            continuation_cell.rune = 0;
            continuation_cell.width = 0;
            continuation_cell.style = style;
            continuation_cell.isContinuation = true;
        } else if (charWidth == 0) {
            // Zero-width character, try to add as combining character to previous cell
            if (x > 0) {
                const prev_cell = &self.cells[y * self.width + x - 1];
                if (prev_cell.comb == null) {
                    prev_cell.comb = try self.allocator.alloc(u21, 1);
                    prev_cell.comb.?[0] = rune;
                } else {
                    const prev_comb = prev_cell.comb.?;
                    prev_cell.comb = try self.allocator.realloc(prev_comb, prev_comb.len + 1);
                    prev_cell.comb.?[prev_comb.len] = rune;
                }
                return; // Don't modify current cell
            }
        }

        if (cell.isWide()) {
            // Clear any existing wide character continuation
            cleanupWideCell(self, x, y);
        }

        cell.rune = rune;
        cell.style = style;
        if (charWidth <= 1) {
            cell.width = charWidth;
            cell.style = style;
            cell.isContinuation = false;
        }
    }

    /// Set cell with full Cell struct
    pub fn setCellFull(self: *Self, x: usize, y: usize, cell: Cell) bool {
        if (x >= self.width or y >= self.height) return false;

        const idx = y * self.width + x;

        // Handle wide character cleanup
        self.cleanupWideCell(x, y);

        // Clone the cell data
        var cloned_cell = cell;
        if (cell.comb) |comb| {
            cloned_cell.comb = self.allocator.dupe(u21, comb) catch null;
        }

        self.cells[idx] = cloned_cell;

        // Mark subsequent cells for wide characters
        if (cloned_cell.isWide()) {
            var i: usize = 1;
            while (i < cloned_cell.width and x + i < self.width) : (i += 1) {
                const wide_idx = (y * self.width) + (x + i);
                self.cells[wide_idx].reset(); // Mark as continuation
                self.cells[wide_idx].isContinuation = true;
            }
        }

        return true;
    }

    fn cleanupWideCell(self: *Self, x: usize, y: usize) void {
        const current_cell = self.getCell(x, y) orelse return;

        // If overwriting a wide character, blank out all its cells
        if (current_cell.isWide()) {
            var i: usize = 0;
            while (i < current_cell.width and x + i < self.width) : (i += 1) {
                if (self.getCell(x + i, y)) |cell| {
                    cell.reset();
                    cell.makeBlank();
                }
            }
        }

        // If overwriting part of a wide character, find and blank the whole thing
        if (current_cell.isEmpty() and x > 0) {
            var check_x = x - 1;
            while (check_x >= 0) : (check_x -= 1) {
                if (self.getCell(check_x, y)) |cell| {
                    if (cell.isWide() and check_x + cell.width > x) {
                        // This wide char overlaps our position, blank it
                        var i: usize = 0;
                        while (i < cell.width and check_x + i < self.width) : (i += 1) {
                            if (self.getCell(check_x + i, y)) |wide_cell| {
                                wide_cell.reset();
                                wide_cell.makeBlank();
                            }
                        }
                        break;
                    }
                    if (!cell.isEmpty()) break; // Found a non-wide character
                }
                if (check_x == 0) break;
            }
        }
    }

    /// Write UTF-8 text at position with style
    pub fn writeText(self: *Self, x: usize, y: usize, text: []const u8, style: Style) !usize {
        var pos_x = x;
        var i: usize = 0;

        while (i < text.len and pos_x < self.width) {
            const seq_len = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
            if (i + seq_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i .. i + seq_len]) catch {
                i += 1;
                continue;
            };

            try self.setCell(pos_x, y, codepoint, style);

            const charWidth = codepointWidth(codepoint, .{});
            pos_x += @max(1, charWidth); // Always advance at least 1 for wide chars
            i += seq_len;
        }

        return pos_x - x; // Return number of columns written
    }

    /// Clear entire buffer
    pub fn clear(self: *Self) void {
        for (self.cells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
            cell.reset();
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
                    if (cell.comb) |comb| {
                        self.allocator.free(comb);
                    }
                    cell.reset();
                }
            }
        }
    }

    /// Set cursor position
    pub fn setCursor(self: *Self, x: usize, y: usize) void {
        self.cursorX = @min(x, self.width - 1);
        self.cursorY = @min(y, self.height - 1);
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
                if (!cell.eql(self.previousCells[idx])) {
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
        // Free old combining chars in previousCells
        for (self.previousCells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
        }

        // Deep copy current cells to previous
        for (self.cells, 0..) |cell, idx| {
            var prevCell = cell;
            if (cell.comb) |comb| {
                prevCell.comb = self.allocator.dupe(u21, comb) catch null;
            }
            self.previousCells[idx] = prevCell;
        }
        self.dirty = false;
    }

    /// Force full redraw on next render
    pub fn markDirty(self: *Self) void {
        self.dirty = true;
    }

    /// Fill area with character and style
    pub fn fillRect(self: *Self, x: usize, y: usize, width: usize, height: usize, rune: u21, style: Style) !void {
        const end_x = @min(x + width, self.width);
        const end_y = @min(y + height, self.height);

        for (y..end_y) |row| {
            for (x..end_x) |col| {
                try self.setCell(col, row, rune, style);
            }
        }
    }

    /// Fill area with Cell struct
    pub fn fillRectCell(self: *Self, rect: Rectangle, cell: Cell) void {
        const intersected = rect.intersect(Rectangle{ .x = 0, .y = 0, .width = @intCast(self.width), .height = @intCast(self.height) });

        var y: usize = @intCast(intersected.y);
        while (y < @as(usize, @intCast(intersected.y)) + intersected.height) : (y += 1) {
            var x: usize = @intCast(intersected.x);
            while (x < @as(usize, @intCast(intersected.x)) + intersected.width) : (x += 1) {
                _ = self.setCellFull(x, y, cell);
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

    pub fn drawBox(self: *Self, x: usize, y: usize, width: usize, height: usize, style: BoxStyle, fg: Color, bg: Color, attrs: AttrMask) !void {
        if (width < 2 or height < 2) return;

        const box_style = Style{ .fg = fg, .bg = bg, .attrs = attrs };

        // Fill interior if requested
        if (style.fill) |fill_char| {
            try self.fillRect(x + 1, y + 1, width - 2, height - 2, fill_char, box_style);
        }

        // Draw corners
        try self.setCell(x, y, style.top_left, box_style);
        try self.setCell(x + width - 1, y, style.top_right, box_style);
        try self.setCell(x, y + height - 1, style.bottom_left, box_style);
        try self.setCell(x + width - 1, y + height - 1, style.bottom_right, box_style);

        // Draw horizontal borders
        for (1..width - 1) |col| {
            try self.setCell(x + col, y, style.horizontal, box_style);
            try self.setCell(x + col, y + height - 1, style.horizontal, box_style);
        }

        // Draw vertical borders
        for (1..height - 1) |row| {
            try self.setCell(x, y + row, style.vertical, box_style);
            try self.setCell(x + width - 1, y + row, style.vertical, box_style);
        }
    }

    /// Insert lines at position y, shifting existing content down
    pub fn insertLines(self: *Self, y: usize, count: usize, fill_cell: Cell) void {
        if (y >= self.height or count == 0) return;

        const available_lines = self.height - y;
        const actual_count = @min(count, available_lines);

        // Shift existing lines down
        var src_y = self.height - 1;
        while (src_y >= y + actual_count) : (src_y -= 1) {
            for (0..self.width) |x| {
                if (self.getCell(x, src_y)) |src_cell| {
                    const dst_y = src_y + actual_count;
                    if (dst_y < self.height) {
                        _ = self.setCellFull(x, dst_y, src_cell.*);
                    }
                }
            }
            if (src_y == 0) break;
        }

        // Fill inserted lines
        for (y..y + actual_count) |line_y| {
            for (0..self.width) |x| {
                _ = self.setCellFull(x, line_y, fill_cell);
            }
        }
    }

    /// Delete lines at position y, shifting remaining content up
    pub fn deleteLines(self: *Self, y: usize, count: usize, fill_cell: Cell) void {
        if (y >= self.height or count == 0) return;

        const available_lines = self.height - y;
        const actual_count = @min(count, available_lines);

        // Shift lines up
        for (y..self.height - actual_count) |dst_y| {
            const src_y = dst_y + actual_count;
            for (0..self.width) |x| {
                if (self.getCell(x, src_y)) |src_cell| {
                    _ = self.setCellFull(x, dst_y, src_cell.*);
                }
            }
        }

        // Fill remaining lines at bottom
        for (self.height - actual_count..self.height) |line_y| {
            for (0..self.width) |x| {
                _ = self.setCellFull(x, line_y, fill_cell);
            }
        }
    }

    /// Convert buffer to string representation
    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        for (0..self.height) |y| {
            if (y > 0) try result.appendSlice("\r\n");

            for (0..self.width) |x| {
                if (self.getCell(x, y)) |cell| {
                    if (!cell.isEmpty()) {
                        const cell_str = try cell.toString(allocator);
                        defer allocator.free(cell_str);
                        try result.appendSlice(cell_str);
                    } else {
                        try result.append(' ');
                    }
                }
            }

            // Trim trailing spaces
            while (result.items.len > 0 and result.items[result.items.len - 1] == ' ') {
                _ = result.pop();
            }
        }

        return result.toOwnedSlice();
    }
};

// Convenience functions for common colors
pub fn defaultColor() Color {
    return .default;
}
pub fn ansiColor(index: u8) Color {
    return .{ .ansi = index };
}
pub fn ansi256Color(index: u8) Color {
    return .{ .ansi256 = index };
}
pub fn rgbColor(r: u8, g: u8, b: u8) Color {
    return .{ .rgb = .{ .r = r, .g = g, .b = b } };
}

// Common attribute combinations
pub const bold = AttrMask{ .bold = true };
pub const italic = AttrMask{ .italic = true };
pub const reverse = AttrMask{ .reverse = true };
pub const strikethrough = AttrMask{ .strikethrough = true };

// Utility functions for creating cells
pub fn createCell(rune: u21, width: u8) Cell {
    return Cell{
        .rune = rune,
        .width = width,
    };
}

pub fn createStyledCell(rune: u21, width: u8, style: Style) Cell {
    return Cell{
        .rune = rune,
        .width = width,
        .style = style,
    };
}

pub fn createCellWithLink(rune: u21, width: u8, url: []const u8) Cell {
    return Cell{
        .rune = rune,
        .width = width,
        .link = Link{ .url = url },
    };
}

// Style builder helpers
pub fn boldStyle() Style {
    return Style{ .attrs = .{ .bold = true } };
}

pub fn colorStyle(fg: Color, bg: Color) Style {
    return Style{ .fg = fg, .bg = bg };
}

pub fn underlineStyle(style: UnderlineStyle, color: Color) Style {
    return Style{ .ulStyle = style, .ulColor = color };
}

// Tests
test "cell buffer creation and operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 80, 24);
    defer buf.deinit();

    try testing.expect(buf.width == 80);
    try testing.expect(buf.height == 24);

    // Test setting a cell
    try buf.setCell(0, 0, 'A', .{});
    const cell = buf.getCell(0, 0).?;
    try testing.expect(cell.rune == 'A');
}

test "wide character handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 10, 5);
    defer buf.deinit();

    // Test wide character (CJK ideograph)
    try buf.setCell(0, 0, 0x4E00, .{}); // 一

    const cell1 = buf.getCell(0, 0).?;
    const cell2 = buf.getCell(1, 0).?;

    try testing.expect(cell1.rune == 0x4E00);
    try testing.expect(cell1.width == 2);
    try testing.expect(cell2.isContinuation);
}

test "text writing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 20, 5);
    defer buf.deinit();

    const written = try buf.writeText(0, 0, "Hello, 世界!", .{});
    try testing.expect(written > 6); // Should be longer due to wide characters

    // Check first few characters
    try testing.expect(buf.getCell(0, 0).?.rune == 'H');
    try testing.expect(buf.getCell(1, 0).?.rune == 'e');
}

test "buffer resize" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 10, 5);
    defer buf.deinit();

    // Set some content
    try buf.setCell(5, 2, 'X', .{});

    // Resize larger
    try buf.resize(20, 10);
    try testing.expect(buf.width == 20);
    try testing.expect(buf.height == 10);

    // Content should be preserved
    try testing.expect(buf.getCell(5, 2).?.rune == 'X');
}

test "box drawing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = try CellBuffer.init(allocator, 10, 5);
    defer buf.deinit();

    try buf.drawBox(1, 1, 5, 3, .{}, .default, .default, .{});

    // Check corners
    try testing.expect(buf.getCell(1, 1).?.rune == '┌');
    try testing.expect(buf.getCell(5, 1).?.rune == '┐');
    try testing.expect(buf.getCell(1, 3).?.rune == '└');
    try testing.expect(buf.getCell(5, 3).?.rune == '┘');
}

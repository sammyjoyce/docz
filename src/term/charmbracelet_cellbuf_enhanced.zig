/// Enhanced cellbuf implementation inspired by charmbracelet/x cellbuf
/// Provides advanced terminal cell buffer functionality with Style, Link, and Buffer manipulation
/// Compatible with Zig 0.15.1 patterns
const std = @import("std");
const ansi = @import("ansi/mod.zig");
const wcwidth = @import("wcwidth.zig");

/// AttrMask represents text attributes that can be combined
pub const AttrMask = packed struct(u8) {
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    slow_blink: bool = false,
    rapid_blink: bool = false,
    reverse: bool = false,
    conceal: bool = false,
    strikethrough: bool = false,

    pub const RESET = AttrMask{};

    pub fn contains(self: AttrMask, attr: AttrMask) bool {
        const self_bits = @as(u8, @bitCast(self));
        const attr_bits = @as(u8, @bitCast(attr));
        return (self_bits & attr_bits) == attr_bits;
    }

    pub fn isEmpty(self: AttrMask) bool {
        return @as(u8, @bitCast(self)) == 0;
    }
};

/// Underline styles for text
pub const UnderlineStyle = enum(u8) {
    none = 0,
    single = 1,
    double = 2,
    curly = 3,
    dotted = 4,
    dashed = 5,
};

/// Color interface compatible with ANSI colors
pub const Color = union(enum) {
    default,
    basic: u4, // 0-15 basic colors
    indexed: u8, // 0-255 indexed colors
    rgb: struct { r: u8, g: u8, b: u8 },

    pub fn equal(self: Color, other: Color) bool {
        return switch (self) {
            .default => other == .default,
            .basic => |c| other == .basic and other.basic == c,
            .indexed => |c| other == .indexed and other.indexed == c,
            .rgb => |rgb| other == .rgb and
                other.rgb.r == rgb.r and
                other.rgb.g == rgb.g and
                other.rgb.b == rgb.b,
        };
    }

    pub fn toRGBA(self: Color) struct { r: u32, g: u32, b: u32, a: u32 } {
        return switch (self) {
            .default => .{ .r = 0, .g = 0, .b = 0, .a = 0xffff },
            .basic => |c| {
                // Convert basic color to RGB (simplified)
                const rgb = switch (c) {
                    0 => [3]u8{ 0x00, 0x00, 0x00 }, // Black
                    1 => [3]u8{ 0x80, 0x00, 0x00 }, // Red
                    2 => [3]u8{ 0x00, 0x80, 0x00 }, // Green
                    3 => [3]u8{ 0x80, 0x80, 0x00 }, // Yellow
                    4 => [3]u8{ 0x00, 0x00, 0x80 }, // Blue
                    5 => [3]u8{ 0x80, 0x00, 0x80 }, // Magenta
                    6 => [3]u8{ 0x00, 0x80, 0x80 }, // Cyan
                    7 => [3]u8{ 0xc0, 0xc0, 0xc0 }, // White
                    8 => [3]u8{ 0x80, 0x80, 0x80 }, // Bright Black
                    9 => [3]u8{ 0xff, 0x00, 0x00 }, // Bright Red
                    10 => [3]u8{ 0x00, 0xff, 0x00 }, // Bright Green
                    11 => [3]u8{ 0xff, 0xff, 0x00 }, // Bright Yellow
                    12 => [3]u8{ 0x00, 0x00, 0xff }, // Bright Blue
                    13 => [3]u8{ 0xff, 0x00, 0xff }, // Bright Magenta
                    14 => [3]u8{ 0x00, 0xff, 0xff }, // Bright Cyan
                    15 => [3]u8{ 0xff, 0xff, 0xff }, // Bright White
                };
                const r = @as(u32, rgb[0]) | (@as(u32, rgb[0]) << 8);
                const g = @as(u32, rgb[1]) | (@as(u32, rgb[1]) << 8);
                const b = @as(u32, rgb[2]) | (@as(u32, rgb[2]) << 8);
                return .{ .r = r, .g = g, .b = b, .a = 0xffff };
            },
            .indexed => |c| {
                // Simplified indexed color to RGB conversion
                const r = @as(u32, c) | (@as(u32, c) << 8);
                const g = @as(u32, c) | (@as(u32, c) << 8);
                const b = @as(u32, c) | (@as(u32, c) << 8);
                return .{ .r = r, .g = g, .b = b, .a = 0xffff };
            },
            .rgb => |rgb| {
                const r = @as(u32, rgb.r) | (@as(u32, rgb.r) << 8);
                const g = @as(u32, rgb.g) | (@as(u32, rgb.g) << 8);
                const b = @as(u32, rgb.b) | (@as(u32, rgb.b) << 8);
                return .{ .r = r, .g = g, .b = b, .a = 0xffff };
            },
        };
    }
};

/// Hyperlink support for terminal cells
pub const Link = struct {
    url: []const u8 = "",
    params: []const u8 = "",

    pub fn reset(self: *Link) void {
        self.url = "";
        self.params = "";
    }

    pub fn equal(self: Link, other: Link) bool {
        return std.mem.eql(u8, self.url, other.url) and
            std.mem.eql(u8, self.params, other.params);
    }

    pub fn empty(self: Link) bool {
        return self.url.len == 0 and self.params.len == 0;
    }
};

/// Cell style containing colors and attributes
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    ul: ?Color = null, // Underline color
    attrs: AttrMask = AttrMask.RESET,
    ul_style: UnderlineStyle = .none,

    pub fn reset(self: *Style) void {
        self.* = Style{};
    }

    pub fn equal(self: Style, other: Style) bool {
        return colorEqual(self.fg, other.fg) and
            colorEqual(self.bg, other.bg) and
            colorEqual(self.ul, other.ul) and
            @as(u8, @bitCast(self.attrs)) == @as(u8, @bitCast(other.attrs)) and
            self.ul_style == other.ul_style;
    }

    pub fn empty(self: Style) bool {
        return self.fg == null and
            self.bg == null and
            self.ul == null and
            self.attrs.isEmpty() and
            self.ul_style == .none;
    }

    pub fn clear(self: Style) bool {
        // Returns true if style only contains attributes that don't affect
        // the appearance of a space character
        return self.ul_style == .none and
            !self.attrs.reverse and
            !self.attrs.conceal and
            self.fg == null and
            self.bg == null and
            self.ul == null;
    }

    // Style builder methods
    pub fn bold(self: Style, v: bool) Style {
        var result = self;
        result.attrs.bold = v;
        return result;
    }

    pub fn faint(self: Style, v: bool) Style {
        var result = self;
        result.attrs.faint = v;
        return result;
    }

    pub fn italic(self: Style, v: bool) Style {
        var result = self;
        result.attrs.italic = v;
        return result;
    }

    pub fn underline(self: Style, ul_style: UnderlineStyle) Style {
        var result = self;
        result.ul_style = ul_style;
        return result;
    }

    pub fn foreground(self: Style, color: ?Color) Style {
        var result = self;
        result.fg = color;
        return result;
    }

    pub fn background(self: Style, color: ?Color) Style {
        var result = self;
        result.bg = color;
        return result;
    }
};

fn colorEqual(a: ?Color, b: ?Color) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return a.?.equal(b.?);
}

/// Enhanced terminal cell with style and link support
pub const Cell = struct {
    rune: u21 = 0,
    comb: []u21 = &.{}, // Combining characters
    cell_width: u8 = 0,
    style: Style = .{},
    link: Link = .{},

    const max_cell_width = 4;

    pub fn empty(self: Cell) bool {
        return self.cell_width == 0 and self.rune == 0 and self.comb.len == 0;
    }

    pub fn clear(self: Cell) bool {
        return self.rune == ' ' and
            self.comb.len == 0 and
            self.cell_width == 1 and
            self.style.clear() and
            self.link.empty();
    }

    pub fn reset(self: *Cell) void {
        self.rune = 0;
        self.comb = &.{};
        self.cell_width = 0;
        self.style.reset();
        self.link.reset();
    }

    pub fn blank(self: *Cell) *Cell {
        self.rune = ' ';
        self.comb = &.{};
        self.cell_width = 1;
        return self;
    }

    pub fn equal(self: Cell, other: Cell) bool {
        return self.cell_width == other.cell_width and
            self.rune == other.rune and
            std.mem.eql(u21, self.comb, other.comb) and
            self.style.equal(other.style) and
            self.link.equal(other.link);
    }

    pub fn clone(self: Cell) Cell {
        return self; // Safe to copy since we don't have allocated fields in this simple version
    }

    pub fn append(self: *Cell, runes: []const u21) void {
        for (runes, 0..) |r, i| {
            if (i == 0 and self.rune == 0) {
                self.rune = r;
                continue;
            }
            // In a full implementation, we'd resize comb slice
            // For now, we'll skip this to keep it simple
        }
    }

    pub fn toString(self: Cell, buf: []u8) []const u8 {
        if (self.rune == 0) return "";

        var len = std.unicode.utf8CodepointSequenceLength(self.rune) catch return "";
        if (buf.len < len) return "";

        _ = std.unicode.utf8Encode(self.rune, buf) catch return "";

        // Add combining characters (simplified)
        for (self.comb) |comb_rune| {
            const comb_len = std.unicode.utf8CodepointSequenceLength(comb_rune) catch continue;
            if (len + comb_len > buf.len) break;

            _ = std.unicode.utf8Encode(comb_rune, buf[len..]) catch continue;
            len += comb_len;
        }

        return buf[0..len];
    }
};

/// Predefined cells for convenience
pub const blank_cell = Cell{ .rune = ' ', .cell_width = 1 };
pub const empty_cell = Cell{};

/// Line represents a row of cells in the terminal buffer
pub const Line = struct {
    cells: []?*Cell,

    pub fn getWidth(self: Line) usize {
        return self.cells.len;
    }

    pub fn len(self: Line) usize {
        return self.cells.len;
    }

    pub fn at(self: Line, x: usize) ?*Cell {
        if (x >= self.cells.len) return null;

        if (self.cells[x]) |cell_ptr| {
            return cell_ptr;
        }

        // Return a blank cell for null entries
        return @constCast(&blank_cell);
    }

    pub fn set(self: Line, x: usize, cell_ptr: ?*Cell) bool {
        return self.setInternal(x, cell_ptr, true);
    }

    fn setInternal(self: Line, x: usize, new_cell: ?*Cell, clone: bool) bool {
        const line_width = self.getWidth();
        if (x >= line_width) return false;

        // Handle wide character overwrites
        const prev = self.at(x);
        if (prev != null and prev.?.cell_width > 1) {
            // Writing to the first wide cell - fill rest with blanks
            for (0..prev.?.cell_width) |j| {
                if (x + j < line_width) {
                    var blank = prev.?.clone();
                    _ = blank.blank();
                    self.cells[x + j] = &blank;
                }
            }
        } else if (prev != null and prev.?.cell_width == 0) {
            // Writing to wide cell placeholder - find the wide cell and blank it
            for (1..Cell.max_cell_width) |j| {
                if (x >= j) {
                    const wide = self.at(x - j);
                    if (wide != null and wide.?.cell_width > 1 and j < wide.?.cell_width) {
                        for (0..wide.?.cell_width) |k| {
                            if (x - j + k < line_width) {
                                var blank = wide.?.clone();
                                _ = blank.blank();
                                self.cells[x - j + k] = &blank;
                            }
                        }
                        break;
                    }
                }
            }
        }

        if (new_cell) |c| {
            // Check if cell is too wide for remaining space
            if (x + c.cell_width > line_width) {
                // Fill with blanks
                for (0..c.cell_width) |i| {
                    if (x + i < line_width) {
                        var blank = c.clone();
                        _ = blank.blank();
                        self.cells[x + i] = &blank;
                    }
                }
            } else {
                self.cells[x] = if (clone) &c.clone() else c;

                // Mark wide cells with empty placeholders
                if (c.cell_width > 1) {
                    for (1..c.cell_width) |j| {
                        if (x + j < line_width) {
                            self.cells[x + j] = @constCast(&empty_cell);
                        }
                    }
                }
            }
        } else {
            self.cells[x] = null;
        }

        return true;
    }

    pub fn toString(self: Line, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var buf: [16]u8 = undefined;
        for (self.cells) |cell_opt| {
            if (cell_opt) |cell_ptr| {
                if (cell_ptr.empty()) continue;
                const str = cell_ptr.toString(&buf);
                try result.appendSlice(str);
            } else {
                try result.append(' ');
            }
        }

        // Trim trailing spaces
        while (result.items.len > 0 and result.items[result.items.len - 1] == ' ') {
            _ = result.pop();
        }

        return try result.toOwnedSlice();
    }
};

/// Rectangle for buffer operations
pub const Rectangle = struct {
    min: struct { x: i32, y: i32 },
    max: struct { x: i32, y: i32 },
};

pub fn rect(x: i32, y: i32, w: i32, h: i32) Rectangle {
    return Rectangle{
        .min = .{ .x = x, .y = y },
        .max = .{ .x = x + w, .y = y + h },
    };
}

/// Enhanced terminal buffer with comprehensive cell manipulation
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    lines: []Line,

    pub fn init(allocator: std.mem.Allocator, buffer_width: usize, buffer_height: usize) !*Buffer {
        const buffer = try allocator.create(Buffer);
        buffer.allocator = allocator;
        buffer.lines = try allocator.alloc(Line, buffer_height);

        for (buffer.lines, 0..) |*buffer_line, i| {
            _ = i;
            buffer_line.cells = try allocator.alloc(?*Cell, buffer_width);
            @memset(buffer_line.cells, null);
        }

        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines) |buffer_line| {
            self.allocator.free(buffer_line.cells);
        }
        self.allocator.free(self.lines);
        self.allocator.destroy(self);
    }

    pub fn height(self: Buffer) usize {
        return self.lines.len;
    }

    pub fn getWidth(self: Buffer) usize {
        if (self.lines.len == 0) return 0;
        return self.lines[0].getWidth();
    }

    pub fn bounds(self: Buffer) Rectangle {
        return rect(0, 0, @intCast(self.getWidth()), @intCast(self.height()));
    }

    pub fn line(self: Buffer, y: usize) ?Line {
        if (y >= self.lines.len) return null;
        return self.lines[y];
    }

    pub fn getCell(self: Buffer, x: usize, y: usize) ?*Cell {
        if (y >= self.lines.len) return null;
        return self.lines[y].at(x);
    }

    pub fn setCell(self: *Buffer, x: usize, y: usize, c: ?*Cell) bool {
        if (y >= self.lines.len) return false;
        return self.lines[y].set(x, c);
    }

    pub fn resize(self: *Buffer, new_width: usize, new_height: usize) !void {
        // Resize lines array if needed
        if (new_height != self.lines.len) {
            if (new_height > self.lines.len) {
                // Growing - add new lines
                const old_lines = self.lines;
                self.lines = try self.allocator.realloc(old_lines, new_height);

                for (self.lines[old_lines.len..]) |*buffer_line| {
                    buffer_line.cells = try self.allocator.alloc(?*Cell, new_width);
                    @memset(buffer_line.cells, null);
                }
            } else {
                // Shrinking - free excess lines
                for (self.lines[new_height..]) |buffer_line| {
                    self.allocator.free(buffer_line.cells);
                }
                self.lines = try self.allocator.realloc(self.lines, new_height);
            }
        }

        // Resize width of existing lines
        const current_width = if (self.lines.len > 0) self.lines[0].getWidth() else 0;
        if (new_width != current_width) {
            for (self.lines) |*buffer_line| {
                if (new_width > current_width) {
                    buffer_line.cells = try self.allocator.realloc(buffer_line.cells, new_width);
                    @memset(buffer_line.cells[current_width..], null);
                } else {
                    buffer_line.cells = try self.allocator.realloc(buffer_line.cells, new_width);
                }
            }
        }
    }

    pub fn fill(self: *Buffer, c: ?*Cell) void {
        self.fillRect(c, self.bounds());
    }

    pub fn fillRect(self: *Buffer, c: ?*Cell, rectangle: Rectangle) void {
        const cell_width: usize = if (c) |cell_ptr| cell_ptr.cell_width else 1;

        const start_y = @max(0, rectangle.min.y);
        const end_y = @min(@as(i32, @intCast(self.height())), rectangle.max.y);
        const start_x = @max(0, rectangle.min.x);
        const end_x = @min(@as(i32, @intCast(self.getWidth())), rectangle.max.x);

        var y = start_y;
        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += @intCast(cell_width)) {
                _ = self.setCell(@intCast(x), @intCast(y), c);
            }
        }
    }

    pub fn clear(self: *Buffer) void {
        self.fill(null);
    }

    pub fn clearRect(self: *Buffer, rectangle: Rectangle) void {
        self.fillRect(null, rectangle);
    }
};

/// Create common cell types
pub fn newCell(rune: u21, comb: []const u21) *Cell {
    var new_cell = empty_cell;
    new_cell.rune = rune;
    new_cell.cell_width = wcwidth.codepointWidth(rune, .{});
    if (comb.len > 0) {
        // In a full implementation, we'd allocate space for combining characters
        // For now, we'll just store the first one
        if (comb.len > 0 and wcwidth.codepointWidth(comb[0], .{}) == 0) {
            // It's a combining character, add to the cell
            // Simplified: just calculate total width
            new_cell.cell_width = wcwidth.stringWidthGraphemes(&[_]u8{@intCast(rune)}, .{});
        }
    }
    return &new_cell;
}

pub fn newCellString(s: []const u8) *Cell {
    if (s.len == 0) return @constCast(&empty_cell);

    var new_cell = empty_cell;
    var i: usize = 0;
    var first = true;

    while (i < s.len) {
        const seq_len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (i + seq_len > s.len) break;

        const codepoint = std.unicode.utf8Decode(s[i .. i + seq_len]) catch {
            i += 1;
            continue;
        };

        if (first) {
            new_cell.rune = codepoint;
            new_cell.cell_width = wcwidth.codepointWidth(codepoint, .{});
            first = false;
        } else if (wcwidth.codepointWidth(codepoint, .{}) == 0) {
            // Combining character - would add to comb array in full implementation
            break;
        } else {
            // Non-combining character - stop here
            break;
        }

        i += seq_len;
    }

    return &new_cell;
}

// Tests
test "cell basic operations" {
    const testing = std.testing;

    var test_cell = empty_cell;
    try testing.expect(test_cell.empty());

    test_cell.rune = 'A';
    test_cell.cell_width = 1;
    try testing.expect(!test_cell.empty());
    try testing.expectEqual(@as(u21, 'A'), test_cell.rune);
    try testing.expectEqual(@as(u8, 1), test_cell.cell_width);
}

test "cell wide character" {
    const testing = std.testing;

    const wide_char = newCell(0x4E00, &.{}); // CJK ideograph
    try testing.expectEqual(@as(u8, 2), wide_char.cell_width);
}

test "buffer creation and basic operations" {
    const testing = std.testing;

    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit();

    try testing.expectEqual(@as(usize, 10), buffer.getWidth());
    try testing.expectEqual(@as(usize, 5), buffer.height());

    var test_cell = empty_cell;
    test_cell.rune = 'X';
    test_cell.cell_width = 1;

    try testing.expect(buffer.setCell(2, 1, &test_cell));

    const retrieved = buffer.getCell(2, 1);
    try testing.expect(retrieved != null);
    try testing.expectEqual(@as(u21, 'X'), retrieved.?.rune);
}

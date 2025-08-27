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

/// Enhanced terminal cell with style and link support
pub const Cell = struct {
    rune: u21 = 0,
    cell_width: u8 = 0,

    pub fn empty(self: Cell) bool {
        return self.cell_width == 0 and self.rune == 0;
    }

    pub fn reset(self: *Cell) void {
        self.rune = 0;
        self.cell_width = 0;
    }

    pub fn blank(self: *Cell) *Cell {
        self.rune = ' ';
        self.cell_width = 1;
        return self;
    }

    pub fn equal(self: Cell, other: Cell) bool {
        return self.cell_width == other.cell_width and
            self.rune == other.rune;
    }

    pub fn clone(self: Cell) Cell {
        return self;
    }
};

/// Predefined cells for convenience
pub const blank_cell = Cell{ .rune = ' ', .cell_width = 1 };
pub const empty_cell = Cell{};

/// Line represents a row of cells in the terminal buffer
pub const Line = struct {
    cells: []?Cell,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize) !Line {
        const cells = try allocator.alloc(?Cell, width);
        @memset(cells, null);
        return Line{
            .cells = cells,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Line) void {
        self.allocator.free(self.cells);
    }

    pub fn getWidth(self: Line) usize {
        return self.cells.len;
    }

    pub fn len(self: Line) usize {
        return self.cells.len;
    }

    pub fn at(self: Line, x: usize) ?Cell {
        if (x >= self.cells.len) return null;

        if (self.cells[x]) |cell| {
            return cell;
        }

        // Return a blank cell for null entries
        return blank_cell;
    }

    pub fn set(self: *Line, x: usize, new_cell: ?Cell) bool {
        if (x >= self.cells.len) return false;
        self.cells[x] = new_cell;
        return true;
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
    buffer_width: usize,
    buffer_height: usize,

    pub fn init(allocator: std.mem.Allocator, buffer_width: usize, buffer_height: usize) !*Buffer {
        const buffer = try allocator.create(Buffer);
        buffer.allocator = allocator;
        buffer.buffer_width = buffer_width;
        buffer.buffer_height = buffer_height;
        buffer.lines = try allocator.alloc(Line, buffer_height);

        for (buffer.lines, 0..) |*buffer_line, i| {
            _ = i;
            buffer_line.* = try Line.init(allocator, buffer_width);
        }

        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        for (self.lines) |*buffer_line| {
            buffer_line.deinit();
        }
        self.allocator.free(self.lines);
        self.allocator.destroy(self);
    }

    pub fn height(self: Buffer) usize {
        return self.buffer_height;
    }

    pub fn getWidth(self: Buffer) usize {
        return self.buffer_width;
    }

    pub fn bounds(self: Buffer) Rectangle {
        return rect(0, 0, @intCast(self.getWidth()), @intCast(self.height()));
    }

    pub fn line(self: Buffer, y: usize) ?*Line {
        if (y >= self.lines.len) return null;
        return &self.lines[y];
    }

    pub fn getCell(self: Buffer, x: usize, y: usize) ?Cell {
        if (y >= self.lines.len) return null;
        return self.lines[y].at(x);
    }

    pub fn setCell(self: *Buffer, x: usize, y: usize, new_cell: ?Cell) bool {
        if (y >= self.lines.len) return false;
        return self.lines[y].set(x, new_cell);
    }

    pub fn fill(self: *Buffer, new_cell: ?Cell) void {
        self.fillRect(new_cell, self.bounds());
    }

    pub fn fillRect(self: *Buffer, new_cell: ?Cell, rectangle: Rectangle) void {
        const start_y = @max(0, rectangle.min.y);
        const end_y = @min(@as(i32, @intCast(self.height())), rectangle.max.y);
        const start_x = @max(0, rectangle.min.x);
        const end_x = @min(@as(i32, @intCast(self.getWidth())), rectangle.max.x);

        var y = start_y;
        while (y < end_y) : (y += 1) {
            var x = start_x;
            while (x < end_x) : (x += 1) {
                _ = self.setCell(@intCast(x), @intCast(y), new_cell);
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
pub fn newCell(rune: u21) Cell {
    return Cell{
        .rune = rune,
        .cell_width = wcwidth.codepointWidth(rune, .{}),
    };
}

pub fn newCellString(s: []const u8) Cell {
    if (s.len == 0) return empty_cell;

    const seq_len = std.unicode.utf8ByteSequenceLength(s[0]) catch 1;
    if (s.len < seq_len) return empty_cell;

    const codepoint = std.unicode.utf8Decode(s[0..seq_len]) catch return empty_cell;

    return Cell{
        .rune = codepoint,
        .cell_width = wcwidth.codepointWidth(codepoint, .{}),
    };
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

    const wide_char = newCell(0x4E00); // CJK ideograph
    try testing.expectEqual(@as(u8, 2), wide_char.cell_width);
}

test "buffer creation and basic operations" {
    const testing = std.testing;

    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit();

    try testing.expectEqual(@as(usize, 10), buffer.getWidth());
    try testing.expectEqual(@as(usize, 5), buffer.height());

    const test_cell = Cell{ .rune = 'X', .cell_width = 1 };

    try testing.expect(buffer.setCell(2, 1, test_cell));

    const retrieved = buffer.getCell(2, 1);
    try testing.expect(retrieved != null);
    try testing.expectEqual(@as(u21, 'X'), retrieved.?.rune);
}

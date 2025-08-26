const std = @import("std");
const wcwidth = @import("wcwidth.zig");
const ansi = @import("ansi/ansi.zon");

/// Enhanced cell-based terminal display buffer with advanced features
/// Based on charmbracelet/x/cellbuf with Zig 0.15.1 compatibility
/// Supports combining characters, hyperlinks, and sophisticated styling

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
    slow_blink: bool = false,
    rapid_blink: bool = false,
    reverse: bool = false,
    conceal: bool = false,
    strikethrough: bool = false,
    
    pub fn isEmpty(self: AttrMask) bool {
        const as_int: u8 = @bitCast(self);
        return as_int == 0;
    }
    
    pub fn eql(self: AttrMask, other: AttrMask) bool {
        const self_int: u8 = @bitCast(self);
        const other_int: u8 = @bitCast(other);
        return self_int == other_int;
    }
};

/// Color representation that supports ANSI colors and RGB
pub const Color = union(enum) {
    default,
    ansi: u8, // 0-15 basic colors  
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
    pub fn toAnsiSeq(self: Color, allocator: std.mem.Allocator, is_bg: bool) ![]u8 {
        var seq = std.ArrayList(u8).init(allocator);
        defer seq.deinit();
        
        const prefix = if (is_bg) "48" else "38";
        
        switch (self) {
            .default => return allocator.dupe(u8, if (is_bg) "49" else "39"),
            .ansi => |c| {
                if (c < 8) {
                    try seq.writer().print("{s};5;{d}", .{prefix, c});
                } else {
                    try seq.writer().print("{s};5;{d}", .{prefix, c});
                }
            },
            .ansi256 => |c| {
                try seq.writer().print("{s};5;{d}", .{prefix, c});
            },
            .rgb => |rgb| {
                try seq.writer().print("{s};2;{d};{d};{d}", .{prefix, rgb.r, rgb.g, rgb.b});
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
        const url_match = blk: {
            if (self.url == null and other.url == null) break :blk true;
            if (self.url == null or other.url == null) break :blk false;
            break :blk std.mem.eql(u8, self.url.?, other.url.?);
        };
        
        const params_match = blk: {
            if (self.params == null and other.params == null) break :blk true;
            if (self.params == null or other.params == null) break :blk false;
            break :blk std.mem.eql(u8, self.params.?, other.params.?);
        };
        
        return url_match and params_match;
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
    ul_color: Color = .default, // Underline color
    attrs: AttrMask = .{},
    ul_style: UnderlineStyle = .none,
    
    pub fn eql(self: Style, other: Style) bool {
        return self.fg.eql(other.fg) and
            self.bg.eql(other.bg) and
            self.ul_color.eql(other.ul_color) and
            self.attrs.eql(other.attrs) and
            self.ul_style == other.ul_style;
    }
    
    pub fn isEmpty(self: Style) bool {
        return self.fg == .default and 
            self.bg == .default and
            self.ul_color == .default and
            self.attrs.isEmpty() and
            self.ul_style == .none;
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
        if (self.attrs.slow_blink) {
            if (!first) try seq.append(';');
            try seq.appendSlice("5");
            first = false;
        }
        if (self.attrs.rapid_blink) {
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
        if (self.ul_style != .none) {
            if (!first) try seq.append(';');
            try seq.appendSlice(self.ul_style.toAnsiCode());
            first = false;
        }
        
        // Colors
        if (self.fg != .default) {
            if (!first) try seq.append(';');
            const fg_seq = try self.fg.toAnsiSeq(allocator, false);
            defer allocator.free(fg_seq);
            try seq.appendSlice(fg_seq);
            first = false;
        }
        
        if (self.bg != .default) {
            if (!first) try seq.append(';');
            const bg_seq = try self.bg.toAnsiSeq(allocator, true);
            defer allocator.free(bg_seq);
            try seq.appendSlice(bg_seq);
            first = false;
        }
        
        if (self.ul_color != .default) {
            if (!first) try seq.append(';');
            try seq.appendSlice("58;2;");
            if (self.ul_color == .rgb) {
                try seq.writer().print("{d};{d};{d}", .{
                    self.ul_color.rgb.r, 
                    self.ul_color.rgb.g, 
                    self.ul_color.rgb.b
                });
            }
            first = false;
        }
        
        try seq.append('m');
        return seq.toOwnedSlice();
    }
};

/// Enhanced terminal cell with advanced features
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
        const comb_match = blk: {
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
            comb_match;
    }
    
    pub fn reset(self: *Cell) void {
        self.rune = 0;
        self.comb = null;
        self.width = 0;
        self.style.reset();
        self.link.reset();
    }
    
    pub fn makeBlank(self: *Cell) void {
        self.rune = ' ';
        self.comb = null;
        self.width = 1;
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
            const new_comb = try allocator.realloc(self.comb.?, self.comb.?.len + 1);
            new_comb[self.comb.?.len] = combining_char;
            self.comb = new_comb;
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

/// Enhanced terminal cell buffer
pub const EnhancedCellBuffer = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    cells: []Cell,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Self {
        const total = width * height;
        const cells = try allocator.alloc(Cell, total);
        
        // Initialize all cells as empty
        for (cells) |*cell| {
            cell.reset();
        }
        
        return Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .cells = cells,
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Free combining characters
        for (self.cells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
        }
        self.allocator.free(self.cells);
    }
    
    fn cellIndex(self: Self, x: u32, y: u32) ?usize {
        if (x >= self.width or y >= self.height) return null;
        return y * self.width + x;
    }
    
    pub fn getCell(self: Self, x: u32, y: u32) ?*Cell {
        const idx = self.cellIndex(x, y) orelse return null;
        return &self.cells[idx];
    }
    
    pub fn setCell(self: *Self, x: u32, y: u32, cell: Cell) bool {
        const idx = self.cellIndex(x, y) orelse return false;
        
        // Handle wide character cleanup
        self.cleanupWideCell(x, y);
        
        // Clone the cell data
        var new_cell = cell;
        if (cell.comb) |comb| {
            new_cell.comb = self.allocator.dupe(u21, comb) catch null;
        }
        
        self.cells[idx] = new_cell;
        
        // Mark subsequent cells for wide characters
        if (new_cell.isWide()) {
            var i: u32 = 1;
            while (i < new_cell.width and x + i < self.width) : (i += 1) {
                const wide_idx = self.cellIndex(x + i, y).?;
                self.cells[wide_idx].reset(); // Mark as continuation
            }
        }
        
        return true;
    }
    
    fn cleanupWideCell(self: *Self, x: u32, y: u32) void {
        const current_cell = self.getCell(x, y) orelse return;
        
        // If overwriting a wide character, blank out all its cells
        if (current_cell.isWide()) {
            var i: u32 = 0;
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
                        var i: u32 = 0;
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
    
    pub fn resize(self: *Self, new_width: u32, new_height: u32) !void {
        const new_total = new_width * new_height;
        const new_cells = try self.allocator.alloc(Cell, new_total);
        
        // Initialize new cells
        for (new_cells) |*cell| {
            cell.reset();
        }
        
        // Copy existing content
        const copy_height = @min(self.height, new_height);
        const copy_width = @min(self.width, new_width);
        
        for (0..copy_height) |y| {
            for (0..copy_width) |x| {
                const old_idx = y * self.width + x;
                const new_idx = y * new_width + x;
                new_cells[new_idx] = self.cells[old_idx];
                // Don't free old combining chars, they're moved
                self.cells[old_idx].comb = null;
            }
        }
        
        // Free old cells without touching moved combining chars
        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.width = new_width;
        self.height = new_height;
    }
    
    pub fn clear(self: *Self) void {
        for (self.cells) |*cell| {
            if (cell.comb) |comb| {
                self.allocator.free(comb);
            }
            cell.reset();
        }
    }
    
    pub fn fillRect(self: *Self, rect: Rectangle, cell: Cell) void {
        const intersected = rect.intersect(Rectangle{
            .x = 0, .y = 0,
            .width = self.width,
            .height = self.height
        });
        
        var y: u32 = @intCast(intersected.y);
        while (y < @as(u32, @intCast(intersected.y)) + intersected.height) : (y += 1) {
            var x: u32 = @intCast(intersected.x);
            while (x < @as(u32, @intCast(intersected.x)) + intersected.width) : (x += 1) {
                _ = self.setCell(x, y, cell);
            }
        }
    }
    
    /// Insert lines at position y, shifting existing content down
    pub fn insertLines(self: *Self, y: u32, count: u32, fill_cell: Cell) void {
        if (y >= self.height or count == 0) return;
        
        const available_lines = self.height - y;
        const actual_count = @min(count, available_lines);
        
        // Shift existing lines down
        var src_y = self.height - 1;
        while (src_y >= y + actual_count) : (src_y -= 1) {
            for (0..self.width) |x| {
                if (self.getCell(@intCast(x), src_y)) |src_cell| {
                    const dst_y = src_y + actual_count;
                    if (dst_y < self.height) {
                        _ = self.setCell(@intCast(x), @intCast(dst_y), src_cell.*);
                    }
                }
            }
            if (src_y == 0) break;
        }
        
        // Fill inserted lines
        for (y..y + actual_count) |line_y| {
            for (0..self.width) |x| {
                _ = self.setCell(@intCast(x), @intCast(line_y), fill_cell);
            }
        }
    }
    
    /// Delete lines at position y, shifting remaining content up
    pub fn deleteLines(self: *Self, y: u32, count: u32, fill_cell: Cell) void {
        if (y >= self.height or count == 0) return;
        
        const available_lines = self.height - y;
        const actual_count = @min(count, available_lines);
        
        // Shift lines up
        for (y..self.height - actual_count) |dst_y| {
            const src_y = dst_y + actual_count;
            for (0..self.width) |x| {
                if (self.getCell(@intCast(x), @intCast(src_y))) |src_cell| {
                    _ = self.setCell(@intCast(x), @intCast(dst_y), src_cell.*);
                }
            }
        }
        
        // Fill remaining lines at bottom
        for (self.height - actual_count..self.height) |line_y| {
            for (0..self.width) |x| {
                _ = self.setCell(@intCast(x), @intCast(line_y), fill_cell);
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
                if (self.getCell(@intCast(x), @intCast(y))) |cell| {
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

// Utility functions for creating cells

pub fn newCell(rune: u21, width: u8) Cell {
    return Cell{
        .rune = rune,
        .width = width,
    };
}

pub fn newStyledCell(rune: u21, width: u8, style: Style) Cell {
    return Cell{
        .rune = rune,
        .width = width,
        .style = style,
    };
}

pub fn newCellWithLink(rune: u21, width: u8, url: []const u8) Cell {
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
    return Style{ .ul_style = style, .ul_color = color };
}
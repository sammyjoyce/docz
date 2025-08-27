//! Tab character processing for terminal rendering
//! Provides proper tab expansion and width calculation

const std = @import("std");

/// Tab width configuration
pub const TabConfig = struct {
    /// Standard tab width (typically 4 or 8 spaces)
    tab_width: u8 = 8,
    /// Whether to use hard tabs or expand to spaces
    expand_tabs: bool = true,

    const Self = @This();

    /// Calculate the number of spaces needed to reach the next tab stop
    /// from the given column position
    pub fn spacesToNextTabStop(self: Self, column: usize) u8 {
        const tab_stop = self.tab_width;
        const spaces_to_next = tab_stop - (column % tab_stop);
        return @intCast(spaces_to_next);
    }

    /// Calculate the visual width a tab character would occupy at the given column
    pub fn tabWidthAtColumn(self: Self, column: usize) u8 {
        return self.spacesToNextTabStop(column);
    }

    /// Get the next tab stop position after the given column
    pub fn nextTabStop(self: Self, column: usize) usize {
        const spaces = self.spacesToNextTabStop(column);
        return column + spaces;
    }
};

/// Process text containing tabs, expanding them to proper width
pub fn expandTabs(
    allocator: std.mem.Allocator,
    text: []const u8,
    config: TabConfig,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var column: usize = 0;
    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        if (codepoint == '\t') {
            // Expand tab to spaces
            const spaces_needed = config.spacesToNextTabStop(column);
            try result.appendNTimes(' ', spaces_needed);
            column += spaces_needed;
        } else if (codepoint == '\n' or codepoint == '\r') {
            // Reset column on newline
            try result.append(@intCast(codepoint));
            column = 0;
        } else {
            // Regular character - append and update column
            const bytes = text[iter.i - iter.nextCodepointSlice().len .. iter.i];
            try result.appendSlice(bytes);
            column += 1; // Simplified - doesn't account for wide chars
        }
    }

    return result.toOwnedSlice();
}

/// Calculate the display width of text containing tabs
pub fn displayWidth(text: []const u8, config: TabConfig) usize {
    var width: usize = 0;
    var column: usize = 0;
    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        if (codepoint == '\t') {
            const tab_width = config.spacesToNextTabStop(column);
            width += tab_width;
            column += tab_width;
        } else if (codepoint == '\n' or codepoint == '\r') {
            // Reset column but don't add to width
            column = 0;
        } else {
            // Regular character
            width += 1; // Simplified - doesn't account for wide chars
            column += 1;
        }
    }

    return width;
}

/// Tab stop processor for terminal emulation
pub const TabStop = struct {
    stops: std.DynamicBitSet,
    width: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default tab stops every 8 columns
    pub fn init(allocator: std.mem.Allocator, width: usize) !Self {
        var stops = try std.DynamicBitSet.initFull(allocator, width);

        // Set standard tab stops every 8 columns
        stops.unsetAll();
        var i: usize = 0;
        while (i < width) : (i += 8) {
            stops.set(i);
        }

        return Self{
            .stops = stops,
            .width = width,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stops.deinit();
    }

    /// Find next tab stop at or after the given column
    pub fn nextTabStop(self: Self, column: usize) usize {
        var col = column + 1; // Start from next column
        while (col < self.width) : (col += 1) {
            if (self.stops.isSet(col)) return col;
        }
        return self.width - 1;
    }

    /// Calculate spaces to next tab stop
    pub fn spacesToNextTabStop(self: Self, column: usize) u8 {
        const next_stop = self.nextTabStop(column);
        const spaces = next_stop - column;
        return @intCast(@min(spaces, 255));
    }

    /// Set a tab stop at the given column
    pub fn setTabStop(self: *Self, column: usize) void {
        if (column < self.width) {
            self.stops.set(column);
        }
    }

    /// Clear a tab stop at the given column
    pub fn clearTabStop(self: *Self, column: usize) void {
        if (column < self.width) {
            self.stops.unset(column);
        }
    }

    /// Clear all tab stops
    pub fn clearAllTabStops(self: *Self) void {
        self.stops.unsetAll();
    }

    /// Reset to default tab stops (every 8 columns)
    pub fn resetToDefault(self: *Self) void {
        self.stops.unsetAll();
        var i: usize = 0;
        while (i < self.width) : (i += 8) {
            self.stops.set(i);
        }
    }
};

// Tests
test "TabConfig.spacesToNextTabStop" {
    const config = TabConfig{ .tab_width = 8 };

    try std.testing.expectEqual(@as(u8, 8), config.spacesToNextTabStop(0));
    try std.testing.expectEqual(@as(u8, 7), config.spacesToNextTabStop(1));
    try std.testing.expectEqual(@as(u8, 1), config.spacesToNextTabStop(7));
    try std.testing.expectEqual(@as(u8, 8), config.spacesToNextTabStop(8));
    try std.testing.expectEqual(@as(u8, 4), config.spacesToNextTabStop(12));
}

test "expandTabs basic" {
    const allocator = std.testing.allocator;
    const config = TabConfig{ .tab_width = 4 };

    const input = "hello\tworld";
    const expanded = try expandTabs(allocator, input, config);
    defer allocator.free(expanded);

    try std.testing.expectEqualStrings("hello   world", expanded);
}

test "expandTabs multiple tabs" {
    const allocator = std.testing.allocator;
    const config = TabConfig{ .tab_width = 4 };

    const input = "\t\tindented";
    const expanded = try expandTabs(allocator, input, config);
    defer allocator.free(expanded);

    try std.testing.expectEqualStrings("        indented", expanded);
}

test "TabStop" {
    const allocator = std.testing.allocator;
    var manager = try TabStop.init(allocator, 80);
    defer manager.deinit();

    // Default tab stops every 8 columns
    try std.testing.expectEqual(@as(usize, 8), manager.nextTabStop(0));
    try std.testing.expectEqual(@as(usize, 8), manager.nextTabStop(7));
    try std.testing.expectEqual(@as(usize, 16), manager.nextTabStop(8));

    // Custom tab stop
    manager.setTabStop(12);
    try std.testing.expectEqual(@as(usize, 12), manager.nextTabStop(10));
}

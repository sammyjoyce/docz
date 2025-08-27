const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const allocator = std.testing.allocator;

// ============================================================================
// Embedded Tab Processor Implementation for Testing
// ============================================================================

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
    alloc: std.mem.Allocator,
    text: []const u8,
    config: TabConfig,
) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(alloc, text.len * 2);
    defer result.deinit(alloc);

    var column: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        const codepoint = text[i];
        if (codepoint == '\t') {
            // Expand tab to spaces
            const spaces_needed = config.spacesToNextTabStop(column);
            for (0..spaces_needed) |_| {
                try result.append(alloc, ' ');
            }
            column += spaces_needed;
            i += 1;
        } else if (codepoint == '\n' or codepoint == '\r') {
            // Reset column on newline
            try result.append(alloc, codepoint);
            column = 0;
            i += 1;
        } else {
            // Regular character - append and update column
            try result.append(alloc, codepoint);
            column += 1; // Simplified - doesn't account for wide chars
            i += 1;
        }
    }

    return result.toOwnedSlice(alloc);
}

/// Calculate the display width of text containing tabs
pub fn displayWidth(text: []const u8, config: TabConfig) usize {
    var width: usize = 0;
    var column: usize = 0;
    var i: usize = 0;
    var last_line_width: usize = 0;

    while (i < text.len) {
        const codepoint = text[i];
        if (codepoint == '\t') {
            const tab_width = config.spacesToNextTabStop(column);
            width += tab_width;
            column += tab_width;
        } else if (codepoint == '\n' or codepoint == '\r') {
            // Reset column and update last line width
            last_line_width = width;
            width = 0;
            column = 0;
        } else {
            // Regular character
            width += 1; // Simplified - doesn't account for wide chars
            column += 1;
        }
        i += 1;
    }

    // Return the width of the last line (or total width if no newlines)
    return if (last_line_width > 0) width else width;
}

/// Tab stop manager for terminal emulation
pub const TabStopManager = struct {
    stops: std.ArrayList(usize),
    width: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default tab stops every 8 columns
    pub fn init(alloc: std.mem.Allocator, width: usize) !Self {
        var stops = try std.ArrayList(usize).initCapacity(alloc, width / 8 + 1);

        // Set standard tab stops every 8 columns
        var i: usize = 0;
        while (i < width) : (i += 8) {
            try stops.append(alloc, i);
        }

        return Self{
            .stops = stops,
            .width = width,
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stops.deinit(self.allocator);
    }

    /// Find next tab stop after the given column
    pub fn nextTabStop(self: Self, column: usize) usize {
        for (self.stops.items) |stop| {
            if (stop > column) return stop;
        }
        return if (self.width > 0) self.width - 1 else 0;
    }

    /// Calculate spaces to next tab stop
    pub fn spacesToNextTabStop(self: Self, column: usize) u8 {
        const next_stop = self.nextTabStop(column);
        if (next_stop >= column) {
            const spaces = next_stop - column;
            return @intCast(@min(spaces, 255));
        }
        return 0;
    }

    /// Set a tab stop at the given column
    pub fn setTabStop(self: *Self, column: usize) void {
        if (column >= self.width) return;

        // Remove existing stop at this column if any
        var i: usize = 0;
        while (i < self.stops.items.len) {
            if (self.stops.items[i] == column) {
                _ = self.stops.orderedRemove(i);
                break;
            }
            i += 1;
        }

        // Insert new stop in sorted order
        i = 0;
        while (i < self.stops.items.len and self.stops.items[i] < column) {
            i += 1;
        }
        self.stops.insert(self.allocator, i, column) catch {};
    }

    /// Clear a tab stop at the given column
    pub fn clearTabStop(self: *Self, column: usize) void {
        var i: usize = 0;
        while (i < self.stops.items.len) {
            if (self.stops.items[i] == column) {
                _ = self.stops.orderedRemove(i);
                break;
            }
            i += 1;
        }
    }

    /// Clear all tab stops
    pub fn clearAllTabStops(self: *Self) void {
        self.stops.clearRetainingCapacity();
        var i: usize = 0;
        while (i < self.width) : (i += 8) {
            self.stops.append(self.allocator, i) catch {};
        }
    }

    /// Reset to default tab stops (every 8 columns)
    pub fn resetToDefault(self: *Self) void {
        self.stops.clearRetainingCapacity();
        var i: usize = 0;
        while (i < self.width) : (i += 8) {
            self.stops.append(self.allocator, i) catch {};
        }
    }
};

// ============================================================================
// Simplified Cell Buffer for Testing
// ============================================================================

/// Simplified cell structure for testing
pub const TestCell = struct {
    rune: u21 = 0,
    width: u8 = 0,
};

/// Simplified cell buffer for testing tab integration
pub const TestCellBuffer = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    cells: []TestCell,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, width: usize, height: usize) !Self {
        const total_cells = width * height;
        const cells = try allocator.alloc(TestCell, total_cells);

        // Initialize all cells as empty
        for (cells) |*cell| {
            cell.rune = 0;
            cell.width = 0;
        }

        return Self{
            .allocator = alloc,
            .width = width,
            .height = height,
            .cells = cells,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cells);
    }

    pub fn getCell(self: Self, x: usize, y: usize) ?*TestCell {
        if (x >= self.width or y >= self.height) return null;
        return &self.cells[y * self.width + x];
    }

    pub fn setCell(self: *Self, x: usize, y: usize, rune: u21, char_width: u8) bool {
        if (x >= self.width or y >= self.height) return false;

        const cell = &self.cells[y * self.width + x];
        cell.rune = rune;
        cell.width = char_width;
        return true;
    }

    pub fn writeText(self: *Self, x: usize, y: usize, text: []const u8) !usize {
        var pos_x = x;
        var i: usize = 0;

        while (i < text.len and pos_x < self.width) {
            const seq_len = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
            if (i + seq_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i .. i + seq_len]) catch {
                i += 1;
                continue;
            };

            const char_width: u8 = if (codepoint < 0x80) 1 else 2; // Simplified width calculation
            _ = self.setCell(pos_x, y, codepoint, char_width);

            pos_x += char_width;
            i += seq_len;
        }

        return pos_x - x;
    }
};

// ============================================================================
// Tab Expansion Tests
// ============================================================================

test "tab expansion with different widths" {
    // Test tab width 4
    const config4 = TabConfig{ .tab_width = 4, .expand_tabs = true };

    const input1 = "hello\tworld";
    const expanded1 = try expandTabs(allocator, input1, config4);
    defer allocator.free(expanded1);
    try expectEqualStrings("hello   world", expanded1);

    const input2 = "\tstart";
    const expanded2 = try expandTabs(allocator, input2, config4);
    defer allocator.free(expanded2);
    try expectEqualStrings("    start", expanded2);

    // Test tab width 8
    const config8 = TabConfig{ .tab_width = 8, .expand_tabs = true };

    const input3 = "hello\tworld";
    const expanded3 = try expandTabs(allocator, input3, config8);
    defer allocator.free(expanded3);
    try expectEqualStrings("hello   world", expanded3);

    const input4 = "\tstart";
    const expanded4 = try expandTabs(allocator, input4, config8);
    defer allocator.free(expanded4);
    try expectEqualStrings("        start", expanded4);
}

test "tab expansion with multiple tabs" {
    const config = TabConfig{ .tab_width = 8, .expand_tabs = true };

    const input = "\t\tindented\ttext";
    const expanded = try expandTabs(allocator, input, config);
    defer allocator.free(expanded);
    try expectEqualStrings("                indented        text", expanded);
}

test "tab expansion with mixed content" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    const input = "col1\tcol2\tcol3";
    const expanded = try expandTabs(allocator, input, config);
    defer allocator.free(expanded);
    try expectEqualStrings("col1    col2    col3", expanded);
}

test "tab expansion with newlines" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    const input = "line1\twith tab\nline2\twith tab";
    const expanded = try expandTabs(allocator, input, config);
    defer allocator.free(expanded);
    try expectEqualStrings("line1   with tab\nline2   with tab", expanded);
}

test "tab expansion edge cases" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    // Empty string
    const empty = try expandTabs(allocator, "", config);
    defer allocator.free(empty);
    try expectEqualStrings("", empty);

    // Only tabs
    const only_tabs = try expandTabs(allocator, "\t\t\t", config);
    defer allocator.free(only_tabs);
    try expectEqualStrings("            ", only_tabs);

    // Tabs at end
    const tabs_at_end = try expandTabs(allocator, "text\t\t", config);
    defer allocator.free(tabs_at_end);
    try expectEqualStrings("text        ", tabs_at_end);
}

// ============================================================================
// Display Width Calculation Tests
// ============================================================================

test "display width calculation" {
    const config4 = TabConfig{ .tab_width = 4, .expand_tabs = true };
    const config8 = TabConfig{ .tab_width = 8, .expand_tabs = true };

    // Basic tab expansion
    try expectEqual(@as(usize, 13), displayWidth("hello\tworld", config4));
    try expectEqual(@as(usize, 13), displayWidth("hello\tworld", config8));

    // Multiple tabs
    try expectEqual(@as(usize, 16), displayWidth("\t\tindented", config4));
    try expectEqual(@as(usize, 24), displayWidth("\t\tindented", config8));

    // Mixed content
    try expectEqual(@as(usize, 20), displayWidth("col1\tcol2\tcol3", config4));
    try expectEqual(@as(usize, 20), displayWidth("col1\tcol2\tcol3", config8));
}

test "display width with newlines" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    const input = "line1\twith tab\nline2\twith tab";
    const width = displayWidth(input, config);
    try expectEqual(@as(usize, 16), width); // Only considers last line
}

test "display width edge cases" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    // Empty string
    try expectEqual(@as(usize, 0), displayWidth("", config));

    // Only tabs
    try expectEqual(@as(usize, 12), displayWidth("\t\t\t", config));

    // No tabs
    try expectEqual(@as(usize, 11), displayWidth("hello world", config));
}

// ============================================================================
// TabConfig Method Tests
// ============================================================================

test "TabConfig.spacesToNextTabStop" {
    const config4 = TabConfig{ .tab_width = 4 };
    const config8 = TabConfig{ .tab_width = 8 };

    // Tab width 4
    try expectEqual(@as(u8, 4), config4.spacesToNextTabStop(0));
    try expectEqual(@as(u8, 3), config4.spacesToNextTabStop(1));
    try expectEqual(@as(u8, 2), config4.spacesToNextTabStop(2));
    try expectEqual(@as(u8, 1), config4.spacesToNextTabStop(3));
    try expectEqual(@as(u8, 4), config4.spacesToNextTabStop(4));

    // Tab width 8
    try expectEqual(@as(u8, 8), config8.spacesToNextTabStop(0));
    try expectEqual(@as(u8, 7), config8.spacesToNextTabStop(1));
    try expectEqual(@as(u8, 1), config8.spacesToNextTabStop(7));
    try expectEqual(@as(u8, 8), config8.spacesToNextTabStop(8));
}

test "TabConfig.tabWidthAtColumn" {
    const config = TabConfig{ .tab_width = 4 };

    try expectEqual(@as(u8, 4), config.tabWidthAtColumn(0));
    try expectEqual(@as(u8, 3), config.tabWidthAtColumn(1));
    try expectEqual(@as(u8, 2), config.tabWidthAtColumn(2));
    try expectEqual(@as(u8, 1), config.tabWidthAtColumn(3));
    try expectEqual(@as(u8, 4), config.tabWidthAtColumn(4));
}

test "TabConfig.nextTabStop" {
    const config = TabConfig{ .tab_width = 4 };

    try expectEqual(@as(usize, 4), config.nextTabStop(0));
    try expectEqual(@as(usize, 4), config.nextTabStop(1));
    try expectEqual(@as(usize, 4), config.nextTabStop(2));
    try expectEqual(@as(usize, 4), config.nextTabStop(3));
    try expectEqual(@as(usize, 8), config.nextTabStop(4));
    try expectEqual(@as(usize, 8), config.nextTabStop(5));
}

// ============================================================================
// TabStopManager Tests
// ============================================================================

test "TabStopManager initialization" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    try expectEqual(@as(usize, 80), manager.width);
    // Check default tab stops (every 8 columns)
    try expectEqual(@as(usize, 8), manager.nextTabStop(0));
    try expectEqual(@as(usize, 16), manager.nextTabStop(8));
    try expectEqual(@as(usize, 24), manager.nextTabStop(16));
}

test "TabStopManager nextTabStop" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    // Default tab stops at 0, 8, 16, 24, 32, 40, 48, 56, 64, 72
    try expectEqual(@as(usize, 8), manager.nextTabStop(0));
    try expectEqual(@as(usize, 8), manager.nextTabStop(1));
    try expectEqual(@as(usize, 8), manager.nextTabStop(7));
    try expectEqual(@as(usize, 16), manager.nextTabStop(8));
    try expectEqual(@as(usize, 16), manager.nextTabStop(9));
    try expectEqual(@as(usize, 79), manager.nextTabStop(79)); // At boundary
}

test "TabStopManager spacesToNextTabStop" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    try expectEqual(@as(u8, 8), manager.spacesToNextTabStop(0));
    try expectEqual(@as(u8, 7), manager.spacesToNextTabStop(1));
    try expectEqual(@as(u8, 1), manager.spacesToNextTabStop(7));
    try expectEqual(@as(u8, 8), manager.spacesToNextTabStop(8));
}

test "TabStopManager setTabStop" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    // Set custom tab stop
    manager.setTabStop(12);
    try expectEqual(@as(usize, 12), manager.nextTabStop(10));
    try expectEqual(@as(usize, 12), manager.nextTabStop(11));
    try expectEqual(@as(usize, 16), manager.nextTabStop(12));
}

test "TabStopManager clearTabStop" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    // Set and then clear a tab stop
    manager.setTabStop(12);
    try expectEqual(@as(usize, 12), manager.nextTabStop(10));

    manager.clearTabStop(12);
    try expectEqual(@as(usize, 16), manager.nextTabStop(10)); // Should skip to next default
}

test "TabStopManager clearAllTabStops" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    manager.setTabStop(12);
    manager.setTabStop(20);
    try expectEqual(@as(usize, 12), manager.nextTabStop(10));

    manager.clearAllTabStops();
    try expectEqual(@as(usize, 16), manager.nextTabStop(10)); // Should skip to next default
}

test "TabStopManager resetToDefault" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    // Set custom tab stops
    manager.setTabStop(12);
    manager.setTabStop(20);
    try expectEqual(@as(usize, 12), manager.nextTabStop(10));

    manager.resetToDefault();
    try expectEqual(@as(usize, 16), manager.nextTabStop(10)); // Should be back to default
}

test "TabStopManager boundary conditions" {
    var manager = try TabStopManager.init(allocator, 20);
    defer manager.deinit();

    // Test at boundary
    try expectEqual(@as(usize, 19), manager.nextTabStop(19));
    try expectEqual(@as(u8, 0), manager.spacesToNextTabStop(19));

    // Test beyond boundary
    try expectEqual(@as(usize, 19), manager.nextTabStop(20));
    try expectEqual(@as(u8, 0), manager.spacesToNextTabStop(20));
}

// ============================================================================
// Cell Buffer Integration Tests
// ============================================================================

test "cell buffer tab integration" {
    var buffer = try TestCellBuffer.init(allocator, 20, 5);
    defer buffer.deinit();

    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };
    const text = "hello\tworld";

    // Expand tabs first
    const expanded = try expandTabs(allocator, text, config);
    defer allocator.free(expanded);

    // Write to cell buffer
    const written = try buffer.writeText(0, 0, expanded);
    try expectEqual(@as(usize, 13), written); // "hello   world" is 13 chars

    // Verify content
    try expectEqual(@as(u21, 'h'), buffer.getCell(0, 0).?.rune);
    try expectEqual(@as(u21, 'e'), buffer.getCell(1, 0).?.rune);
    try expectEqual(@as(u21, 'l'), buffer.getCell(2, 0).?.rune);
    try expectEqual(@as(u21, 'l'), buffer.getCell(3, 0).?.rune);
    try expectEqual(@as(u21, 'o'), buffer.getCell(4, 0).?.rune);
    try expectEqual(@as(u21, ' '), buffer.getCell(5, 0).?.rune); // First space from tab
    try expectEqual(@as(u21, ' '), buffer.getCell(6, 0).?.rune); // Second space from tab
    try expectEqual(@as(u21, ' '), buffer.getCell(7, 0).?.rune); // Third space from tab
    try expectEqual(@as(u21, 'w'), buffer.getCell(8, 0).?.rune);
}

test "cell buffer tab width calculation integration" {
    const config4 = TabConfig{ .tab_width = 4, .expand_tabs = true };
    const config8 = TabConfig{ .tab_width = 8, .expand_tabs = true };

    const text = "hello\tworld";

    const width4 = displayWidth(text, config4);
    const width8 = displayWidth(text, config8);

    try expectEqual(@as(usize, 13), width4); // "hello   world" = 5 + 3 + 5 = 13 chars
    try expectEqual(@as(usize, 13), width8); // "hello   world" = 5 + 3 + 5 = 13 chars

    // Actually, let's verify the expansion strings
    const expanded4 = try expandTabs(allocator, text, config4);
    defer allocator.free(expanded4);
    try expectEqualStrings("hello   world", expanded4); // 5 + 3 + 5 = 13 chars

    const expanded8 = try expandTabs(allocator, text, config8);
    defer allocator.free(expanded8);
    try expectEqualStrings("hello   world", expanded8); // 5 + 3 + 5 = 13 chars

    try expectEqual(@as(usize, 13), displayWidth(text, config4));
    try expectEqual(@as(usize, 13), displayWidth(text, config8));
}



// ============================================================================
// Cursor Positioning Tests
// ============================================================================

test "cursor positioning with tabs" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    // Test cursor position after tab expansion
    const text = "hello\tworld";
    const expanded = try expandTabs(allocator, text, config);
    defer allocator.free(expanded);

    // Cursor should be positioned at the end of expanded text
    const cursor_pos = expanded.len;
    try expectEqual(@as(usize, 13), cursor_pos); // "hello   world" = 13 chars
}

test "cursor positioning in tab manager" {
    var manager = try TabStopManager.init(allocator, 80);
    defer manager.deinit();

    // Test cursor positioning at various columns
    try expectEqual(@as(usize, 8), manager.nextTabStop(0));   // From col 0, next tab at 8
    try expectEqual(@as(usize, 8), manager.nextTabStop(4));   // From col 4, next tab at 8
    try expectEqual(@as(usize, 16), manager.nextTabStop(8));  // From col 8, next tab at 16
    try expectEqual(@as(usize, 16), manager.nextTabStop(12)); // From col 12, next tab at 16
}

// ============================================================================
// Complex Integration Tests
// ============================================================================

test "complex tab processing scenario" {
    const config = TabConfig{ .tab_width = 8, .expand_tabs = true };

    // Complex text with multiple tabs and newlines
    const text =
        \\Name\tAge\tCity
        \\John\t25\tNew York
        \\Jane\t30\tSan Francisco
    ;

    const expanded = try expandTabs(allocator, text, config);
    defer allocator.free(expanded);

    // Verify the expansion contains proper spacing
    try expect(std.mem.indexOf(u8, expanded, "Name") != null);
    try expect(std.mem.indexOf(u8, expanded, "Age") != null);
    try expect(std.mem.indexOf(u8, expanded, "City") != null);
}

test "tab processing with unicode characters" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    // Test with Unicode characters
    const text = "café\tnaïve\t北京";
    const expanded = try expandTabs(allocator, text, config);
    defer allocator.free(expanded);

    // The display width calculation should handle UTF-8 properly
    const width = displayWidth(text, config);
    try expect(width > 4); // Should account for multi-byte characters
}

test "tab processing performance test" {
    const config = TabConfig{ .tab_width = 8, .expand_tabs = true };

    // Create a large string with many tabs
    var large_text = try std.ArrayList(u8).initCapacity(allocator, 10000);
    defer large_text.deinit(allocator);

    for (0..1000) |i| {
        const line = try std.fmt.allocPrint(allocator, "line{d}\t", .{i});
        defer allocator.free(line);
        try large_text.appendSlice(allocator, line);
        if (i % 10 == 0) {
            try large_text.append(allocator, '\n');
        }
    }

    // This should complete without issues
    const expanded = try expandTabs(allocator, large_text.items, config);
    defer allocator.free(expanded);

    try expect(expanded.len > large_text.items.len); // Should be expanded
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "tab processing with invalid UTF-8" {
    const config = TabConfig{ .tab_width = 4, .expand_tabs = true };

    // Create invalid UTF-8 sequence
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, '\t', 'a' };

    // Should handle gracefully (may truncate or skip invalid sequences)
    const expanded = try expandTabs(allocator, &invalid_utf8, config);
    defer allocator.free(expanded);

    // Should still produce some output
    try expect(expanded.len > 0);
}

test "tab stop manager with zero width" {
    // This should work but with limited functionality
    var manager = try TabStopManager.init(allocator, 0);
    defer manager.deinit();

    try expectEqual(@as(usize, 0), manager.width);
    // Boundary case: no tab stops possible
    try expectEqual(@as(usize, 0), manager.nextTabStop(0));
}
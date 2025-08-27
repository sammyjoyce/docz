const std = @import("std");
const Renderer = @import("../Renderer.zig").Renderer;
const RenderTier = Renderer.RenderTier;
const QualityTiers = @import("../quality_tiers.zig").QualityTiers;
const TableConfig = @import("../quality_tiers.zig").TableConfig;
const term_shared = @import("term_shared");
const Color = term_shared.ansi.color.Color;
const cacheKey = @import("../Renderer.zig").cacheKey;

/// Table data structure
pub const Table = struct {
    headers: []const []const u8,
    rows: []const []const []const u8,
    title: ?[]const u8 = null,
    column_widths: ?[]const u16 = null,
    column_alignments: ?[]const Alignment = null,
    sortable: bool = false,
    sort_column: ?u16 = null,
    sort_ascending: bool = true,
    row_colors: ?[]const ?Color = null,
    header_color: ?Color = null,
    border_color: ?Color = null,

    pub const Alignment = enum {
        left,
        center,
        right,

        pub fn apply(self: Alignment, text: []const u8, width: u16, buffer: []u8) []const u8 {
            const text_len = std.unicode.utf8CountCodepoints(text) catch text.len;
            if (text_len >= width) {
                return text;
            }

            const padding = width - @as(u16, @intCast(text_len));

            return switch (self) {
                .left => std.fmt.bufPrint(buffer, "{s}{s}", .{ text, " " ** padding }) catch text,
                .right => std.fmt.bufPrint(buffer, "{s}{s}", .{ " " ** padding, text }) catch text,
                .center => {
                    const left_pad = padding / 2;
                    const right_pad = padding - left_pad;
                    return std.fmt.bufPrint(buffer, "{s}{s}{s}", .{ " " ** left_pad, text, " " ** right_pad }) catch text;
                },
            };
        }
    };

    pub fn validate(self: Table) !void {
        if (self.headers.len == 0) {
            return error.EmptyHeaders;
        }

        for (self.rows) |row| {
            if (row.len != self.headers.len) {
                return error.InconsistentColumnCount;
            }
        }

        if (self.column_widths) |widths| {
            if (widths.len != self.headers.len) {
                return error.InconsistentColumnWidths;
            }
        }

        if (self.column_alignments) |alignments| {
            if (alignments.len != self.headers.len) {
                return error.InconsistentColumnAlignments;
            }
        }
    }

    /// Calculate optimal column widths based on content
    pub fn calculateColumnWidths(self: Table, allocator: std.mem.Allocator) ![]u16 {
        const widths = try allocator.alloc(u16, self.headers.len);

        // Start with header widths
        for (self.headers, 0..) |header, i| {
            widths[i] = @intCast(std.unicode.utf8CountCodepoints(header) catch header.len);
        }

        // Check all rows
        for (self.rows) |row| {
            for (row, 0..) |cell, i| {
                const cell_width = @as(u16, @intCast(std.unicode.utf8CountCodepoints(cell) catch cell.len));
                widths[i] = @max(widths[i], cell_width);
            }
        }

        return widths;
    }
};

/// Render table using unified renderer
pub fn renderTable(renderer: *@import("../Renderer.zig").Renderer, table: Table) !void {
    try table.validate();

    const key = cacheKey("table_{d}_{d}_{?s}", .{ table.headers.len, table.rows.len, table.title });

    if (renderer.cache.get(key, renderer.render_tier)) |cached| {
        try renderer.terminal.writeText(cached);
        return;
    }

    var output = std.ArrayList(u8).init(renderer.allocator);
    defer output.deinit();

    switch (renderer.render_tier) {
        .ultra => try renderHigh(renderer, table, &output),
        .rich => try renderMedium(renderer, table, &output),
        .standard => try renderLow(renderer, table, &output),
        .minimal => try renderBasic(renderer, table, &output),
    }

    const content = try output.toOwnedSlice();
    defer renderer.allocator.free(content);

    try renderer.cache.put(key, content, renderer.render_tier);
    try renderer.terminal.writeText(content);
}

/// High quality rendering with box drawing and colors
fn renderHigh(renderer: *Renderer, table: Table, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Table.high;
    const writer = output.writer();

    // Calculate column widths
    const widths = table.column_widths orelse try table.calculateColumnWidths(renderer.allocator);
    defer if (table.column_widths == null) renderer.allocator.free(widths);

    const border_chars = config.border_style.getChars();

    // Title
    if (table.title) |title| {
        if (config.supports_color and table.header_color) |color| {
            try setTableColor(renderer, color, writer);
        }
        try writer.print("{s}\n", .{title});
        if (config.supports_color and table.header_color) |_| {
            try writer.writeAll("\x1b[0m");
        }
    }

    // Top border
    if (config.use_box_drawing) {
        try renderHorizontalBorder(writer, widths, border_chars, .top);
        try writer.writeAll("\n");
    }

    // Header row
    try renderDataRow(renderer, config, table.headers, widths, table.column_alignments, table.header_color, writer, true);

    // Header separator
    if (config.use_box_drawing) {
        try renderHorizontalBorder(writer, widths, border_chars, .middle);
        try writer.writeAll("\n");
    }

    // Data rows
    for (table.rows, 0..) |row, row_index| {
        const row_color = if (table.row_colors) |colors| colors[row_index] else null;
        const alternating_color = if (config.use_alternating_rows and row_index % 2 == 1)
            Color.ansi(.bright_black)
        else
            null;
        const final_color = row_color orelse alternating_color;

        try renderDataRow(renderer, config, row, widths, table.column_alignments, final_color, writer, false);
    }

    // Bottom border
    if (config.use_box_drawing) {
        try renderHorizontalBorder(writer, widths, border_chars, .bottom);
        try writer.writeAll("\n");
    }
}

/// Compatible rendering with ASCII characters
fn renderCompatible(renderer: *Renderer, table: Table, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Table.compatible;
    const writer = output.writer();

    // Calculate column widths
    const widths = table.column_widths orelse try table.calculateColumnWidths(renderer.allocator);
    defer if (table.column_widths == null) renderer.allocator.free(widths);

    const border_chars = config.border_style.getChars();

    // Title
    if (table.title) |title| {
        try writer.print("{s}\n", .{title});
    }

    // Top border
    try renderHorizontalBorder(writer, widths, border_chars, .top);
    try writer.writeAll("\n");

    // Header row
    try renderDataRow(renderer, config, table.headers, widths, table.column_alignments, null, writer, true);

    // Header separator
    try renderHorizontalBorder(writer, widths, border_chars, .middle);
    try writer.writeAll("\n");

    // Data rows
    for (table.rows) |row| {
        try renderDataRow(renderer, config, row, widths, table.column_alignments, null, writer, false);
    }

    // Bottom border
    try renderHorizontalBorder(writer, widths, border_chars, .bottom);
    try writer.writeAll("\n");
}

/// Medium quality rendering with double-line borders
fn renderMedium(renderer: *Renderer, table: Table, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Table.medium;
    const writer = output.writer();

    // Calculate column widths
    const widths = table.column_widths orelse try table.calculateColumnWidths(renderer.allocator);
    defer if (table.column_widths == null) renderer.allocator.free(widths);

    const border_chars = config.border_style.getChars();

    // Title
    if (table.title) |title| {
        if (config.supports_color and table.header_color) |color| {
            try setTableColor(renderer, color, writer);
        }
        try writer.print("{s}\n", .{title});
        if (config.supports_color and table.header_color) |_| {
            try writer.writeAll("\x1b[0m");
        }
    }

    // Top border
    try renderHorizontalBorder(writer, widths, border_chars, .top);
    try writer.writeAll("\n");

    // Header row
    try renderDataRow(renderer, config, table.headers, widths, table.column_alignments, table.header_color, writer, true);

    // Header separator
    try renderHorizontalBorder(writer, widths, border_chars, .middle);
    try writer.writeAll("\n");

    // Data rows
    for (table.rows, 0..) |row, row_index| {
        const row_color = if (table.row_colors) |colors| colors[row_index] else null;
        const alternating_color = if (config.use_alternating_rows and row_index % 2 == 1)
            Color.ansi(.bright_black)
        else
            null;
        const final_color = row_color orelse alternating_color;

        try renderDataRow(renderer, config, row, widths, table.column_alignments, final_color, writer, false);
    }

    // Bottom border
    try renderHorizontalBorder(writer, widths, border_chars, .bottom);
    try writer.writeAll("\n");
}

/// Low quality rendering with ASCII borders
fn renderLow(renderer: *Renderer, table: Table, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Table.low;
    const writer = output.writer();

    // Calculate column widths
    const widths = table.column_widths orelse try table.calculateColumnWidths(renderer.allocator);
    defer if (table.column_widths == null) renderer.allocator.free(widths);

    const border_chars = config.border_style.getChars();

    // Title
    if (table.title) |title| {
        try writer.print("{s}\n", .{title});
    }

    // Top border
    try renderHorizontalBorder(writer, widths, border_chars, .top);
    try writer.writeAll("\n");

    // Header row
    try renderDataRow(renderer, config, table.headers, widths, table.column_alignments, null, writer, true);

    // Header separator
    try renderHorizontalBorder(writer, widths, border_chars, .middle);
    try writer.writeAll("\n");

    // Data rows
    for (table.rows) |row| {
        try renderDataRow(renderer, config, row, widths, table.column_alignments, null, writer, false);
    }

    // Bottom border
    try renderHorizontalBorder(writer, widths, border_chars, .bottom);
    try writer.writeAll("\n");
}

/// Basic rendering with plain text
fn renderBasic(_: *Renderer, table: Table, output: *std.ArrayList(u8)) !void {
    const writer = output.writer();

    // Title
    if (table.title) |title| {
        try writer.print("{s}\n\n", .{title});
    }

    // Headers
    for (table.headers, 0..) |header, i| {
        if (i > 0) try writer.writeAll("\t");
        try writer.writeAll(header);
    }
    try writer.writeAll("\n");

    // Separator line
    for (table.headers, 0..) |_, i| {
        if (i > 0) try writer.writeAll("\t");
        try writer.writeAll("---");
    }
    try writer.writeAll("\n");

    // Data rows
    for (table.rows) |row| {
        for (row, 0..) |cell, i| {
            if (i > 0) try writer.writeAll("\t");
            try writer.writeAll(cell);
        }
        try writer.writeAll("\n");
    }
}

/// Render a horizontal border
fn renderHorizontalBorder(writer: anytype, widths: []const u16, chars: TableConfig.BorderChars, position: enum { top, middle, bottom }) !void {
    const left_char = switch (position) {
        .top => chars.top_left,
        .middle => chars.left_tee,
        .bottom => chars.bottom_left,
    };
    const right_char = switch (position) {
        .top => chars.top_right,
        .middle => chars.right_tee,
        .bottom => chars.bottom_right,
    };
    const junction_char = switch (position) {
        .top => chars.top_tee,
        .middle => chars.cross,
        .bottom => chars.bottom_tee,
    };

    try writer.writeAll(left_char);

    for (widths, 0..) |width, i| {
        if (i > 0) {
            try writer.writeAll(junction_char);
        }

        const padding = width + 2; // +2 for spaces around content
        for (0..padding) |_| {
            try writer.writeAll(chars.horizontal);
        }
    }

    try writer.writeAll(right_char);
}

/// Render a data row
fn renderDataRow(
    renderer: *Renderer,
    config: TableConfig,
    row: []const []const u8,
    widths: []const u16,
    alignments: ?[]const Table.Alignment,
    row_color: ?Color,
    writer: anytype,
    is_header: bool,
) !void {
    const border_chars = config.border_style.getChars();

    // Set row color
    if (config.supports_color and row_color) |color| {
        try setTableColor(renderer, color, writer);
    }

    if (config.use_box_drawing) {
        try writer.writeAll(border_chars.vertical);
    }

    for (row, 0..) |cell, i| {
        if (i > 0 and config.use_box_drawing) {
            try writer.writeAll(border_chars.vertical);
        }

        if (config.use_cell_padding) {
            try writer.writeAll(" ");
        }

        // Apply alignment
        var buffer: [256]u8 = undefined;
        const alignment = if (alignments) |aligns| aligns[i] else .left;
        const aligned_text = alignment.apply(cell, widths[i], &buffer);

        try writer.writeAll(aligned_text);

        if (config.use_cell_padding) {
            try writer.writeAll(" ");
        }
    }

    if (config.use_box_drawing) {
        try writer.writeAll(border_chars.vertical);
    }

    // Add sorting indicator for headers
    if (is_header and config.supports_sorting_indicators) {
        // This would be implemented based on table.sort_column and sort_ascending
        // For now, just placeholder
    }

    // Reset color
    if (config.supports_color and row_color) |_| {
        try writer.writeAll("\x1b[0m");
    }

    try writer.writeAll("\n");
}

/// Set table color based on renderer capabilities
fn setTableColor(renderer: *Renderer, color: Color, writer: anytype) !void {
    try renderer.setRendererColor(color, writer);
}

/// Convert RGB to nearest 256-color palette index
fn rgbToPalette256(rgb: struct { r: u8, g: u8, b: u8 }) u8 {
    const r6 = rgb.r * 5 / 255;
    const g6 = rgb.g * 5 / 255;
    const b6 = rgb.b * 5 / 255;
    return 16 + (r6 * 36) + (g6 * 6) + b6;
}

// Tests
test "table rendering" {
    const testing = std.testing;

    var renderer = try Renderer.initWithTier(testing.allocator, .rich);
    defer renderer.deinit();

    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "Alice", "25", "New York" };
    const row2 = [_][]const u8{ "Bob", "30", "London" };
    const rows = [_][]const []const u8{ &row1, &row2 };

    const table = Table{
        .headers = &headers,
        .rows = &rows,
        .title = "Sample Table",
    };

    try renderTable(renderer, table);

    // Test validation
    const invalid_table = Table{
        .headers = &[_][]const u8{},
        .rows = &[_][]const []const u8{},
    };
    try testing.expectError(error.EmptyHeaders, invalid_table.validate());
}

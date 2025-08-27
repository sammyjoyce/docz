//! Table widget with clipboard integration
//! Provides interactive table display with copy/paste functionality,
//! selection support, and keyboard navigation leveraging OSC 52 clipboard capabilities

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const events_mod = @import("../../core/events.zig");
const tui_mod = @import("../../mod.zig");
const terminal_mod = tui_mod.term.common;

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;
const MouseEvent = events_mod.MouseEvent;
const KeyEvent = events_mod.KeyEvent;

pub const TableError = error{
    InvalidSelection,
    ClipboardUnavailable,
    InvalidData,
} || std.mem.Allocator.Error;

pub const Table = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    headers: [][]const u8,
    rows: [][]Cell,
    config: Config,
    state: TableState,
    bounds: Bounds = Bounds.init(0, 0, 0, 0),

    // Clipboard integration
    clipboard_enabled: bool,
    last_copied_data: ?[]u8 = null,
    // Cached renderer pointer to enable clipboard ops during input events
    renderer: ?*Renderer = null,

    pub const Config = struct {
        title: ?[]const u8 = null,
        showHeaders: bool = true,
        showRowNumbers: bool = false,
        show_grid_lines: bool = true,
        allow_selection: bool = true,
        clipboard_enabled: bool = true,
        scrollable: bool = true,
        sortable: bool = false,
        resizable_columns: bool = false,
        max_cell_width: u32 = 20,
        min_cell_width: u32 = 3,
        pagination_size: u32 = 50,
    };

    pub const Cell = struct {
        value: []const u8,
        style: ?CellStyle = null,
        copyable: bool = true,
        editable: bool = false,

        pub const CellStyle = struct {
            foregroundColor: ?tui_mod.term.common.Color = null,
            backgroundColor: ?tui_mod.term.common.Color = null,
            bold: bool = false,
            italic: bool = false,
            alignment: Alignment = .left,

            pub const Alignment = enum {
                left,
                center,
                right,
            };
        };
    };

    pub const TableState = struct {
        cursor: Point = Point.init(0, 0),
        selection: ?Selection = null,
        scrollOffset: Point = Point.init(0, 0),
        column_widths: []u32,
        focused: bool = false,
        editing_cell: ?Point = null,
        sort_column: ?u32 = null,
        sort_direction: SortDirection = .ascending,

        pub const SortDirection = enum {
            ascending,
            descending,
        };
    };

    pub const Selection = struct {
        start: Point,
        end: Point,
        mode: SelectionMode,

        pub const SelectionMode = enum {
            cell, // Single cell
            row, // Entire row(s)
            column, // Entire column(s)
            range, // Rectangular range
        };

        pub fn normalize(self: Selection) Selection {
            return Selection{
                .start = Point.init(@min(self.start.x, self.end.x), @min(self.start.y, self.end.y)),
                .end = Point.init(@max(self.start.x, self.end.x), @max(self.start.y, self.end.y)),
                .mode = self.mode,
            };
        }

        pub fn contains(self: Selection, point: Point) bool {
            const norm = self.normalize();
            return point.x >= norm.start.x and point.x <= norm.end.x and
                point.y >= norm.start.y and point.y <= norm.end.y;
        }

        pub fn getCellCount(self: Selection) u32 {
            const norm = self.normalize();
            return (norm.end.x - norm.start.x + 1) * (norm.end.y - norm.start.y + 1);
        }
    };

    pub const InputEvent = union(enum) {
        key: KeyEvent,
        mouse: MouseEvent,
        paste: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, headers: [][]const u8, config: Config) !Self {
        // Calculate initial column widths based on headers
        const column_widths = try allocator.alloc(u32, headers.len);
        for (headers, column_widths) |header, *width| {
            width.* = @max(@min(@as(u32, @intCast(header.len)), config.max_cell_width), config.min_cell_width);
        }

        return Self{
            .allocator = allocator,
            .headers = headers,
            .rows = &[_][]Cell{},
            .config = config,
            .state = TableState{
                .column_widths = column_widths,
            },
            .clipboard_enabled = config.clipboard_enabled,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.state.column_widths);
        if (self.last_copied_data) |data| {
            self.allocator.free(data);
        }
        // Note: We don't own headers and rows data, so we don't free them
    }

    pub fn setData(self: *Self, rows: [][]Cell) !void {
        self.rows = rows;

        // Recalculate column widths if needed
        if (self.config.resizable_columns) {
            try self.recalculateColumnWidths();
        }

        // Reset cursor if it's out of bounds
        if (self.state.cursor.y >= self.rows.len) {
            self.state.cursor.y = if (self.rows.len > 0) @intCast(self.rows.len - 1) else 0;
        }
    }

    fn recalculateColumnWidths(self: *Self) !void {
        for (self.state.column_widths, 0..) |*width, col_idx| {
            var max_width = self.headers[col_idx].len;

            for (self.rows) |row| {
                if (col_idx < row.len) {
                    max_width = @max(max_width, row[col_idx].value.len);
                }
            }

            width.* = @max(@min(@as(u32, @intCast(max_width)), self.config.max_cell_width), self.config.min_cell_width);
        }
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: Render) !void {
        self.bounds = ctx.bounds;
        self.renderer = renderer;

        var current_y: u32 = ctx.bounds.y;

        // Render title if present
        if (self.config.title) |title| {
            try renderer.moveCursor(ctx.bounds.x, current_y);
            try renderer.setStyle(.{ .bold = true });
            try renderer.writeText("{s}", .{title});
            try renderer.resetStyle();
            current_y += 2;
        }

        // Render headers
        if (self.config.showHeaders) {
            try self.renderHeaders(renderer, ctx.bounds.x, current_y);
            current_y += if (self.config.show_grid_lines) 2 else 1;
        }

        // Render data rows
        const available_height = ctx.bounds.height - (current_y - ctx.bounds.y);
        try self.renderRows(renderer, ctx.bounds.x, current_y, available_height);

        // Render status line
        try self.renderStatusLine(renderer, ctx);
    }

    fn renderHeaders(self: *Self, renderer: *Renderer, x: u32, y: u32) !void {
        try renderer.moveCursor(x, y);

        // Row number column
        if (self.config.show_row_numbers) {
            try renderer.writeText("{s:>4} ", .{""});
        }

        // Headers
        for (self.headers, self.state.column_widths, 0..) |header, width, col_idx| {
            // Highlight sorted column
            if (self.state.sort_column == col_idx and self.config.sortable) {
                try renderer.setStyle(.{ .bold = true });
                const sort_arrow = if (self.state.sort_direction == .ascending) "↑" else "↓";
                try renderer.writeText("{s:<{}}{}|", .{ header, width - 1, sort_arrow });
                try renderer.resetStyle();
            } else {
                try renderer.setStyle(.{ .bold = true });
                try renderer.writeText("{s:<{}}|", .{ header, width });
                try renderer.resetStyle();
            }
        }

        // Grid line under headers
        if (self.config.show_grid_lines) {
            try renderer.moveCursor(x, y + 1);

            if (self.config.showRowNumbers) {
                try renderer.writeText("-----");
            }

            for (self.state.column_widths) |width| {
                for (0..width) |_| {
                    try renderer.writeText("-");
                }
                try renderer.writeText("+");
            }
        }
    }

    fn renderRows(self: *Self, renderer: *Renderer, x: u32, start_y: u32, available_height: u32) !void {
        const visible_rows = @min(available_height, @as(u32, @intCast(self.rows.len - self.state.scrollOffset.y)));

        for (0..visible_rows) |row_idx| {
            const actual_row_idx = row_idx + @as(usize, @intCast(self.state.scrollOffset.y));
            if (actual_row_idx >= self.rows.len) break;

            const row = self.rows[actual_row_idx];
            const y = start_y + @as(u32, @intCast(row_idx));

            try self.renderRow(renderer, x, y, row, @intCast(actual_row_idx));
        }
    }

    fn renderRow(self: *Self, renderer: *Renderer, x: u32, y: u32, row: []Cell, row_idx: u32) !void {
        try renderer.moveCursor(x, y);

        // Row number
        if (self.config.showRowNumbers) {
            const style = if (self.isRowSelected(row_idx))
                renderer_mod.Style{ .backgroundColor = .yellow }
            else
                renderer_mod.Style{};

            try renderer.setStyleEx(style);
            try renderer.writeText("{d:>4} ", .{row_idx + 1});
            try renderer.resetStyle();
        }

        // Cells
        for (row, self.state.column_widths, 0..) |cell, width, col_idx| {
            const cell_pos = Point.init(@intCast(col_idx), row_idx);
            const is_selected = self.isCellSelected(cell_pos);
            const is_cursor = self.state.cursor.x == col_idx and self.state.cursor.y == row_idx;

            // Apply cell styling
            var style = renderer_mod.Style{};

            if (cell.style) |cell_style| {
                if (cell_style.foregroundColor) |fg| style.foregroundColor = fg;
                if (cell_style.backgroundColor) |bg| style.backgroundColor = bg;
                style.bold = cell_style.bold;
                style.italic = cell_style.italic;
            }

            // Selection and cursor highlighting
            if (is_selected) {
                style.backgroundColor = terminal_mod.Color.blue;
                style.foregroundColor = terminal_mod.Color.white;
            }

            if (is_cursor and self.state.focused) {
                style.backgroundColor = terminal_mod.Color.cyan;
                style.foregroundColor = terminal_mod.Color.black;
            }

            try renderer.setStyleEx(style);

            // Render cell content with proper alignment
            const content = if (cell.value.len > width)
                cell.value[0..@min(cell.value.len, width - 3)] ++ "..."
            else
                cell.value;

            switch ((cell.style orelse Cell.CellStyle{}).alignment) {
                .left => try renderer.writeText("{s:<{}}|", .{ content, width }),
                .center => try renderer.writeText("{s:^{}}|", .{ content, width }),
                .right => try renderer.writeText("{s:>{}}|", .{ content, width }),
            }

            try renderer.resetStyle();
        }
    }

    fn renderStatusLine(self: *Self, renderer: *Renderer, ctx: Render) !void {
        const status_y = ctx.bounds.y + ctx.bounds.height - 1;
        try renderer.moveCursor(ctx.bounds.x, status_y);

        // Clear the line
        for (0..ctx.bounds.width) |_| {
            try renderer.writeText(" ");
        }

        try renderer.moveCursor(ctx.bounds.x, status_y);

        // Selection info
        if (self.state.selection) |sel| {
            const cell_count = sel.getCellCount();
            try renderer.writeText("Selected: {} cells", .{cell_count});
        } else {
            try renderer.writeText("Row {}/{}, Col {}/{}", .{
                self.state.cursor.y + 1,
                self.rows.len,
                self.state.cursor.x + 1,
                self.headers.len,
            });
        }

        // Keyboard shortcuts
        if (self.clipboard_enabled) {
            try renderer.writeText(" | Ctrl+C: Copy, Ctrl+V: Paste");
        }
        try renderer.writeText(" | Arrow Keys: Navigate");
    }

    pub fn handleInput(self: *Self, event: InputEvent) !void {
        switch (event) {
            .key => |key| try self.handleKeyInput(key),
            .mouse => |mouse| try self.handleMouseInput(mouse),
            .paste => |data| try self.handlePaste(data),
        }
    }

    fn handleKeyInput(self: *Self, key: KeyEvent) !void {
        // Navigation
        if (key.ctrl) {
            switch (key.char) {
                'c', 'C' => if (self.clipboard_enabled) try self.copySelection(),
                'v', 'V' => if (self.clipboard_enabled) try self.requestPaste(),
                'a', 'A' => try self.selectAll(),
                else => {},
            }
        } else {
            switch (key.char) {
                // Arrow key navigation would be handled here
                // For now, using WASD as a demo
                'w', 'W' => self.moveCursor(0, -1),
                's', 'S' => self.moveCursor(0, 1),
                'a', 'A' => self.moveCursor(-1, 0),
                'd', 'D' => self.moveCursor(1, 0),
                ' ' => try self.toggleSelection(),
                '\r' => try self.startCellEdit(),
                27 => self.clearSelection(), // Escape
                else => {},
            }
        }
    }

    fn handleMouseInput(self: *Self, mouse: MouseEvent) !void {
        // Convert mouse coordinates to cell coordinates
        const cell_pos = self.mouseToCellPos(Point.init(mouse.x, mouse.y));

        switch (mouse.button) {
            .left => {
                if (mouse.pressed) {
                    self.setCursor(cell_pos);
                    if (mouse.ctrl) {
                        try self.toggleCellSelection(cell_pos);
                    } else {
                        try self.startSelection(cell_pos);
                    }
                }
            },
            .right => {
                // Context menu could be implemented here
                try self.copyCell(cell_pos);
            },
            else => {},
        }
    }

    fn handlePaste(self: *Self, data: []const u8) !void {
        // Parse clipboard data and insert into table
        // This is a simplified implementation
        if (self.state.editing_cell) |pos| {
            // Replace cell content
            if (pos.y < self.rows.len and pos.x < self.rows[pos.y].len) {
                // Note: In a real implementation, you'd need to manage memory for cell values
                _ = data; // For now, just acknowledge the paste
                try self.endCellEdit();
            }
        }
    }

    // Navigation and cursor management
    fn moveCursor(self: *Self, dx: i32, dy: i32) void {
        const new_x = @as(i32, @intCast(self.state.cursor.x)) + dx;
        const new_y = @as(i32, @intCast(self.state.cursor.y)) + dy;

        if (new_x >= 0 and new_x < self.headers.len) {
            self.state.cursor.x = @intCast(new_x);
        }

        if (new_y >= 0 and new_y < self.rows.len) {
            self.state.cursor.y = @intCast(new_y);
        }

        // Auto-scroll if needed
        self.ensureCursorVisible();
    }

    fn setCursor(self: *Self, pos: Point) void {
        if (pos.x < self.headers.len and pos.y < self.rows.len) {
            self.state.cursor = pos;
            self.ensureCursorVisible();
        }
    }

    fn ensureCursorVisible(self: *Self) void {
        // Implement scrolling logic to keep cursor visible
        const visible_height = self.bounds.height - 3; // Account for headers and status

        if (self.state.cursor.y < self.state.scrollOffset.y) {
            self.state.scrollOffset.y = self.state.cursor.y;
        } else if (self.state.cursor.y >= self.state.scrollOffset.y + visible_height) {
            self.state.scrollOffset.y = self.state.cursor.y - visible_height + 1;
        }
    }

    // Selection management
    fn startSelection(self: *Self, pos: Point) !void {
        self.state.selection = Selection{
            .start = pos,
            .end = pos,
            .mode = .cell,
        };
    }

    fn toggleSelection(self: *Self) !void {
        if (self.state.selection) |_| {
            self.clearSelection();
        } else {
            try self.startSelection(self.state.cursor);
        }
    }

    fn toggleCellSelection(self: *Self, pos: Point) !void {
        if (self.state.selection) |sel| {
            if (sel.contains(pos)) {
                self.clearSelection();
            } else {
                self.state.selection = Selection{
                    .start = sel.start,
                    .end = pos,
                    .mode = .range,
                };
            }
        } else {
            try self.startSelection(pos);
        }
    }

    fn selectAll(self: *Self) !void {
        if (self.rows.len > 0) {
            self.state.selection = Selection{
                .start = Point.init(0, 0),
                .end = Point.init(@intCast(self.headers.len - 1), @intCast(self.rows.len - 1)),
                .mode = .range,
            };
        }
    }

    fn clearSelection(self: *Self) void {
        self.state.selection = null;
    }

    fn isCellSelected(self: *Self, pos: Point) bool {
        if (self.state.selection) |sel| {
            return sel.contains(pos);
        }
        return false;
    }

    fn isRowSelected(self: *Self, row_idx: u32) bool {
        if (self.state.selection) |sel| {
            return sel.start.y <= row_idx and sel.end.y >= row_idx;
        }
        return false;
    }

    // Clipboard operations
    fn copySelection(self: *Self) !void {
        if (!self.clipboard_enabled) return;

        const selection = self.state.selection orelse Selection{
            .start = self.state.cursor,
            .end = self.state.cursor,
            .mode = .cell,
        };

        const data = try self.getSelectionData(selection);
        defer self.allocator.free(data);

        // Use renderer clipboard API if available
        if (self.renderer) |r| {
            r.copyToClipboard(data) catch {};
        }

        // Cache the data locally
        if (self.last_copied_data) |old_data| {
            self.allocator.free(old_data);
        }
        self.last_copied_data = try self.allocator.dupe(u8, data);

        // TODO: Show notification that data was copied
    }

    fn copyCell(self: *Self, pos: Point) !void {
        if (!self.clipboard_enabled or pos.y >= self.rows.len or pos.x >= self.rows[pos.y].len) return;

        const cell = self.rows[pos.y][pos.x];
        if (!cell.copyable) return;

        if (self.renderer) |r| {
            r.copyToClipboard(cell.value) catch {};
        }

        if (self.last_copied_data) |old_data| {
            self.allocator.free(old_data);
        }
        self.last_copied_data = try self.allocator.dupe(u8, cell.value);
    }

    fn requestPaste(self: *Self) !void {
        if (!self.clipboard_enabled) return;
        // Renderer does not support reading clipboard; rely on paste input events.
        // As a small helper, fall back to local last_copied_data cache if present.
        if (self.last_copied_data) |cached| {
            try self.handlePaste(cached);
        }
    }

    fn getSelectionData(self: *Self, selection: Selection) ![]u8 {
        const norm_sel = selection.normalize();
        var data = std.ArrayList(u8).init(self.allocator);
        defer data.deinit();

        const writer = data.writer();

        for (@as(u32, @intCast(norm_sel.start.y))..@as(u32, @intCast(norm_sel.end.y + 1))) |row_idx| {
            if (row_idx >= self.rows.len) break;

            const row = self.rows[row_idx];
            var first_cell = true;

            for (@as(u32, @intCast(norm_sel.start.x))..@as(u32, @intCast(norm_sel.end.x + 1))) |col_idx| {
                if (col_idx >= row.len) break;

                if (!first_cell) {
                    try writer.writeAll("\t"); // Tab-separated values
                }

                const cell = row[col_idx];
                if (cell.copyable) {
                    try writer.writeAll(cell.value);
                }

                first_cell = false;
            }

            if (row_idx < norm_sel.end.y) {
                try writer.writeAll("\n");
            }
        }

        return data.toOwnedSlice();
    }

    // Cell editing
    fn startCellEdit(self: *Self) !void {
        if (self.state.cursor.y < self.rows.len and
            self.state.cursor.x < self.rows[self.state.cursor.y].len and
            self.rows[self.state.cursor.y][self.state.cursor.x].editable)
        {
            self.state.editing_cell = self.state.cursor;
        }
    }

    fn endCellEdit(self: *Self) !void {
        self.state.editing_cell = null;
    }

    // Utility functions
    fn mouseToCellPos(self: *Self, mouse_pos: Point) Point {
        // Convert mouse coordinates to cell coordinates
        // This is a simplified implementation
        var x: u32 = 0;
        var current_x = self.bounds.x;

        // Account for row numbers column
        if (self.config.showRowNumbers) {
            current_x += 5;
        }

        // Find column
        for (self.state.column_widths, 0..) |width, col_idx| {
            if (mouse_pos.x >= current_x and mouse_pos.x < current_x + width) {
                x = @intCast(col_idx);
                break;
            }
            current_x += width + 1; // +1 for separator
        }

        // Find row (accounting for headers and scroll offset)
        var y = self.state.scrollOffset.y;
        const header_offset: u32 = if (self.config.showHeaders) 2 else 0;
        if (mouse_pos.y >= self.bounds.y + header_offset) {
            y += mouse_pos.y - self.bounds.y - header_offset;
        }

        return Point.init(x, y);
    }

    pub fn focus(self: *Self) void {
        self.state.focused = true;
    }

    pub fn blur(self: *Self) void {
        self.state.focused = false;
        self.clearSelection();
    }
};

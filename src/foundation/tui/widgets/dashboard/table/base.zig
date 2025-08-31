//! DataTable base types and core data structures
//!
//! This module contains the fundamental types and interfaces used by the table system.

const std = @import("std");
const bounds_mod = @import("../../../core/bounds.zig");
const term = @import("../../../../term.zig");

pub const Point = bounds_mod.Point;
pub const Bounds = bounds_mod.Bounds;

pub const TableError = error{
    InvalidSelection,
    ClipboardUnavailable,
    InvalidData,
} || std.mem.Allocator.Error;

/// Table configuration options
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

/// Individual table cell with styling and behavior options
pub const Cell = struct {
    value: []const u8,
    style: ?CellStyle = null,
    copyable: bool = true,
    editable: bool = false,

    pub const CellStyle = struct {
        foregroundColor: ?term.Color = null,
        backgroundColor: ?term.Color = null,
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

/// Table state management
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

        pub fn toggle(self: SortDirection) SortDirection {
            return switch (self) {
                .ascending => .descending,
                .descending => .ascending,
            };
        }
    };

    /// Initialize table state with calculated column widths
    pub fn init(allocator: std.mem.Allocator, headers: [][]const u8, config: Config) !TableState {
        const column_widths = try allocator.alloc(u32, headers.len);
        for (headers, column_widths) |header, *width| {
            width.* = @max(@min(@as(u32, @intCast(header.len)), config.max_cell_width), config.min_cell_width);
        }

        return TableState{
            .column_widths = column_widths,
        };
    }

    pub fn deinit(self: *TableState, allocator: std.mem.Allocator) void {
        allocator.free(self.column_widths);
    }

    /// Check if cursor is within table bounds
    pub fn isCursorValid(self: TableState, row_count: usize, col_count: usize) bool {
        return self.cursor.x >= 0 and
            self.cursor.y >= 0 and
            self.cursor.x < col_count and
            self.cursor.y < row_count;
    }

    /// Move cursor with bounds checking
    pub fn moveCursor(self: *TableState, dx: i32, dy: i32, row_count: usize, col_count: usize) void {
        const new_x = @max(0, @min(@as(i32, @intCast(col_count)) - 1, self.cursor.x + dx));
        const new_y = @max(0, @min(@as(i32, @intCast(row_count)) - 1, self.cursor.y + dy));

        self.cursor = Point.init(new_x, new_y);
    }

    /// Calculate column widths based on content
    pub fn recalculateColumnWidths(self: *TableState, headers: [][]const u8, rows: [][]Cell, config: Config) void {
        for (self.column_widths, 0..) |*width, col_idx| {
            var max_width = if (col_idx < headers.len) headers[col_idx].len else 0;

            for (rows) |row| {
                if (col_idx < row.len) {
                    max_width = @max(max_width, row[col_idx].value.len);
                }
            }

            width.* = @max(@min(@as(u32, @intCast(max_width)), config.max_cell_width), config.min_cell_width);
        }
    }
};

/// Selection management
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

    /// Normalize selection so start <= end
    pub fn normalize(self: Selection) Selection {
        return Selection{
            .start = Point.init(@min(self.start.x, self.end.x), @min(self.start.y, self.end.y)),
            .end = Point.init(@max(self.start.x, self.end.x), @max(self.start.y, self.end.y)),
            .mode = self.mode,
        };
    }

    /// Check if a point is within the selection
    pub fn contains(self: Selection, point: Point) bool {
        const norm = self.normalize();
        return point.x >= norm.start.x and point.x <= norm.end.x and
            point.y >= norm.start.y and point.y <= norm.end.y;
    }

    /// Get the total number of selected cells
    pub fn getCellCount(self: Selection) u32 {
        const norm = self.normalize();
        return @as(u32, @intCast((norm.end.x - norm.start.x + 1) * (norm.end.y - norm.start.y + 1)));
    }

    /// Create a single cell selection
    pub fn singleCell(point: Point) Selection {
        return Selection{
            .start = point,
            .end = point,
            .mode = .cell,
        };
    }

    /// Create a row selection
    pub fn row(row_idx: i32, col_count: usize) Selection {
        return Selection{
            .start = Point.init(0, row_idx),
            .end = Point.init(@as(i32, @intCast(col_count)) - 1, row_idx),
            .mode = .row,
        };
    }

    /// Create a column selection
    pub fn column(col_idx: i32, row_count: usize) Selection {
        return Selection{
            .start = Point.init(col_idx, 0),
            .end = Point.init(col_idx, @as(i32, @intCast(row_count)) - 1),
            .mode = .column,
        };
    }

    /// Create a range selection
    pub fn range(start: Point, end: Point) Selection {
        return Selection{
            .start = start,
            .end = end,
            .mode = .range,
        };
    }
};

/// Column information and metadata
pub const Column = struct {
    index: usize,
    header: []const u8,
    width: u32,
    sortable: bool = true,
    resizable: bool = true,
    alignment: Cell.CellStyle.Alignment = .left,

    /// Calculate the display width needed for this column
    pub fn calculateWidth(self: Column, rows: [][]Cell, config: Config) u32 {
        var max_width = self.header.len;

        for (rows) |row| {
            if (self.index < row.len) {
                max_width = @max(max_width, row[self.index].value.len);
            }
        }

        return @max(@min(@as(u32, @intCast(max_width)), config.max_cell_width), config.min_cell_width);
    }
};

/// Pagination management
pub const Pagination = struct {
    current_page: u32 = 0,
    page_size: u32,
    total_rows: usize,

    pub fn init(page_size: u32, total_rows: usize) Pagination {
        return Pagination{
            .page_size = page_size,
            .total_rows = total_rows,
        };
    }

    pub fn getTotalPages(self: Pagination) u32 {
        if (self.total_rows == 0) return 1;
        return @as(u32, @intFromFloat(@ceil(@as(f64, @floatFromInt(self.total_rows)) / @as(f64, @floatFromInt(self.page_size)))));
    }

    pub fn getStartRow(self: Pagination) usize {
        return @as(usize, self.current_page * self.page_size);
    }

    pub fn getEndRow(self: Pagination) usize {
        return @min(self.total_rows, @as(usize, (self.current_page + 1) * self.page_size));
    }

    pub fn nextPage(self: *Pagination) void {
        if (self.current_page + 1 < self.getTotalPages()) {
            self.current_page += 1;
        }
    }

    pub fn previousPage(self: *Pagination) void {
        if (self.current_page > 0) {
            self.current_page -= 1;
        }
    }

    pub fn goToPage(self: *Pagination, page: u32) void {
        self.current_page = @min(page, self.getTotalPages() - 1);
    }
};

/// Table dimensions and layout calculations
pub const TableLayout = struct {
    header_height: u32,
    row_height: u32,
    total_width: u32,
    total_height: u32,
    visible_rows: u32,
    scroll_needed: bool,

    pub fn calculate(bounds: Bounds, column_widths: []const u32, row_count: usize, config: Config) TableLayout {
        // Calculate total width needed
        var total_width: u32 = 0;
        for (column_widths) |width| {
            total_width += width + 1; // +1 for column separator
        }
        if (total_width > 0) total_width -= 1; // Remove last separator

        // Calculate layout dimensions
        const header_height: u32 = if (config.showHeaders) 1 else 0;
        const row_height: u32 = 1;
        const available_height = @as(u32, @intCast(bounds.height));
        const content_height = available_height - header_height - 1; // -1 for title

        const visible_rows = content_height / row_height;
        const scroll_needed = @as(u32, @intCast(row_count)) > visible_rows;

        return TableLayout{
            .header_height = header_height,
            .row_height = row_height,
            .total_width = total_width,
            .total_height = header_height + @as(u32, @intCast(row_count)) * row_height,
            .visible_rows = visible_rows,
            .scroll_needed = scroll_needed,
        };
    }
};

//! DataTable module exports
//! 
//! This module provides the public interface for the modular data table system.

const std = @import("std");
const renderer_mod = @import("../../../core/renderer.zig");
const events_mod = @import("../../../core/events.zig");

// Re-export all public types and functions
pub const base = @import("base.zig");
pub const selection = @import("selection.zig");
pub const clipboard = @import("clipboard.zig");

// Re-export commonly used types for convenience
pub const DataTable = DataTableImpl;
pub const Config = base.Config;
pub const Cell = base.Cell;
pub const TableState = base.TableState;
pub const Selection = base.Selection;
pub const DataTableError = base.DataTableError;

// Event types
pub const InputEvent = union(enum) {
    key: events_mod.KeyEvent,
    mouse: events_mod.MouseEvent,
    paste: []const u8,
};

/// Main DataTable implementation that combines all modules
pub const DataTableImpl = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    headers: [][]const u8,
    rows: [][]base.Cell,
    config: base.Config,
    state: base.TableState,
    bounds: base.Bounds = base.Bounds.init(0, 0, 0, 0),
    
    // Clipboard integration
    clipboard_manager: ?clipboard.ClipboardManager = null,
    
    /// Initialize table with headers and configuration
    pub fn init(allocator: std.mem.Allocator, headers: [][]const u8, config: base.Config) !Self {
        const state = try base.TableState.init(allocator, headers, config);
        
        return Self{
            .allocator = allocator,
            .headers = headers,
            .rows = &[_][]base.Cell{},
            .config = config,
            .state = state,
        };
    }
    
    /// Initialize table with clipboard support
    pub fn initWithClipboard(allocator: std.mem.Allocator, headers: [][]const u8, config: base.Config, terminal_caps: anytype) !Self {
        var table = try init(allocator, headers, config);
        
        if (config.clipboard_enabled) {
            table.clipboard_manager = clipboard.ClipboardManager.init(allocator, terminal_caps);
        }
        
        return table;
    }
    
    pub fn deinit(self: *Self) void {
        self.state.deinit(self.allocator);
        if (self.clipboard_manager) |*clip| {
            clip.deinit();
        }
    }
    
    /// Set table data
    pub fn setData(self: *Self, rows: [][]base.Cell) !void {
        self.rows = rows;
        
        // Recalculate column widths if needed
        if (self.config.resizable_columns) {
            self.state.recalculateColumnWidths(self.headers, self.rows, self.config);
        }
        
        // Reset cursor if it's out of bounds
        if (self.state.cursor.y >= self.rows.len) {
            self.state.cursor.y = if (self.rows.len > 0) @as(i32, @intCast(self.rows.len - 1)) else 0;
        }
    }
    
    /// Handle input events
    pub fn handleInput(self: *Self, event: InputEvent) !bool {
        switch (event) {
            .key => |key| return self.handleKeyEvent(key),
            .mouse => |mouse| return self.handleMouseEvent(mouse),
            .paste => |text| return self.handlePasteEvent(text),
        }
    }
    
    /// Handle keyboard input
    fn handleKeyEvent(self: *Self, key: events_mod.KeyEvent) !bool {
        const row_count = self.rows.len;
        const col_count = if (self.headers.len > 0) self.headers.len else 0;
        
        switch (key.key) {
            .arrow_up => {
                self.state.moveCursor(0, -1, row_count, col_count);
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .arrow_down => {
                self.state.moveCursor(0, 1, row_count, col_count);
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .arrow_left => {
                self.state.moveCursor(-1, 0, row_count, col_count);
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .arrow_right => {
                self.state.moveCursor(1, 0, row_count, col_count);
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .home => {
                self.state.cursor.x = 0;
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .end => {
                self.state.cursor.x = @as(i32, @intCast(col_count)) - 1;
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .page_up => {
                self.state.moveCursor(0, -10, row_count, col_count);
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .page_down => {
                self.state.moveCursor(0, 10, row_count, col_count);
                selection.SelectionManager.extendSelection(&self.state, key, row_count, col_count);
                return true;
            },
            .char => |c| {
                if (key.modifiers.ctrl and c == 'c' and self.state.selection != null) {
                    try self.copySelection();
                    return true;
                } else if (key.modifiers.ctrl and c == 'a') {
                    // Select all
                    self.state.selection = base.Selection.range(
                        base.Point.init(0, 0),
                        base.Point.init(@as(i32, @intCast(col_count)) - 1, @as(i32, @intCast(row_count)) - 1)
                    );
                    return true;
                }
                return false;
            },
            .escape => {
                self.state.selection = null;
                return true;
            },
            else => return false,
        }
    }
    
    /// Handle mouse input
    fn handleMouseEvent(self: *Self, mouse: events_mod.MouseEvent) !bool {
        _ = self;
        _ = mouse;
        // TODO: Implement mouse handling with cell bounds calculation
        return false;
    }
    
    /// Handle paste input
    fn handlePasteEvent(self: *Self, text: []const u8) !bool {
        _ = self;
        _ = text;
        // TODO: Implement paste handling
        return false;
    }
    
    /// Copy current selection to clipboard
    pub fn copySelection(self: *Self) !void {
        if (self.state.selection == null) return;
        if (self.clipboard_manager == null) return;
        
        try self.clipboard_manager.?.copySelection(
            self.state.selection.?,
            self.headers,
            self.rows,
            .plain_text,
        );
    }
    
    /// Copy selection in specific format
    pub fn copySelectionAs(self: *Self, format: selection.ClipboardFormat) !void {
        if (self.state.selection == null) return;
        if (self.clipboard_manager == null) return;
        
        try self.clipboard_manager.?.copySelection(
            self.state.selection.?,
            self.headers,
            self.rows,
            format,
        );
    }
    
    /// Get information about selected data
    pub fn getSelectionInfo(self: Self) ?SelectionInfo {
        if (self.state.selection) |sel| {
            return SelectionInfo{
                .cell_count = sel.getCellCount(),
                .mode = sel.mode,
                .bounds = sel.normalize(),
            };
        }
        return null;
    }
    
    /// Simple render method for basic usage (advanced rendering would be in a separate renderer module)
    pub fn render(self: *Self, renderer: *renderer_mod.Renderer, ctx: renderer_mod.RenderContext) !void {
        self.bounds = ctx.bounds;
        
        // This is a simplified render implementation
        // In a full implementation, this would delegate to a separate renderer module
        
        var current_y = ctx.bounds.y;
        
        // Render title if present
        if (self.config.title) |title| {
            const title_ctx = renderer_mod.RenderContext{
                .bounds = base.Bounds.init(ctx.bounds.x, current_y, ctx.bounds.width, 1),
                .style = renderer_mod.Style{ .bold = true },
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };
            try renderer.drawText(title_ctx, title);
            current_y += 2;
        }
        
        // Render headers
        if (self.config.show_headers) {
            var current_x = ctx.bounds.x;
            for (self.headers, 0..) |header, col_idx| {
                const col_width = if (col_idx < self.state.column_widths.len) 
                    self.state.column_widths[col_idx] 
                else 
                    self.config.min_cell_width;
                
                const header_ctx = renderer_mod.RenderContext{
                    .bounds = base.Bounds.init(current_x, current_y, @intCast(col_width), 1),
                    .style = renderer_mod.Style{ .bold = true },
                    .z_index = ctx.z_index,
                    .clip_region = ctx.clip_region,
                };
                try renderer.drawText(header_ctx, header);
                current_x += @intCast(col_width + 1);
            }
            current_y += 1;
        }
        
        // Render visible rows
        const visible_rows = @min(self.rows.len, @as(usize, @intCast(ctx.bounds.height - (current_y - ctx.bounds.y))));
        for (0..visible_rows) |row_idx| {
            if (row_idx >= self.rows.len) break;
            
            const row = self.rows[row_idx];
            var current_x = ctx.bounds.x;
            
            for (row, 0..) |cell, col_idx| {
                const col_width = if (col_idx < self.state.column_widths.len) 
                    self.state.column_widths[col_idx] 
                else 
                    self.config.min_cell_width;
                
                // Check if this cell is selected
                const cell_point = base.Point.init(@intCast(col_idx), @intCast(row_idx));
                const is_selected = self.state.selection != null and self.state.selection.?.contains(cell_point);
                
                const cell_style = if (is_selected) 
                    renderer_mod.Style{ .bg_color = .{ .palette = 8 } }  // Highlight selected cells
                else 
                    renderer_mod.Style{};
                
                const cell_ctx = renderer_mod.RenderContext{
                    .bounds = base.Bounds.init(current_x, current_y, @intCast(col_width), 1),
                    .style = cell_style,
                    .z_index = ctx.z_index,
                    .clip_region = ctx.clip_region,
                };
                
                // Truncate cell value to fit column width
                const display_value = if (cell.value.len > col_width) 
                    cell.value[0..col_width] 
                else 
                    cell.value;
                
                try renderer.drawText(cell_ctx, display_value);
                current_x += @intCast(col_width + 1);
            }
            current_y += 1;
        }
    }
    
    /// Create a simple cell
    pub fn createCell(value: []const u8) base.Cell {
        return base.Cell{ .value = value };
    }
    
    /// Create a styled cell
    pub fn createStyledCell(value: []const u8, style: base.Cell.CellStyle) base.Cell {
        return base.Cell{ .value = value, .style = style };
    }
};

/// Information about current selection
pub const SelectionInfo = struct {
    cell_count: u32,
    mode: base.Selection.SelectionMode,
    bounds: base.Selection,
};

/// Convenience functions for common table operations

/// Create a simple table with string data
pub fn createSimpleTable(allocator: std.mem.Allocator, headers: [][]const u8, data: [][]const u8) !DataTable {
    var table = try DataTable.init(allocator, headers, base.Config{});
    
    // Convert string data to cells
    var rows = try allocator.alloc([]base.Cell, data.len);
    for (data, 0..) |row_data, row_idx| {
        rows[row_idx] = try allocator.alloc(base.Cell, row_data.len);
        for (row_data, 0..) |cell_data, col_idx| {
            rows[row_idx][col_idx] = DataTable.createCell(cell_data);
        }
    }
    
    try table.setData(rows);
    return table;
}

/// Create a table from CSV-like data
pub fn createTableFromCSV(allocator: std.mem.Allocator, csv_data: []const u8, has_header: bool) !DataTable {
    var lines = std.mem.split(u8, csv_data, "\n");
    
    // Parse header
    const header_line = lines.next() orelse return base.DataTableError.InvalidData;
    var headers = std.ArrayList([]const u8).init(allocator);
    defer headers.deinit();
    
    var header_iter = std.mem.split(u8, header_line, ",");
    while (header_iter.next()) |header| {
        try headers.append(std.mem.trim(u8, header, " \t"));
    }
    
    const config = base.Config{
        .show_headers = has_header,
        .clipboard_enabled = true,
    };
    
    var table = try DataTable.init(allocator, try headers.toOwnedSlice(), config);
    
    // Parse data rows
    var rows = std.ArrayList([]base.Cell).init(allocator);
    defer rows.deinit();
    
    // Skip header line if it exists
    if (has_header) {
        _ = lines.next();
    }
    
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        
        var row_cells = std.ArrayList(base.Cell).init(allocator);
        defer row_cells.deinit();
        
        var cell_iter = std.mem.split(u8, line, ",");
        while (cell_iter.next()) |cell_data| {
            const trimmed = std.mem.trim(u8, cell_data, " \t");
            try row_cells.append(DataTable.createCell(trimmed));
        }
        
        try rows.append(try row_cells.toOwnedSlice());
    }
    
    try table.setData(try rows.toOwnedSlice());
    return table;
}
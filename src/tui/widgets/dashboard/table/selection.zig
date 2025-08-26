//! Table selection management and operations
//! 
//! Handles selection state, multi-cell operations, and selection rendering.

const std = @import("std");
const base = @import("base.zig");
const events_mod = @import("../../../core/events.zig");

const Point = base.Point;
const Selection = base.Selection;
const TableState = base.TableState;
const Cell = base.Cell;
const KeyEvent = events_mod.KeyEvent;
const MouseEvent = events_mod.MouseEvent;

/// Selection manager handles selection operations and state
pub const SelectionManager = struct {
    /// Extend selection based on keyboard input
    pub fn extendSelection(state: *TableState, key: KeyEvent, row_count: usize, col_count: usize) void {
        _ = row_count;
        _ = col_count;
        
        if (!key.modifiers.shift) {
            // Clear selection if not extending
            state.selection = null;
            return;
        }
        
        // Create or extend existing selection
        if (state.selection == null) {
            state.selection = Selection.singleCell(state.cursor);
        }
        
        if (state.selection) |*selection| {
            // Update end point of selection based on new cursor position
            selection.end = state.cursor;
            
            // Determine selection mode based on movement
            if (key.modifiers.ctrl) {
                // Ctrl+Shift for rectangular selection
                selection.mode = .range;
            } else {
                // Regular Shift for range selection
                selection.mode = .range;
            }
        }
    }
    
    /// Get selected cells data for clipboard operations
    pub fn getSelectedData(selection: Selection, headers: [][]const u8, rows: [][]Cell, allocator: std.mem.Allocator) ![]u8 {
        const norm_selection = selection.normalize();
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        const writer = result.writer();
        
        switch (selection.mode) {
            .cell => {
                // Single cell
                const start_y = @as(usize, @intCast(norm_selection.start.y));
                const start_x = @as(usize, @intCast(norm_selection.start.x));
                if (start_y < rows.len and start_x < rows[start_y].len) {
                    const cell = rows[start_y][start_x];
                    if (cell.copyable) {
                        try writer.writeAll(cell.value);
                    }
                }
            },
            .row => {
                // Entire row(s)
                const start_y = @as(usize, @intCast(norm_selection.start.y));
                const end_y = @as(usize, @intCast(norm_selection.end.y));
                
                for (start_y..end_y + 1) |row_idx| {
                    if (row_idx >= rows.len) break;
                    
                    const row = rows[row_idx];
                    for (row, 0..) |cell, col_idx| {
                        if (cell.copyable) {
                            try writer.writeAll(cell.value);
                            if (col_idx < row.len - 1) {
                                try writer.writeAll("\t"); // Tab separator
                            }
                        }
                    }
                    
                    if (row_idx < end_y) {
                        try writer.writeAll("\n");
                    }
                }
            },
            .column => {
                // Entire column(s)
                const col_idx = @as(usize, @intCast(norm_selection.start.x));
                
                // Include header if available
                if (col_idx < headers.len) {
                    try writer.writeAll(headers[col_idx]);
                    if (rows.len > 0) try writer.writeAll("\n");
                }
                
                for (rows, 0..) |row, row_idx| {
                    if (col_idx < row.len and row[col_idx].copyable) {
                        try writer.writeAll(row[col_idx].value);
                        if (row_idx < rows.len - 1) {
                            try writer.writeAll("\n");
                        }
                    }
                }
            },
            .range => {
                // Rectangular range
                const start_y = @as(usize, @intCast(norm_selection.start.y));
                const end_y = @as(usize, @intCast(norm_selection.end.y));
                const start_x = @as(usize, @intCast(norm_selection.start.x));
                const end_x = @as(usize, @intCast(norm_selection.end.x));
                
                for (start_y..end_y + 1) |row_idx| {
                    if (row_idx >= rows.len) break;
                    
                    const row = rows[row_idx];
                    for (start_x..end_x + 1) |col_idx| {
                        if (col_idx >= row.len) break;
                        
                        const cell = row[col_idx];
                        if (cell.copyable) {
                            try writer.writeAll(cell.value);
                            if (col_idx < end_x) {
                                try writer.writeAll("\t");
                            }
                        }
                    }
                    
                    if (row_idx < end_y) {
                        try writer.writeAll("\n");
                    }
                }
            },
        }
        
        return result.toOwnedSlice();
    }
    
    /// Get selection in different formats for clipboard
    pub fn formatSelectedData(selection: Selection, headers: [][]const u8, rows: [][]Cell, allocator: std.mem.Allocator, format: ClipboardFormat) ![]u8 {
        switch (format) {
            .plain_text => return getSelectedData(selection, headers, rows, allocator),
            .csv => return formatAsCSV(selection, headers, rows, allocator),
            .markdown => return formatAsMarkdown(selection, headers, rows, allocator),
        }
    }
    
    /// Format selection as CSV
    fn formatAsCSV(selection: Selection, headers: [][]const u8, rows: [][]Cell, allocator: std.mem.Allocator) ![]u8 {
        const norm_selection = selection.normalize();
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        const writer = result.writer();
        
        const start_x = @as(usize, @intCast(norm_selection.start.x));
        const end_x = @as(usize, @intCast(norm_selection.end.x));
        const start_y = @as(usize, @intCast(norm_selection.start.y));
        const end_y = @as(usize, @intCast(norm_selection.end.y));
        
        // CSV header row for range/column selections
        if (selection.mode == .range or selection.mode == .column) {
            for (start_x..end_x + 1) |col_idx| {
                if (col_idx < headers.len) {
                    try writeCSVField(writer, headers[col_idx]);
                    if (col_idx < end_x) {
                        try writer.writeAll(",");
                    }
                }
            }
            try writer.writeAll("\n");
        }
        
        // CSV data rows
        for (start_y..end_y + 1) |row_idx| {
            if (row_idx >= rows.len) break;
            
            const row = rows[row_idx];
            for (start_x..end_x + 1) |col_idx| {
                if (col_idx >= row.len) break;
                
                const cell = row[col_idx];
                if (cell.copyable) {
                    try writeCSVField(writer, cell.value);
                }
                
                if (col_idx < end_x) {
                    try writer.writeAll(",");
                }
            }
            
            if (row_idx < end_y) {
                try writer.writeAll("\n");
            }
        }
        
        return result.toOwnedSlice();
    }
    
    /// Format selection as Markdown table
    fn formatAsMarkdown(selection: Selection, headers: [][]const u8, rows: [][]Cell, allocator: std.mem.Allocator) ![]u8 {
        const norm_selection = selection.normalize();
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        const writer = result.writer();
        
        const start_x = @as(usize, @intCast(norm_selection.start.x));
        const end_x = @as(usize, @intCast(norm_selection.end.x));
        const start_y = @as(usize, @intCast(norm_selection.start.y));
        const end_y = @as(usize, @intCast(norm_selection.end.y));
        
        // Markdown header row
        try writer.writeAll("|");
        for (start_x..end_x + 1) |col_idx| {
            if (col_idx < headers.len) {
                try writer.print(" {s} |", .{headers[col_idx]});
            }
        }
        try writer.writeAll("\n");
        
        // Markdown separator row
        try writer.writeAll("|");
        for (start_x..end_x + 1) |_| {
            try writer.writeAll("---|");
        }
        try writer.writeAll("\n");
        
        // Markdown data rows
        for (start_y..end_y + 1) |row_idx| {
            if (row_idx >= rows.len) break;
            
            try writer.writeAll("|");
            const row = rows[row_idx];
            for (start_x..end_x + 1) |col_idx| {
                if (col_idx < row.len and row[col_idx].copyable) {
                    try writer.print(" {s} |", .{row[col_idx].value});
                } else {
                    try writer.writeAll("  |");
                }
            }
            try writer.writeAll("\n");
        }
        
        return result.toOwnedSlice();
    }
    
    /// Write a CSV field, escaping quotes and commas as needed
    fn writeCSVField(writer: anytype, field: []const u8) !void {
        const needs_quotes = std.mem.containsAtLeast(u8, field, 1, ",") or 
                           std.mem.containsAtLeast(u8, field, 1, "\"") or
                           std.mem.containsAtLeast(u8, field, 1, "\n");
        
        if (needs_quotes) {
            try writer.writeAll("\"");
            for (field) |c| {
                if (c == '"') {
                    try writer.writeAll("\"\""); // Escape quotes by doubling
                } else {
                    try writer.writeByte(c);
                }
            }
            try writer.writeAll("\"");
        } else {
            try writer.writeAll(field);
        }
    }
};

/// Clipboard format options
pub const ClipboardFormat = enum {
    plain_text,
    csv,
    markdown,
    
    pub fn getFileExtension(self: ClipboardFormat) []const u8 {
        return switch (self) {
            .plain_text => ".txt",
            .csv => ".csv",
            .markdown => ".md",
        };
    }
    
    pub fn getMimeType(self: ClipboardFormat) []const u8 {
        return switch (self) {
            .plain_text => "text/plain",
            .csv => "text/csv",
            .markdown => "text/markdown",
        };
    }
};
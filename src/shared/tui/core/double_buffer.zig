const std = @import("std");
const term_shared = @import("term_shared");
const Cell = term_shared.cellbuf.Cell;
const Style = term_shared.cellbuf.Style;
const Color = term_shared.cellbuf.Color;
const RichCellBuffer = @import("../../components/cell_buffer.zig").RichCellBuffer;
const Rectangle = term_shared.cellbuf.Rectangle;

/// Statistics for tracking rendering performance
pub const RenderStatistics = struct {
    /// Total number of cells in the buffer
    total_cells: usize = 0,
    /// Number of cells changed in last frame
    cells_changed: usize = 0,
    /// Number of terminal sequences generated
    sequences_sent: usize = 0,
    /// Number of cursor movements
    cursor_moves: usize = 0,
    /// Number of style changes
    style_changes: usize = 0,
    /// Number of consecutive cell runs
    cell_runs: usize = 0,
    /// Time spent diffing (nanoseconds)
    diff_time_ns: u64 = 0,
    /// Time spent rendering (nanoseconds)
    render_time_ns: u64 = 0,
    /// Frame count since last reset
    frame_count: usize = 0,
    /// Whether last frame was completely redrawn
    full_redraw: bool = false,

    pub fn reset(self: *RenderStatistics) void {
        self.* = RenderStatistics{};
    }

    pub fn getChangePercentage(self: RenderStatistics) f32 {
        if (self.total_cells == 0) return 0.0;
        return @as(f32, @floatFromInt(self.cells_changed)) / @as(f32, @floatFromInt(self.total_cells)) * 100.0;
    }

    pub fn getAverageDiffTimeMs(self: RenderStatistics) f64 {
        if (self.frame_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.diff_time_ns)) / @as(f64, @floatFromInt(self.frame_count)) / 1_000_000.0;
    }

    pub fn getAverageRenderTimeMs(self: RenderStatistics) f64 {
        if (self.frame_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.render_time_ns)) / @as(f64, @floatFromInt(self.frame_count)) / 1_000_000.0;
    }
};

/// A run of consecutive cells with the same style
const CellRun = struct {
    x: u32,
    y: u32,
    length: u32,
    style: Style,
    cells: []const Cell,
};

/// Optimization hints for rendering
pub const RenderOptimization = struct {
    /// Use escape sequences for clearing instead of spaces
    use_clear_sequences: bool = true,
    /// Batch consecutive cells with same style
    batch_cell_runs: bool = true,
    /// Skip unchanged regions
    skip_unchanged: bool = true,
    /// Use relative cursor movements when beneficial
    use_relative_moves: bool = true,
    /// Minimize style resets
    minimize_style_changes: bool = true,
    /// Use terminal's erase functions
    use_erase_functions: bool = true,
};

/// Double buffer for diff-based terminal rendering
pub const DoubleBuffer = struct {
    allocator: std.mem.Allocator,
    /// Front buffer (what's currently displayed)
    front: RichCellBuffer,
    /// Back buffer (what we're drawing to)
    back: RichCellBuffer,
    /// Width of buffers
    width: u32,
    /// Height of buffers
    height: u32,
    /// Current cursor position after last render
    cursor_x: u32 = 0,
    cursor_y: u32 = 0,
    /// Current active style
    current_style: Style = .{},
    /// Rendering statistics
    stats: RenderStatistics = .{},
    /// Optimization settings
    optimization: RenderOptimization = .{},
    /// Dirty region tracking
    dirty_region: ?Rectangle = null,
    /// Output writer for terminal sequences
    writer: ?std.io.AnyWriter = null,

    const Self = @This();

    /// Initialize double buffer with given dimensions
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Self {
        const front = try RichCellBuffer.init(allocator, width, height);
        errdefer front.deinit();

        const back = try RichCellBuffer.init(allocator, width, height);
        errdefer back.deinit();

        var self = Self{
            .allocator = allocator,
            .front = front,
            .back = back,
            .width = width,
            .height = height,
        };

        self.stats.total_cells = width * height;
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.front.deinit();
        self.back.deinit();
    }

    /// Set the output writer for terminal sequences
    pub fn setWriter(self: *Self, writer: std.io.AnyWriter) void {
        self.writer = writer;
    }

    /// Get the back buffer for drawing
    pub fn getBackBuffer(self: *Self) *RichCellBuffer {
        return &self.back;
    }

    /// Mark a region as dirty for redraw
    pub fn markDirty(self: *Self, rect: Rectangle) void {
        if (self.dirty_region) |existing| {
            // Expand dirty region to include new rectangle
            const x1 = @min(existing.x, rect.x);
            const y1 = @min(existing.y, rect.y);
            const x2 = @max(existing.x + @as(i32, @intCast(existing.width)), rect.x + @as(i32, @intCast(rect.width)));
            const y2 = @max(existing.y + @as(i32, @intCast(existing.height)), rect.y + @as(i32, @intCast(rect.height)));

            self.dirty_region = Rectangle{
                .x = x1,
                .y = y1,
                .width = @intCast(x2 - x1),
                .height = @intCast(y2 - y1),
            };
        } else {
            self.dirty_region = rect;
        }
    }

    /// Mark entire buffer as dirty
    pub fn markAllDirty(self: *Self) void {
        self.dirty_region = Rectangle{
            .x = 0,
            .y = 0,
            .width = self.width,
            .height = self.height,
        };
    }

    /// Clear the dirty region
    pub fn clearDirty(self: *Self) void {
        self.dirty_region = null;
    }

    /// Resize both buffers
    pub fn resize(self: *Self, new_width: u32, new_height: u32) !void {
        try self.front.resize(new_width, new_height);
        try self.back.resize(new_width, new_height);

        self.width = new_width;
        self.height = new_height;
        self.stats.total_cells = new_width * new_height;

        // Mark everything as dirty after resize
        self.markAllDirty();
    }

    /// Swap front and back buffers
    pub fn swap(self: *Self) void {
        const temp = self.front;
        self.front = self.back;
        self.back = temp;
    }

    /// Clear the back buffer
    pub fn clear(self: *Self) void {
        self.back.clear();
        self.markAllDirty();
    }

    /// Perform diff and generate optimized update sequences
    pub fn render(self: *Self) !void {
        if (self.writer == null) return;

        const start_diff = std.time.nanoTimestamp();

        // Build list of changes
        var changes = std.ArrayList(DiffChange).init(self.allocator);
        defer changes.deinit();

        // Determine scan region
        const scan_region = self.dirty_region orelse Rectangle{
            .x = 0,
            .y = 0,
            .width = self.width,
            .height = self.height,
        };

        // Diff the buffers
        try self.diffBuffers(&changes, scan_region);

        const end_diff = std.time.nanoTimestamp();
        self.stats.diff_time_ns += @intCast(end_diff - start_diff);

        // Generate and send update sequences
        const start_render = std.time.nanoTimestamp();

        if (changes.items.len > 0) {
            if (self.optimization.batch_cell_runs) {
                try self.renderBatchedChanges(changes.items);
            } else {
                try self.renderIndividualChanges(changes.items);
            }
        }

        const end_render = std.time.nanoTimestamp();
        self.stats.render_time_ns += @intCast(end_render - start_render);

        self.stats.frame_count += 1;
        self.stats.cells_changed = changes.items.len;

        // Clear dirty region after successful render
        self.clearDirty();
    }

    const DiffChange = struct {
        x: u32,
        y: u32,
        cell: Cell,
    };

    /// Diff two buffers and collect changes
    fn diffBuffers(self: *Self, changes: *std.ArrayList(DiffChange), region: Rectangle) !void {
        const start_y = @max(0, region.y);
        const end_y = @min(@as(i32, @intCast(self.height)), region.y + @as(i32, @intCast(region.height)));
        const start_x = @max(0, region.x);
        const end_x = @min(@as(i32, @intCast(self.width)), region.x + @as(i32, @intCast(region.width)));

        var y = @as(u32, @intCast(start_y));
        while (y < @as(u32, @intCast(end_y))) : (y += 1) {
            var x = @as(u32, @intCast(start_x));
            while (x < @as(u32, @intCast(end_x))) : (x += 1) {
                const front_cell = self.front.getCell(x, y) orelse continue;
                const back_cell = self.back.getCell(x, y) orelse continue;

                if (!front_cell.eql(back_cell.*)) {
                    try changes.append(DiffChange{
                        .x = x,
                        .y = y,
                        .cell = back_cell.*,
                    });

                    // Skip wide character continuation cells
                    if (back_cell.isWide()) {
                        x += back_cell.width - 1;
                    }
                }
            }
        }
    }

    /// Render changes as batched runs
    fn renderBatchedChanges(self: *Self, changes: []const DiffChange) !void {
        if (changes.len == 0) return;

        var runs = std.ArrayList(CellRun).init(self.allocator);
        defer runs.deinit();

        // Group consecutive cells with same style into runs
        var current_run_start: usize = 0;
        var current_style = changes[0].cell.style;
        var current_y = changes[0].y;
        var expected_x = changes[0].x + 1;

        for (changes[1..], 1..) |change, i| {
            const is_consecutive = (change.y == current_y and change.x == expected_x);
            const same_style = change.cell.style.eql(current_style);

            if (!is_consecutive or !same_style) {
                // End current run
                const run_length = i - current_run_start;
                try runs.append(CellRun{
                    .x = changes[current_run_start].x,
                    .y = changes[current_run_start].y,
                    .length = @intCast(run_length),
                    .style = current_style,
                    .cells = undefined, // Will build cell array when rendering
                });

                self.stats.cell_runs += 1;

                // Start new run
                current_run_start = i;
                current_style = change.cell.style;
                current_y = change.y;
            }

            expected_x = change.x + 1;
        }

        // Add final run
        const run_length = changes.len - current_run_start;
        try runs.append(CellRun{
            .x = changes[current_run_start].x,
            .y = changes[current_run_start].y,
            .length = @intCast(run_length),
            .style = changes[current_run_start].cell.style,
            .cells = undefined,
        });
        self.stats.cell_runs += 1;

        // Render each run
        for (runs.items, 0..) |run, run_idx| {
            // Build cell content for this run
            var content = std.ArrayList(u8).init(self.allocator);
            defer content.deinit();

            const run_start = blk: {
                var sum: usize = 0;
                for (runs.items[0..run_idx]) |r| {
                    sum += r.length;
                }
                break :blk sum;
            };

            for (run_start..run_start + run.length) |index| {
                const cell_str = try changes[index].cell.toString(self.allocator);
                defer self.allocator.free(cell_str);
                try content.appendSlice(cell_str);
            }

            // Move cursor if needed
            try self.moveCursorOptimized(run.x, run.y);

            // Apply style if different
            if (!run.style.eql(self.current_style)) {
                try self.applyStyle(run.style);
            }

            // Write content
            try self.writer.?.writeAll(content.items);
            self.stats.sequences_sent += 1;

            // Update cursor position
            self.cursor_x = run.x + run.length;
            self.cursor_y = run.y;
        }
    }

    /// Render changes individually
    fn renderIndividualChanges(self: *Self, changes: []const DiffChange) !void {
        for (changes) |change| {
            // Move cursor
            try self.moveCursorOptimized(change.x, change.y);

            // Apply style if different
            if (!change.cell.style.eql(self.current_style)) {
                try self.applyStyle(change.cell.style);
            }

            // Write cell content
            const cell_str = try change.cell.toString(self.allocator);
            defer self.allocator.free(cell_str);

            try self.writer.?.writeAll(cell_str);
            self.stats.sequences_sent += 1;

            // Update cursor position
            self.cursor_x = change.x + 1;
            self.cursor_y = change.y;
        }
    }

    /// Move cursor with optimization
    fn moveCursorOptimized(self: *Self, target_x: u32, target_y: u32) !void {
        if (self.cursor_x == target_x and self.cursor_y == target_y) {
            return; // Already at target position
        }

        const writer = self.writer.?;

        if (self.optimization.use_relative_moves) {
            // Check if relative movement is more efficient
            const dx = @as(i32, @intCast(target_x)) - @as(i32, @intCast(self.cursor_x));
            const dy = @as(i32, @intCast(target_y)) - @as(i32, @intCast(self.cursor_y));

            // Use relative movements for small distances
            if (dy == 0 and @abs(dx) <= 3) {
                // Horizontal movement only
                if (dx > 0) {
                    // Move right
                    try writer.print("\x1b[{d}C", .{dx});
                } else if (dx < 0) {
                    // Move left
                    try writer.print("\x1b[{d}D", .{-dx});
                }
                self.cursor_x = target_x;
                self.stats.cursor_moves += 1;
                return;
            } else if (dx == 0 and @abs(dy) <= 3) {
                // Vertical movement only
                if (dy > 0) {
                    // Move down
                    try writer.print("\x1b[{d}B", .{dy});
                } else if (dy < 0) {
                    // Move up
                    try writer.print("\x1b[{d}A", .{-dy});
                }
                self.cursor_y = target_y;
                self.stats.cursor_moves += 1;
                return;
            }
        }

        // Use absolute positioning
        try writer.print("\x1b[{d};{d}H", .{ target_y + 1, target_x + 1 });
        self.cursor_x = target_x;
        self.cursor_y = target_y;
        self.stats.cursor_moves += 1;
    }

    /// Apply style to terminal
    fn applyStyle(self: *Self, style: Style) !void {
        const style_seq = try style.toAnsiSeq(self.allocator);
        defer self.allocator.free(style_seq);

        try self.writer.?.writeAll(style_seq);
        self.current_style = style;
        self.stats.style_changes += 1;
        self.stats.sequences_sent += 1;
    }

    /// Force full redraw
    pub fn forceRedraw(self: *Self) !void {
        self.stats.full_redraw = true;

        // Reset cursor and style
        try self.writer.?.writeAll("\x1b[H\x1b[0m");
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.current_style = .{};

        // Mark everything as changed
        var changes = std.ArrayList(DiffChange).init(self.allocator);
        defer changes.deinit();

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                if (self.back.getCell(@intCast(x), @intCast(y))) |cell| {
                    try changes.append(DiffChange{
                        .x = @intCast(x),
                        .y = @intCast(y),
                        .cell = cell.*,
                    });
                }
            }
        }

        try self.renderBatchedChanges(changes.items);
    }

    /// Get current statistics
    pub fn getStats(self: *Self) RenderStatistics {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *Self) void {
        self.stats.reset();
        self.stats.total_cells = self.width * self.height;
    }

    /// Set optimization options
    pub fn setOptimization(self: *Self, opt: RenderOptimization) void {
        self.optimization = opt;
    }

    /// Check if a full redraw would be more efficient than incremental updates
    pub fn shouldFullRedraw(self: *Self, change_threshold: f32) bool {
        const change_percentage = self.stats.getChangePercentage();
        return change_percentage > change_threshold;
    }

    /// Optimize for specific patterns (e.g., scrolling)
    pub fn detectScrollPattern(self: *Self) bool {
        // Analyze changes to detect if content has scrolled
        // This is a simplified version - real implementation would be more sophisticated

        var line_changes = [_]bool{false} ** 256; // Max 256 lines
        const max_lines = @min(self.height, 256);

        for (0..max_lines) |y| {
            for (0..self.width) |x| {
                const front = self.front.getCell(@intCast(x), @intCast(y));
                const back = self.back.getCell(@intCast(x), @intCast(y));

                if (front != null and back != null and !front.?.eql(back.?.*)) {
                    line_changes[y] = true;
                    break;
                }
            }
        }

        // Check if changes follow a scroll pattern
        var consecutive_changes: u32 = 0;
        for (line_changes[0..max_lines]) |changed| {
            if (changed) {
                consecutive_changes += 1;
            } else if (consecutive_changes > 0) {
                break;
            }
        }

        // If most lines changed consecutively, likely a scroll
        return consecutive_changes > self.height / 2;
    }

    /// Clear screen with optimization
    pub fn clearScreen(self: *Self) !void {
        if (self.writer == null) return;

        if (self.optimization.use_clear_sequences) {
            // Use terminal clear sequence
            try self.writer.?.writeAll("\x1b[2J\x1b[H");
            self.cursor_x = 0;
            self.cursor_y = 0;
            self.stats.sequences_sent += 1;
        } else {
            // Clear by overwriting with spaces
            try self.forceRedraw();
        }

        // Clear both buffers
        self.front.clear();
        self.back.clear();
    }

    /// Erase line with optimization
    pub fn eraseLine(self: *Self, y: u32, from_cursor: bool) !void {
        if (self.writer == null) return;

        if (self.optimization.use_erase_functions) {
            try self.moveCursorOptimized(0, y);

            if (from_cursor) {
                try self.writer.?.writeAll("\x1b[K"); // Erase from cursor to end of line
            } else {
                try self.writer.?.writeAll("\x1b[2K"); // Erase entire line
            }
            self.stats.sequences_sent += 1;

            // Update back buffer
            const blank = Cell{};
            for (0..self.width) |x| {
                _ = self.back.setCell(@intCast(x), y, blank);
            }
        } else {
            // Manual erase with spaces
            const blank = Cell{ .rune = ' ', .width = 1 };
            for (0..self.width) |x| {
                _ = self.back.setCell(@intCast(x), y, blank);
            }
            self.markDirty(Rectangle{
                .x = 0,
                .y = @intCast(y),
                .width = self.width,
                .height = 1,
            });
        }
    }
};

// Test helpers
test "double buffer initialization" {
    const allocator = std.testing.allocator;

    var db = try DoubleBuffer.init(allocator, 80, 24);
    defer db.deinit();

    try std.testing.expectEqual(@as(u32, 80), db.width);
    try std.testing.expectEqual(@as(u32, 24), db.height);
    try std.testing.expectEqual(@as(usize, 1920), db.stats.total_cells);
}

test "buffer swapping" {
    const allocator = std.testing.allocator;

    var db = try DoubleBuffer.init(allocator, 10, 10);
    defer db.deinit();

    // Modify back buffer
    const test_cell = Cell{ .rune = 'A', .width = 1 };
    _ = db.back.setCell(0, 0, test_cell);

    // Swap buffers
    db.swap();

    // Check that front buffer now has the change
    const front_cell = db.front.getCell(0, 0);
    try std.testing.expect(front_cell != null);
    try std.testing.expectEqual(@as(u21, 'A'), front_cell.?.rune);
}

test "dirty region tracking" {
    const allocator = std.testing.allocator;

    var db = try DoubleBuffer.init(allocator, 100, 50);
    defer db.deinit();

    // Initially no dirty region
    try std.testing.expect(db.dirty_region == null);

    // Mark a region dirty
    db.markDirty(Rectangle{ .x = 10, .y = 10, .width = 20, .height = 10 });
    try std.testing.expect(db.dirty_region != null);

    // Expand dirty region
    db.markDirty(Rectangle{ .x = 25, .y = 15, .width = 10, .height = 5 });

    const dirty = db.dirty_region.?;
    try std.testing.expectEqual(@as(i32, 10), dirty.x);
    try std.testing.expectEqual(@as(i32, 10), dirty.y);
    try std.testing.expectEqual(@as(u32, 25), dirty.width);
    try std.testing.expectEqual(@as(u32, 10), dirty.height);
}

test "statistics tracking" {
    const allocator = std.testing.allocator;

    var db = try DoubleBuffer.init(allocator, 10, 10);
    defer db.deinit();

    const stats = db.getStats();
    try std.testing.expectEqual(@as(usize, 100), stats.total_cells);
    try std.testing.expectEqual(@as(usize, 0), stats.cells_changed);
    try std.testing.expectEqual(@as(f32, 0.0), stats.getChangePercentage());
}

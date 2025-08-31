const std = @import("std");
const term = @import("term_shared");
const CellBuffer = term.cellbuf.CellBuffer;

// Point in 2D space with u32 coordinates
pub const Point = struct {
    x: u32,
    y: u32,
};

// Rectangular bounds with i16/u16 coordinates
const Rect = struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,
};

/// Border style for the block
pub const BorderStyle = enum {
    none, // No border
    single, // Single line border ─│┌┐└┘
    double, // Double line border ═║╔╗╚╝
    rounded, // Rounded corners ─│╭╮╰╯
    thick, // Thick line border ━┃┏┓┗┛
    dashed, // Dashed line border ╌╎
    dotted, // Dotted line border ⋯⋮
    ascii, // ASCII border -|+++
};

/// Border merger handles seamless connections between adjacent widgets
pub const Merger = struct {
    allocator: std.mem.Allocator,
    widgets: std.ArrayList(WidgetBoundary),
    merge_map: std.AutoHashMap(Point, JunctionType),

    pub const WidgetBoundary = struct {
        rect: Rect,
        style: BorderStyle,
        has_top: bool = true,
        has_bottom: bool = true,
        has_left: bool = true,
        has_right: bool = true,
    };

    pub const JunctionType = enum {
        top_left, // ┌ ╔ ╭ ┏
        top_right, // ┐ ╗ ╮ ┓
        bottom_left, // └ ╚ ╰ ┗
        bottom_right, // ┘ ╝ ╯ ┛
        horizontal, // ─ ═ ━
        vertical, // │ ║ ┃
        cross, // ┼ ╬ ╋
        tee_up, // ┴ ╩ ┻
        tee_down, // ┬ ╦ ┳
        tee_left, // ┤ ╣ ┫
        tee_right, // ├ ╠ ┣
    };

    pub fn init(allocator: std.mem.Allocator) !Merger {
        return .{
            .allocator = allocator,
            .widgets = try std.ArrayList(WidgetBoundary).initCapacity(allocator, 0),
            .merge_map = std.AutoHashMap(Point, JunctionType).init(allocator),
        };
    }

    pub fn deinit(self: *Merger) void {
        self.widgets.deinit(self.allocator);
        self.merge_map.deinit();
    }

    /// Register a widget boundary for merging
    pub fn addWidget(self: *Merger, boundary: WidgetBoundary) !void {
        try self.widgets.append(self.allocator, boundary);
    }

    /// Calculate all junction points where borders should merge
    pub fn calculateMergePoints(self: *Merger) !void {
        self.merge_map.clearRetainingCapacity();

        for (self.widgets.items, 0..) |widget_a, i| {
            for (self.widgets.items[i + 1 ..]) |widget_b| {
                try self.findIntersections(widget_a, widget_b);
            }
        }
    }

    /// Find intersection points between two widget boundaries
    fn findIntersections(self: *Merger, a: WidgetBoundary, b: WidgetBoundary) !void {
        // Check if widgets are adjacent horizontally
        if (a.rect.x + @as(i16, @intCast(a.rect.width)) == b.rect.x) {
            // Right edge of A meets left edge of B
            const y_start = @max(a.rect.y, b.rect.y);
            const y_end = @min(a.rect.y + @as(i16, @intCast(a.rect.height)), b.rect.y + @as(i16, @intCast(b.rect.height)));

            if (y_start < y_end) {
                // They overlap vertically
                var y = y_start;
                while (y < y_end) : (y += 1) {
                    const point = Point{ .x = @as(u32, @intCast(b.rect.x)), .y = @as(u32, @intCast(y)) };
                    const junction_type = self.determineJunctionType(point, a, b);
                    try self.merge_map.put(point, junction_type);
                }
            }
        }

        // Check if widgets are adjacent vertically
        if (a.rect.y + @as(i16, @intCast(a.rect.height)) == b.rect.y) {
            // Bottom edge of A meets top edge of B
            const x_start = @max(a.rect.x, b.rect.x);
            const x_end = @min(a.rect.x + @as(i16, @intCast(a.rect.width)), b.rect.x + @as(i16, @intCast(b.rect.width)));

            if (x_start < x_end) {
                // They overlap horizontally
                var x = x_start;
                while (x < x_end) : (x += 1) {
                    const point = Point{ .x = @as(u32, @intCast(x)), .y = @as(u32, @intCast(b.rect.y)) };
                    const junction_type = self.determineJunctionType(point, a, b);
                    try self.merge_map.put(point, junction_type);
                }
            }
        }

        // Check corner intersections
        try self.checkCornerIntersection(a, b);
    }

    /// Check if widget corners meet and need special junction characters
    fn checkCornerIntersection(self: *Merger, a: WidgetBoundary, b: WidgetBoundary) !void {
        // Check all four corners of each widget
        const corners_a = [_]Point{
            .{ .x = @as(u32, @intCast(a.rect.x)), .y = @as(u32, @intCast(a.rect.y)) }, // top-left
            .{ .x = @as(u32, @intCast(a.rect.x + @as(i16, @intCast(a.rect.width)) - 1)), .y = @as(u32, @intCast(a.rect.y)) }, // top-right
            .{ .x = @as(u32, @intCast(a.rect.x)), .y = @as(u32, @intCast(a.rect.y + @as(i16, @intCast(a.rect.height)) - 1)) }, // bottom-left
            .{ .x = @as(u32, @intCast(a.rect.x + @as(i16, @intCast(a.rect.width)) - 1)), .y = @as(u32, @intCast(a.rect.y + @as(i16, @intCast(a.rect.height)) - 1)) }, // bottom-right
        };

        const corners_b = [_]Point{
            .{ .x = @as(u32, @intCast(b.rect.x)), .y = @as(u32, @intCast(b.rect.y)) },
            .{ .x = @as(u32, @intCast(b.rect.x + @as(i16, @intCast(b.rect.width)) - 1)), .y = @as(u32, @intCast(b.rect.y)) },
            .{ .x = @as(u32, @intCast(b.rect.x)), .y = @as(u32, @intCast(b.rect.y + @as(i16, @intCast(b.rect.height)) - 1)) },
            .{ .x = @as(u32, @intCast(b.rect.x + @as(i16, @intCast(b.rect.width)) - 1)), .y = @as(u32, @intCast(b.rect.y + @as(i16, @intCast(b.rect.height)) - 1)) },
        };

        for (corners_a) |corner_a| {
            for (corners_b) |corner_b| {
                if (corner_a.x == corner_b.x and corner_a.y == corner_b.y) {
                    // Corners meet - determine junction type
                    const junction_type = self.determineCornerJunction(corner_a, a, b);
                    try self.merge_map.put(corner_a, junction_type);
                }
            }
        }
    }

    /// Determine the type of junction needed at a given point
    fn determineJunctionType(self: *Merger, point: Point, a: WidgetBoundary, b: WidgetBoundary) JunctionType {
        _ = self;

        var connections: struct {
            top: bool = false,
            bottom: bool = false,
            left: bool = false,
            right: bool = false,
        } = .{};

        // Check connections from widget A
        if (point.x == @as(u32, @intCast(a.rect.x)) + @as(u32, @intCast(a.rect.width)) - 1 and
            point.y >= @as(u32, @intCast(a.rect.y)) and point.y < @as(u32, @intCast(a.rect.y)) + @as(u32, @intCast(a.rect.height)))
        {
            connections.right = true;
        }
        if (point.x == @as(u32, @intCast(a.rect.x)) and
            point.y >= @as(u32, @intCast(a.rect.y)) and point.y < @as(u32, @intCast(a.rect.y)) + @as(u32, @intCast(a.rect.height)))
        {
            connections.left = true;
        }
        if (point.y == @as(u32, @intCast(a.rect.y)) + @as(u32, @intCast(a.rect.height)) - 1 and
            point.x >= @as(u32, @intCast(a.rect.x)) and point.x < @as(u32, @intCast(a.rect.x)) + @as(u32, @intCast(a.rect.width)))
        {
            connections.bottom = true;
        }
        if (point.y == @as(u32, @intCast(a.rect.y)) and
            point.x >= @as(u32, @intCast(a.rect.x)) and point.x < @as(u32, @intCast(a.rect.x)) + @as(u32, @intCast(a.rect.width)))
        {
            connections.top = true;
        }

        // Check connections from widget B
        if (point.x == @as(u32, @intCast(b.rect.x)) and
            point.y >= @as(u32, @intCast(b.rect.y)) and point.y < @as(u32, @intCast(b.rect.y)) + @as(u32, @intCast(b.rect.height)))
        {
            connections.left = true;
        }
        if (point.x == @as(u32, @intCast(b.rect.x)) + @as(u32, @intCast(b.rect.width)) - 1 and
            point.y >= @as(u32, @intCast(b.rect.y)) and point.y < @as(u32, @intCast(b.rect.y)) + @as(u32, @intCast(b.rect.height)))
        {
            connections.right = true;
        }
        if (point.y == @as(u32, @intCast(b.rect.y)) and
            point.x >= @as(u32, @intCast(b.rect.x)) and point.x < @as(u32, @intCast(b.rect.x)) + @as(u32, @intCast(b.rect.width)))
        {
            connections.top = true;
        }
        if (point.y == @as(u32, @intCast(b.rect.y)) + @as(u32, @intCast(b.rect.height)) - 1 and
            point.x >= @as(u32, @intCast(b.rect.x)) and point.x < @as(u32, @intCast(b.rect.x)) + @as(u32, @intCast(b.rect.width)))
        {
            connections.bottom = true;
        }

        // Map connections to junction type
        const connection_count = @as(u8, @intFromBool(connections.top)) +
            @as(u8, @intFromBool(connections.bottom)) +
            @as(u8, @intFromBool(connections.left)) +
            @as(u8, @intFromBool(connections.right));

        return switch (connection_count) {
            2 => {
                if (connections.left and connections.right) return .horizontal;
                if (connections.top and connections.bottom) return .vertical;
                if (connections.top and connections.left) return .top_left;
                if (connections.top and connections.right) return .top_right;
                if (connections.bottom and connections.left) return .bottom_left;
                if (connections.bottom and connections.right) return .bottom_right;
                return .cross; // fallback
            },
            3 => {
                if (!connections.top) return .tee_up;
                if (!connections.bottom) return .tee_down;
                if (!connections.left) return .tee_left;
                if (!connections.right) return .tee_right;
                return .cross; // fallback
            },
            4 => .cross,
            else => .cross, // fallback
        };
    }

    /// Determine corner junction type
    fn determineCornerJunction(self: *Merger, corner: Point, a: WidgetBoundary, b: WidgetBoundary) JunctionType {
        // TODO: Implement proper corner junction logic
        // For now, simplified implementation that doesn't use all parameters
        _ = self;
        _ = corner;
        _ = a;
        _ = b;

        // Simplified for now - would need more complex logic for all cases
        // This would analyze which edges of each widget meet at this corner
        return .cross;
    }

    /// Get the appropriate character for a junction based on border style
    pub fn getJunctionChar(junction: JunctionType, style: BorderStyle) u21 {
        return switch (style) {
            .single => switch (junction) {
                .top_left => '┌',
                .top_right => '┐',
                .bottom_left => '└',
                .bottom_right => '┘',
                .horizontal => '─',
                .vertical => '│',
                .cross => '┼',
                .tee_up => '┴',
                .tee_down => '┬',
                .tee_left => '┤',
                .tee_right => '├',
            },
            .double => switch (junction) {
                .top_left => '╔',
                .top_right => '╗',
                .bottom_left => '╚',
                .bottom_right => '╝',
                .horizontal => '═',
                .vertical => '║',
                .cross => '╬',
                .tee_up => '╩',
                .tee_down => '╦',
                .tee_left => '╣',
                .tee_right => '╠',
            },
            .rounded => switch (junction) {
                .top_left => '╭',
                .top_right => '╮',
                .bottom_left => '╰',
                .bottom_right => '╯',
                .horizontal => '─',
                .vertical => '│',
                .cross => '┼',
                .tee_up => '┴',
                .tee_down => '┬',
                .tee_left => '┤',
                .tee_right => '├',
            },
            .thick => switch (junction) {
                .top_left => '┏',
                .top_right => '┓',
                .bottom_left => '┗',
                .bottom_right => '┛',
                .horizontal => '━',
                .vertical => '┃',
                .cross => '╋',
                .tee_up => '┻',
                .tee_down => '┳',
                .tee_left => '┫',
                .tee_right => '┣',
            },
            else => '?', // For styles without junction support
        };
    }

    /// Apply border merging to a cell buffer
    pub fn applyMerging(self: *Merger, buffer: *CellBuffer) !void {
        var iter = self.merge_map.iterator();
        while (iter.next()) |entry| {
            const point = entry.key_ptr.*;
            const junction = entry.value_ptr.*;

            // Determine the predominant style at this junction
            // For simplicity, use the first widget's style that touches this point
            var style: BorderStyle = .single;
            for (self.widgets.items) |widget| {
                if (self.pointOnBorder(point, widget)) {
                    style = widget.style;
                    break;
                }
            }

            const char = getJunctionChar(junction, style);
            try buffer.setCell(@intCast(point.x), @intCast(point.y), .{
                .rune = char,
                .style = .{},
            });
        }
    }

    /// Check if a point is on the border of a widget
    fn pointOnBorder(self: *Merger, point: Point, widget: WidgetBoundary) bool {
        _ = self;

        const on_top = point.y == widget.rect.y and
            point.x >= widget.rect.x and
            point.x < widget.rect.x + widget.rect.width;
        const on_bottom = point.y == widget.rect.y + widget.rect.height - 1 and
            point.x >= widget.rect.x and
            point.x < widget.rect.x + widget.rect.width;
        const on_left = point.x == widget.rect.x and
            point.y >= widget.rect.y and
            point.y < widget.rect.y + widget.rect.height;
        const on_right = point.x == widget.rect.x + widget.rect.width - 1 and
            point.y >= widget.rect.y and
            point.y < widget.rect.y + widget.rect.height;

        return on_top or on_bottom or on_left or on_right;
    }

    /// Clear all registered widgets and merge points
    pub fn clear(self: *Merger) void {
        self.widgets.clearRetainingCapacity();
        self.merge_map.clearRetainingCapacity();
    }
};

// Tests would go here...

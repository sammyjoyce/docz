//! Rich Scrollbar widget for terminal interfaces
//! Supports vertical/horizontal orientations, mouse interaction, and multiple styles

const std = @import("std");
const term_shared = @import("term_shared");
const rich_cellbuf = term_shared.cellbuf;
const term_caps = term_shared.caps;

/// Scrollbar orientation
pub const Orientation = enum {
    vertical,
    horizontal,
};

/// Scrollbar visual style
pub const Style = enum {
    modern, // Unicode box-drawing characters with rounded corners
    classic, // Traditional ASCII scrollbar
    minimal, // Simple line-based design
};

/// Rich scrollbar widget with mouse interaction and multiple styles
pub const Scrollbar = struct {
    /// Scrollbar orientation
    orientation: Orientation,
    /// Visual style
    style: Style,
    /// Current scroll position (0.0 to 1.0)
    scroll_position: f64,
    /// Size of the visible thumb (0.0 to 1.0)
    thumb_size: f64,
    /// Whether to show arrow buttons
    show_arrows: bool,
    /// Whether to auto-hide when content fits
    auto_hide: bool,
    /// Terminal capabilities
    caps: term_caps.TermCaps,

    /// Create a new scrollbar
    pub fn init(
        orientation: Orientation,
        style: Style,
    ) Scrollbar {
        return Scrollbar{
            .orientation = orientation,
            .style = style,
            .scroll_position = 0.0,
            .thumb_size = 1.0,
            .show_arrows = false,
            .auto_hide = true,
            .caps = term_caps.getTermCaps(),
        };
    }

    /// Create a vertical scrollbar
    pub fn initVertical(style: Style) Scrollbar {
        return init(.vertical, style);
    }

    /// Create a horizontal scrollbar
    pub fn initHorizontal(style: Style) Scrollbar {
        return init(.horizontal, style);
    }

    /// Set scroll position directly
    pub fn setScrollPosition(self: *Scrollbar, position: f64) void {
        if (position < 0.0) {
            self.scroll_position = 0.0;
        } else if (position > 1.0) {
            self.scroll_position = 1.0;
        } else {
            self.scroll_position = position;
        }
    }

    /// Scroll by a relative amount
    pub fn scrollBy(self: *Scrollbar, delta: f64) void {
        const new_position = std.math.clamp(self.scroll_position + delta, 0.0, 1.0);
        self.setScrollPosition(new_position);
    }

    /// Check if scrollbar should be visible
    pub fn isVisible(self: Scrollbar) bool {
        if (!self.auto_hide) return true;
        return self.thumb_size < 1.0;
    }

    /// Render scrollbar to a cell buffer
    pub fn renderToBuffer(
        self: *Scrollbar,
        buffer: *rich_cellbuf.Buffer,
        x: usize,
        y: usize,
        length: usize,
    ) !void {
        if (!self.isVisible()) return;

        const thumb_start = @as(usize, @intFromFloat(self.scroll_position * @as(f64, @floatFromInt(length - 1))));
        const thumb_end = @as(usize, @intFromFloat((self.scroll_position + self.thumb_size) * @as(f64, @floatFromInt(length - 1))));

        // Render based on orientation and style
        switch (self.orientation) {
            .vertical => try self.renderVertical(buffer, x, y, length, thumb_start, thumb_end),
            .horizontal => try self.renderHorizontal(buffer, x, y, length, thumb_start, thumb_end),
        }
    }

    fn renderVertical(
        self: *Scrollbar,
        buffer: *rich_cellbuf.Buffer,
        x: usize,
        y: usize,
        length: usize,
        thumb_start: usize,
        thumb_end: usize,
    ) !void {
        const supports_unicode = self.caps.supportsTruecolor or self.caps.supports256Color;

        for (0..length) |i| {
            const cell_y = y + i;
            if (cell_y >= buffer.height) continue;

            const is_thumb = i >= thumb_start and i <= thumb_end;
            const cell = try buffer.cell(x, cell_y);

            if (is_thumb) {
                // Render thumb
                try self.renderThumbCell(cell, supports_unicode);
            } else {
                // Render track
                try self.renderTrackCell(cell, .vertical, supports_unicode);
            }
        }

        // Render arrow buttons if enabled
        if (self.show_arrows and length >= 3) {
            // Up arrow
            if (buffer.cell(x, y)) |up_cell| {
                try renderArrowCell(up_cell, .up, supports_unicode);
            }

            // Down arrow
            if (buffer.cell(x, y + length - 1)) |down_cell| {
                try renderArrowCell(down_cell, .down, supports_unicode);
            }
        }
    }

    fn renderHorizontal(
        self: *Scrollbar,
        buffer: *rich_cellbuf.Buffer,
        x: usize,
        y: usize,
        length: usize,
        thumb_start: usize,
        thumb_end: usize,
    ) !void {
        const supports_unicode = self.caps.supportsTruecolor or self.caps.supports256Color;

        for (0..length) |i| {
            const cell_x = x + i;
            if (cell_x >= buffer.width) continue;

            const is_thumb = i >= thumb_start and i <= thumb_end;
            const cell = buffer.cell(cell_x, y) orelse continue;

            if (is_thumb) {
                // Render thumb
                try self.renderThumbCell(cell, supports_unicode);
            } else {
                // Render track
                try self.renderTrackCell(cell, .horizontal, supports_unicode);
            }
        }

        // Render arrow buttons if enabled
        if (self.show_arrows and length >= 3) {
            // Left arrow
            if (buffer.cell(x, y)) |left_cell| {
                try renderArrowCell(left_cell, .left, supports_unicode);
            }

            // Right arrow
            if (buffer.cell(x + length - 1, y)) |right_cell| {
                try renderArrowCell(right_cell, .right, supports_unicode);
            }
        }
    }

    fn renderThumbCell(
        self: *Scrollbar,
        cell: *rich_cellbuf.Cell,
        supports_unicode: bool,
    ) !void {
        const char: u21 = switch (self.style) {
            .modern => if (supports_unicode) {
                '█';
            } else {
                '█';
            },
            .classic => '█',
            .minimal => '│',
        };

        cell.rune = char;
        cell.width = 1;

        // Apply default thumb colors
        cell.style.fg = .{ .basic = .white };
        cell.style.bg = .{ .basic = .blue };
    }

    fn renderTrackCell(
        self: *Scrollbar,
        cell: *rich_cellbuf.Cell,
        orientation: Orientation,
        supports_unicode: bool,
    ) !void {
        const char: u21 = switch (self.style) {
            .modern => if (supports_unicode) {
                switch (orientation) {
                    .vertical => '│',
                    .horizontal => '─',
                }
            } else {
                '|';
            },
            .classic => '|',
            .minimal => ' ',
        };

        cell.rune = char;
        cell.width = 1;

        // Apply default colors
        cell.style.fg = .{ .basic = .black };
        cell.style.bg = .{ .basic = .white };
    }

    fn renderArrowCell(
        cell: *rich_cellbuf.Cell,
        direction: enum { up, down, left, right },
        supports_unicode: bool,
    ) !void {
        const char: u21 = if (supports_unicode) {
            switch (direction) {
                .up => '▲',
                .down => '▼',
                .left => '◀',
                .right => '▶',
            }
        } else {
            switch (direction) {
                .up => '^',
                .down => 'v',
                .left => '<',
                .right => '>',
            }
        };

        cell.rune = char;
        cell.width = 1;

        // Apply default arrow colors
        cell.style.fg = .{ .basic = .cyan };
    }

    /// Get the current scroll position as a value between 0.0 and 1.0
    pub fn getScrollPosition(self: Scrollbar) f64 {
        return self.scroll_position;
    }

    /// Get the thumb size as a ratio (0.0 to 1.0)
    pub fn getThumbSize(self: Scrollbar) f64 {
        return self.thumb_size;
    }

    /// Configure colors (currently a no-op)
    pub fn setColors(self: *Scrollbar, colors: u32) void {
        // Colors not implemented in this simplified version
        _ = self;
        _ = colors;
    }

    /// Enable or disable arrow buttons
    pub fn setShowArrows(self: *Scrollbar, show: bool) void {
        self.show_arrows = show;
    }

    /// Enable or disable auto-hide
    pub fn setAutoHide(self: *Scrollbar, auto_hide: bool) void {
        self.auto_hide = auto_hide;
    }

    /// Get the minimum size needed for the scrollbar
    pub fn getMinimumSize(self: Scrollbar) usize {
        var size: usize = 1; // Minimum track size

        if (self.show_arrows) {
            size += 2; // Space for arrows
        }

        return size;
    }

    /// Clean up resources (currently a no-op, but included for API consistency)
    pub fn deinit(self: *Scrollbar) void {
        // Currently no dynamic resources to clean up
        // Included for API consistency with other widgets
        _ = self;
    }
};

// Convenience functions for common scrollbar configurations
pub fn createVerticalScrollbar() Scrollbar {
    return Scrollbar.initVertical(.modern);
}

pub fn createHorizontalScrollbar() Scrollbar {
    return Scrollbar.initHorizontal(.modern);
}

pub fn createClassicVerticalScrollbar() Scrollbar {
    return Scrollbar.initVertical(.classic);
}

pub fn createMinimalScrollbar(orientation: Orientation) Scrollbar {
    return Scrollbar.init(orientation, .minimal);
}

// Test functions
test "scrollbar initialization" {
    const testing = std.testing;

    var scrollbar = Scrollbar.initVertical(.modern);
    defer scrollbar.deinit();

    try testing.expect(scrollbar.orientation == .vertical);
    try testing.expect(scrollbar.style == .modern);
    try testing.expect(scrollbar.scroll_position == 0.0);
    try testing.expect(scrollbar.thumb_size == 1.0);
}

test "scrollbar position setting" {
    const testing = std.testing;

    var scrollbar = Scrollbar.initHorizontal(.classic);
    defer scrollbar.deinit();

    scrollbar.setScrollPosition(0.5);
    try testing.expect(scrollbar.getScrollPosition() == 0.5);

    // Test clamping
    scrollbar.setScrollPosition(1.5);
    try testing.expect(scrollbar.getScrollPosition() == 1.0);

    scrollbar.setScrollPosition(-0.5);
    try testing.expect(scrollbar.getScrollPosition() == 0.0);
}

//! Calendar widget for TUI applications
//! Provides interactive date selection with month/year navigation,
//! date ranges, event markers, and customizable styles.

const std = @import("std");
const term_ansi = @import("../../../term/ansi/color.zig");
const terminal_cursor = @import("../../components/terminal_cursor.zig");
const input_mod = @import("../../../components/input.zig");
const print = std.debug.print;

/// Date representation
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn init(year: u16, month: u8, day: u8) Date {
        return Date{
            .year = year,
            .month = month,
            .day = day,
        };
    }

    pub fn equals(self: Date, other: Date) bool {
        return self.year == other.year and
            self.month == other.month and
            self.day == other.day;
    }

    pub fn compare(self: Date, other: Date) std.math.Order {
        if (self.year != other.year) {
            return std.math.order(self.year, other.year);
        }
        if (self.month != other.month) {
            return std.math.order(self.month, other.month);
        }
        return std.math.order(self.day, other.day);
    }

    pub fn isValid(self: Date) bool {
        if (self.month < 1 or self.month > 12) return false;
        if (self.day < 1) return false;
        const days = getDaysInMonth(self.year, self.month);
        return self.day <= days;
    }

    pub fn format(self: Date, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:04}-{d:02}-{d:02}", .{
            self.year,
            self.month,
            self.day,
        });
    }
};

/// Date range for selection
pub const DateRange = struct {
    start: Date,
    end: Date,

    pub fn init(start: Date, end: Date) DateRange {
        if (start.compare(end) == .gt) {
            return DateRange{ .start = end, .end = start };
        }
        return DateRange{ .start = start, .end = end };
    }

    pub fn contains(self: DateRange, date: Date) bool {
        return date.compare(self.start) != .lt and
            date.compare(self.end) != .gt;
    }
};

/// Event marker for specific dates
pub const EventMarker = struct {
    date: Date,
    symbol: []const u8,
    color: term_ansi.Color,
    description: ?[]const u8,

    pub fn init(date: Date, symbol: []const u8) EventMarker {
        return EventMarker{
            .date = date,
            .symbol = symbol,
            .color = term_ansi.Color.Blue,
            .description = null,
        };
    }

    pub fn withColor(self: EventMarker, color: term_ansi.Color) EventMarker {
        return EventMarker{
            .date = self.date,
            .symbol = self.symbol,
            .color = color,
            .description = self.description,
        };
    }

    pub fn withDescription(self: EventMarker, desc: []const u8) EventMarker {
        return EventMarker{
            .date = self.date,
            .symbol = self.symbol,
            .color = self.color,
            .description = desc,
        };
    }
};

/// Day of week enum
pub const DayOfWeek = enum(u8) {
    Sunday = 0,
    Monday = 1,
    Tuesday = 2,
    Wednesday = 3,
    Thursday = 4,
    Friday = 5,
    Saturday = 6,
};

/// Calendar display style configuration
pub const CalendarStyle = struct {
    // Colors for different date states
    normal_color: term_ansi.Color,
    selected_color: term_ansi.Color,
    today_color: term_ansi.Color,
    marked_color: term_ansi.Color,
    range_color: term_ansi.Color,
    weekend_color: term_ansi.Color,
    disabled_color: term_ansi.Color,
    header_color: term_ansi.Color,

    // Symbols
    selected_marker: []const u8,
    today_marker: []const u8,
    range_start_marker: []const u8,
    range_end_marker: []const u8,

    // Layout
    show_week_numbers: bool,
    show_header: bool,
    compact_mode: bool,

    pub fn default() CalendarStyle {
        return CalendarStyle{
            .normal_color = term_ansi.Color.Default,
            .selected_color = term_ansi.Color.Cyan,
            .today_color = term_ansi.Color.Green,
            .marked_color = term_ansi.Color.Yellow,
            .range_color = term_ansi.Color.Blue,
            .weekend_color = term_ansi.Color.BrightBlack,
            .disabled_color = term_ansi.Color.Black,
            .header_color = term_ansi.Color.BrightWhite,
            .selected_marker = "▸",
            .today_marker = "●",
            .range_start_marker = "[",
            .range_end_marker = "]",
            .show_week_numbers = false,
            .show_header = true,
            .compact_mode = false,
        };
    }
};

/// Selection mode
pub const SelectionMode = enum {
    single, // Select single date
    range, // Select date range
    multiple, // Select multiple dates
};

/// Calendar widget state
pub const Calendar = struct {
    allocator: std.mem.Allocator,

    // Current view
    current_month: u8,
    current_year: u16,

    // Selection
    selection_mode: SelectionMode,
    selected_date: ?Date,
    selected_range: ?DateRange,
    selected_dates: std.ArrayList(Date),
    hover_date: ?Date,

    // Marked dates and events
    marked_dates: std.ArrayList(Date),
    event_markers: std.ArrayList(EventMarker),

    // Configuration
    week_start: DayOfWeek,
    style: CalendarStyle,
    min_date: ?Date,
    max_date: ?Date,

    // Position and size
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    // Focus state
    focused: bool,
    visible: bool,

    pub fn init(allocator: std.mem.Allocator) !Calendar {
        const now = std.time.timestamp();
        const epoch_seconds = @as(u64, @intCast(now));
        const epoch_day = @divTrunc(epoch_seconds, 86400);

        // Simple date calculation (approximate)
        const years_since_1970 = @divTrunc(epoch_day, 365);
        const current_year = @as(u16, @intCast(1970 + years_since_1970));
        const current_month = @as(u8, @intCast(@mod(@divTrunc(epoch_day, 30), 12) + 1));

        return Calendar{
            .allocator = allocator,
            .current_month = current_month,
            .current_year = current_year,
            .selection_mode = .single,
            .selected_date = null,
            .selected_range = null,
            .selected_dates = std.ArrayList(Date).init(allocator),
            .hover_date = null,
            .marked_dates = std.ArrayList(Date).init(allocator),
            .event_markers = std.ArrayList(EventMarker).init(allocator),
            .week_start = .Sunday,
            .style = CalendarStyle.default(),
            .min_date = null,
            .max_date = null,
            .x = 0,
            .y = 0,
            .width = 28,
            .height = 10,
            .focused = false,
            .visible = true,
        };
    }

    pub fn deinit(self: *Calendar) void {
        self.selected_dates.deinit();
        self.marked_dates.deinit();
        self.event_markers.deinit();
    }

    /// Set the current view to a specific month/year
    pub fn setCurrentView(self: *Calendar, year: u16, month: u8) void {
        if (month >= 1 and month <= 12) {
            self.current_year = year;
            self.current_month = month;
        }
    }

    /// Navigate to previous month
    pub fn previousMonth(self: *Calendar) void {
        if (self.current_month == 1) {
            self.current_month = 12;
            if (self.current_year > 0) self.current_year -= 1;
        } else {
            self.current_month -= 1;
        }
    }

    /// Navigate to next month
    pub fn nextMonth(self: *Calendar) void {
        if (self.current_month == 12) {
            self.current_month = 1;
            if (self.current_year < 9999) self.current_year += 1;
        } else {
            self.current_month += 1;
        }
    }

    /// Navigate to previous year
    pub fn previousYear(self: *Calendar) void {
        if (self.current_year > 0) self.current_year -= 1;
    }

    /// Navigate to next year
    pub fn nextYear(self: *Calendar) void {
        if (self.current_year < 9999) self.current_year += 1;
    }

    /// Select a date
    pub fn selectDate(self: *Calendar, date: Date) !void {
        if (!self.isDateSelectable(date)) return;

        switch (self.selection_mode) {
            .single => {
                self.selected_date = date;
            },
            .range => {
                if (self.selected_range) |*range| {
                    // Complete the range
                    range.end = date;
                    if (date.compare(range.start) == .lt) {
                        const temp = range.start;
                        range.start = date;
                        range.end = temp;
                    }
                } else if (self.selected_date) |start| {
                    // Start a new range
                    self.selected_range = DateRange.init(start, date);
                    self.selected_date = null;
                } else {
                    // Begin range selection
                    self.selected_date = date;
                }
            },
            .multiple => {
                // Toggle date in selection
                var found_index: ?usize = null;
                for (self.selected_dates.items, 0..) |d, i| {
                    if (d.equals(date)) {
                        found_index = i;
                        break;
                    }
                }

                if (found_index) |index| {
                    _ = self.selected_dates.orderedRemove(index);
                } else {
                    try self.selected_dates.append(date);
                }
            },
        }
    }

    /// Check if a date is selectable
    pub fn isDateSelectable(self: Calendar, date: Date) bool {
        if (self.min_date) |min| {
            if (date.compare(min) == .lt) return false;
        }
        if (self.max_date) |max| {
            if (date.compare(max) == .gt) return false;
        }
        return true;
    }

    /// Add an event marker
    pub fn addEventMarker(self: *Calendar, marker: EventMarker) !void {
        try self.event_markers.append(marker);
    }

    /// Mark a date
    pub fn markDate(self: *Calendar, date: Date) !void {
        for (self.marked_dates.items) |d| {
            if (d.equals(date)) return; // Already marked
        }
        try self.marked_dates.append(date);
    }

    /// Clear all selections
    pub fn clearSelection(self: *Calendar) void {
        self.selected_date = null;
        self.selected_range = null;
        self.selected_dates.clearRetainingCapacity();
    }

    /// Handle keyboard input
    pub fn handleKeyPress(self: *Calendar, key: input_mod.InputEvent.KeyPressEvent) !bool {
        if (!self.focused or !self.visible) return false;

        const current_hover = self.hover_date orelse Date.init(
            self.current_year,
            self.current_month,
            1,
        );

        switch (key) {
            .arrow_left => {
                // Move to previous day
                var new_day = current_hover.day;
                if (new_day > 1) {
                    new_day -= 1;
                } else {
                    self.previousMonth();
                    new_day = getDaysInMonth(self.current_year, self.current_month);
                }
                self.hover_date = Date.init(self.current_year, self.current_month, new_day);
                return true;
            },
            .arrow_right => {
                // Move to next day
                var new_day = current_hover.day;
                const days_in_month = getDaysInMonth(self.current_year, self.current_month);
                if (new_day < days_in_month) {
                    new_day += 1;
                } else {
                    self.nextMonth();
                    new_day = 1;
                }
                self.hover_date = Date.init(self.current_year, self.current_month, new_day);
                return true;
            },
            .arrow_up => {
                // Move to previous week
                var new_day = current_hover.day;
                if (new_day > 7) {
                    new_day -= 7;
                } else {
                    self.previousMonth();
                    const days_in_prev = getDaysInMonth(self.current_year, self.current_month);
                    new_day = days_in_prev - (7 - new_day);
                }
                self.hover_date = Date.init(self.current_year, self.current_month, new_day);
                return true;
            },
            .arrow_down => {
                // Move to next week
                var new_day = current_hover.day;
                const days_in_month = getDaysInMonth(self.current_year, self.current_month);
                if (new_day + 7 <= days_in_month) {
                    new_day += 7;
                } else {
                    self.nextMonth();
                    new_day = 7 - (days_in_month - new_day);
                }
                self.hover_date = Date.init(self.current_year, self.current_month, new_day);
                return true;
            },
            .page_up => {
                // Previous month
                self.previousMonth();
                return true;
            },
            .page_down => {
                // Next month
                self.nextMonth();
                return true;
            },
            .home => {
                // First day of month
                self.hover_date = Date.init(self.current_year, self.current_month, 1);
                return true;
            },
            .end => {
                // Last day of month
                const days = getDaysInMonth(self.current_year, self.current_month);
                self.hover_date = Date.init(self.current_year, self.current_month, days);
                return true;
            },
            .enter, .space => {
                // Select current hover date
                if (self.hover_date) |date| {
                    try self.selectDate(date);
                }
                return true;
            },
            .escape => {
                // Clear selection or lose focus
                if (self.selected_date != null or self.selected_range != null or self.selected_dates.items.len > 0) {
                    self.clearSelection();
                } else {
                    self.focused = false;
                }
                return true;
            },
            .char => |c| {
                switch (c) {
                    't', 'T' => {
                        // Jump to today
                        const now = std.time.timestamp();
                        const epoch_seconds = @as(u64, @intCast(now));
                        const epoch_day = @divTrunc(epoch_seconds, 86400);
                        const years_since_1970 = @divTrunc(epoch_day, 365);
                        const year = @as(u16, @intCast(1970 + years_since_1970));
                        const month = @as(u8, @intCast(@mod(@divTrunc(epoch_day, 30), 12) + 1));
                        const day = @as(u8, @intCast(@mod(epoch_day, 30) + 1));

                        self.setCurrentView(year, month);
                        self.hover_date = Date.init(year, month, day);
                        return true;
                    },
                    'n', 'N' => {
                        // Next month
                        self.nextMonth();
                        return true;
                    },
                    'p', 'P' => {
                        // Previous month
                        self.previousMonth();
                        return true;
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    /// Handle mouse input
    pub fn handleMouseEvent(self: *Calendar, x: u16, y: u16, button: input_mod.MouseButton) !bool {
        if (!self.visible) return false;

        // Check if click is within calendar bounds
        if (x < self.x or x >= self.x + self.width or
            y < self.y or y >= self.y + self.height)
        {
            return false;
        }

        // Calculate relative position
        const rel_x = x - self.x;
        const rel_y = y - self.y;

        // Check if clicking on navigation buttons (in header)
        if (self.style.show_header and rel_y == 0) {
            if (rel_x < 3) {
                // Previous month button
                self.previousMonth();
                return true;
            } else if (rel_x >= self.width - 3) {
                // Next month button
                self.nextMonth();
                return true;
            }
        }

        // Calculate which day was clicked
        const calendar_start_y = if (self.style.show_header) @as(u16, 3) else @as(u16, 1);
        if (rel_y >= calendar_start_y) {
            const week = (rel_y - calendar_start_y) / 2; // Assuming 2 rows per week
            const day_of_week = rel_x / 4; // Assuming 4 chars per day

            if (week < 6 and day_of_week < 7) {
                const first_day = getFirstDayOfMonth(self.current_year, self.current_month);
                const day_offset = @as(u8, @intCast(day_of_week));
                const week_offset = @as(u8, @intCast(week * 7));

                const day = week_offset + day_offset - @intFromEnum(first_day) + 1;
                const days_in_month = getDaysInMonth(self.current_year, self.current_month);

                if (day >= 1 and day <= days_in_month) {
                    const date = Date.init(self.current_year, self.current_month, @as(u8, @intCast(day)));

                    switch (button) {
                        .left => {
                            self.hover_date = date;
                            try self.selectDate(date);
                            self.focused = true;
                        },
                        .right => {
                            // Right click could show context menu or clear selection
                            self.hover_date = date;
                        },
                        else => {},
                    }
                    return true;
                }
            }
        }

        return false;
    }

    /// Render the calendar
    pub fn render(self: *Calendar, writer: anytype) !void {
        if (!self.visible) return;

        const save_cursor = "\x1b[s";
        const restore_cursor = "\x1b[u";

        try writer.print("{s}", .{save_cursor});

        var current_y = self.y;

        // Render header if enabled
        if (self.style.show_header) {
            try self.renderHeader(writer, current_y);
            current_y += 2;
            try self.renderWeekDays(writer, current_y);
            current_y += 1;
        }

        // Render calendar days
        try self.renderDays(writer, current_y);

        try writer.print("{s}", .{restore_cursor});
    }

    fn renderHeader(self: *Calendar, writer: anytype, y: u16) !void {
        // Move to position
        try writer.print("\x1b[{d};{d}H", .{ y + 1, self.x + 1 });

        // Navigation and month/year display
        try term_ansi.setForeground(writer, self.style.header_color);

        const month_names = [_][]const u8{
            "January", "February", "March",     "April",   "May",      "June",
            "July",    "August",   "September", "October", "November", "December",
        };

        const month_name = month_names[self.current_month - 1];

        // Left arrow
        try writer.print("◀ ", .{});

        // Center the month and year
        const header = try std.fmt.allocPrint(self.allocator, "{s} {d}", .{ month_name, self.current_year });
        defer self.allocator.free(header);

        const padding = (self.width - 4 - header.len) / 2;

        var i: usize = 0;
        while (i < padding) : (i += 1) {
            try writer.print(" ", .{});
        }

        try writer.print("{s}", .{header});

        i = 0;
        while (i < padding) : (i += 1) {
            try writer.print(" ", .{});
        }

        // Right arrow
        try writer.print(" ▶", .{});

        try term_ansi.reset(writer);
    }

    fn renderWeekDays(self: *Calendar, writer: anytype, y: u16) !void {
        try writer.print("\x1b[{d};{d}H", .{ y + 1, self.x + 1 });

        const day_labels = if (self.week_start == .Sunday)
            [_][]const u8{ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
        else
            [_][]const u8{ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" };

        try term_ansi.setForeground(writer, self.style.header_color);

        for (day_labels) |label| {
            try writer.print("{s}  ", .{label});
        }

        try term_ansi.reset(writer);
    }

    fn renderDays(self: *Calendar, writer: anytype, start_y: u16) !void {
        const days_in_month = getDaysInMonth(self.current_year, self.current_month);
        const first_day = getFirstDayOfMonth(self.current_year, self.current_month);

        // Adjust for week start preference
        var start_offset = @intFromEnum(first_day);
        if (self.week_start == .Monday) {
            start_offset = if (start_offset == 0) 6 else start_offset - 1;
        }

        var current_day: u8 = 1;
        var week_row: u16 = 0;

        // Get today's date for highlighting
        const now = std.time.timestamp();
        const epoch_seconds = @as(u64, @intCast(now));
        const epoch_day = @divTrunc(epoch_seconds, 86400);
        const years_since_1970 = @divTrunc(epoch_day, 365);
        const today_year = @as(u16, @intCast(1970 + years_since_1970));
        const today_month = @as(u8, @intCast(@mod(@divTrunc(epoch_day, 30), 12) + 1));
        const today_day = @as(u8, @intCast(@mod(epoch_day, 30) + 1));
        const today = Date.init(today_year, today_month, today_day);

        while (current_day <= days_in_month) {
            try writer.print("\x1b[{d};{d}H", .{ start_y + week_row + 1, self.x + 1 });

            var day_of_week: usize = 0;
            while (day_of_week < 7) : (day_of_week += 1) {
                if (week_row == 0 and day_of_week < start_offset) {
                    // Empty cell before first day
                    try writer.print("    ", .{});
                } else if (current_day <= days_in_month) {
                    const date = Date.init(self.current_year, self.current_month, current_day);

                    // Determine style for this date
                    var color = self.style.normal_color;
                    var prefix: []const u8 = " ";
                    var suffix: []const u8 = " ";

                    // Check if weekend
                    const is_weekend = (self.week_start == .Sunday and (day_of_week == 0 or day_of_week == 6)) or
                        (self.week_start == .Monday and (day_of_week == 5 or day_of_week == 6));
                    if (is_weekend) {
                        color = self.style.weekend_color;
                    }

                    // Check if today
                    if (date.equals(today)) {
                        color = self.style.today_color;
                        prefix = self.style.today_marker;
                    }

                    // Check if selected
                    if (self.selected_date) |sel| {
                        if (date.equals(sel)) {
                            color = self.style.selected_color;
                            prefix = self.style.selected_marker;
                        }
                    }

                    // Check if in range
                    if (self.selected_range) |range| {
                        if (range.contains(date)) {
                            color = self.style.range_color;
                            if (date.equals(range.start)) {
                                prefix = self.style.range_start_marker;
                            } else if (date.equals(range.end)) {
                                suffix = self.style.range_end_marker;
                            }
                        }
                    }

                    // Check if in multiple selection
                    for (self.selected_dates.items) |sel| {
                        if (date.equals(sel)) {
                            color = self.style.selected_color;
                            prefix = self.style.selected_marker;
                            break;
                        }
                    }

                    // Check if marked
                    for (self.marked_dates.items) |marked| {
                        if (date.equals(marked)) {
                            color = self.style.marked_color;
                            break;
                        }
                    }

                    // Check for event markers
                    var has_event = false;
                    for (self.event_markers.items) |marker| {
                        if (marker.date.equals(date)) {
                            has_event = true;
                            color = marker.color;
                            suffix = marker.symbol;
                            break;
                        }
                    }

                    // Check if hovering
                    if (self.hover_date) |hover| {
                        if (date.equals(hover) and self.focused) {
                            try term_ansi.setBold(writer, true);
                        }
                    }

                    // Check if disabled
                    if (!self.isDateSelectable(date)) {
                        color = self.style.disabled_color;
                    }

                    // Render the day
                    try term_ansi.setForeground(writer, color);
                    try writer.print("{s}{d:2}{s} ", .{ prefix, current_day, suffix });
                    try term_ansi.reset(writer);

                    current_day += 1;
                } else {
                    // Empty cell after last day
                    try writer.print("    ", .{});
                }
            }

            week_row += 1;
            if (week_row >= 6) break; // Maximum 6 weeks display
        }
    }
};

// Helper functions

fn getDaysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

fn getFirstDayOfMonth(year: u16, month: u8) DayOfWeek {
    // Zeller's congruence for Gregorian calendar
    var y = @as(i32, year);
    var m = @as(i32, month);

    if (m < 3) {
        m += 12;
        y -= 1;
    }

    const k = @mod(y, 100);
    const j = @divTrunc(y, 100);

    const h = @mod(1 + @divTrunc(13 * (m + 1), 5) + k + @divTrunc(k, 4) + @divTrunc(j, 4) - 2 * j, 7);

    // Convert to our DayOfWeek enum (0 = Sunday)
    const day_map = [_]DayOfWeek{
        .Saturday, // h = 0
        .Sunday, // h = 1
        .Monday, // h = 2
        .Tuesday, // h = 3
        .Wednesday, // h = 4
        .Thursday, // h = 5
        .Friday, // h = 6
    };

    return day_map[@as(usize, @intCast(@mod(h, 7)))];
}

// Tests
test "Date comparison" {
    const d1 = Date.init(2024, 1, 15);
    const d2 = Date.init(2024, 1, 20);
    const d3 = Date.init(2024, 1, 15);

    try std.testing.expect(d1.equals(d3));
    try std.testing.expect(!d1.equals(d2));
    try std.testing.expect(d1.compare(d2) == .lt);
    try std.testing.expect(d2.compare(d1) == .gt);
    try std.testing.expect(d1.compare(d3) == .eq);
}

test "Date validation" {
    try std.testing.expect(Date.init(2024, 2, 29).isValid()); // Leap year
    try std.testing.expect(!Date.init(2023, 2, 29).isValid()); // Not leap year
    try std.testing.expect(!Date.init(2024, 13, 1).isValid()); // Invalid month
    try std.testing.expect(!Date.init(2024, 4, 31).isValid()); // April has 30 days
}

test "DateRange contains" {
    const range = DateRange.init(
        Date.init(2024, 1, 10),
        Date.init(2024, 1, 20),
    );

    try std.testing.expect(range.contains(Date.init(2024, 1, 15)));
    try std.testing.expect(range.contains(Date.init(2024, 1, 10)));
    try std.testing.expect(range.contains(Date.init(2024, 1, 20)));
    try std.testing.expect(!range.contains(Date.init(2024, 1, 9)));
    try std.testing.expect(!range.contains(Date.init(2024, 1, 21)));
}

test "Calendar initialization" {
    const allocator = std.testing.allocator;
    var calendar = try Calendar.init(allocator);
    defer calendar.deinit();

    try std.testing.expect(calendar.current_month >= 1 and calendar.current_month <= 12);
    try std.testing.expect(calendar.current_year >= 2020);
    try std.testing.expect(calendar.selection_mode == .single);
}

test "Calendar navigation" {
    const allocator = std.testing.allocator;
    var calendar = try Calendar.init(allocator);
    defer calendar.deinit();

    calendar.setCurrentView(2024, 12);
    calendar.nextMonth();
    try std.testing.expect(calendar.current_month == 1);
    try std.testing.expect(calendar.current_year == 2025);

    calendar.previousMonth();
    try std.testing.expect(calendar.current_month == 12);
    try std.testing.expect(calendar.current_year == 2024);
}

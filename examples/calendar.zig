//! Calendar widget demo
//! Shows how to use the calendar widget with various features

const std = @import("std");
const tui_widgets = @import("../src/shared/tui/widgets/mod.zig");
const Calendar = tui_widgets.core.Calendar;
const Date = tui_widgets.core.Date;
const EventMarker = tui_widgets.core.EventMarker;
const CalendarStyle = tui_widgets.core.CalendarStyle;
const term_ansi = @import("../src/shared/term/ansi/color.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize calendar
    var calendar = try Calendar.init(allocator);
    defer calendar.deinit();

    // Configure calendar
    calendar.x = 5;
    calendar.y = 2;
    calendar.width = 30;
    calendar.height = 12;
    calendar.focused = true;
    calendar.visible = true;

    // Set custom style
    calendar.style = CalendarStyle{
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

    // Set to current date (January 2024 for demo)
    calendar.setCurrentView(2024, 1);

    // Add some marked dates
    try calendar.markDate(Date.init(2024, 1, 15));
    try calendar.markDate(Date.init(2024, 1, 22));

    // Add event markers
    try calendar.addEventMarker(
        EventMarker.init(Date.init(2024, 1, 5), "!")
            .withColor(term_ansi.Color.Red)
            .withDescription("Important meeting"),
    );
    try calendar.addEventMarker(
        EventMarker.init(Date.init(2024, 1, 10), "*")
            .withColor(term_ansi.Color.Blue)
            .withDescription("Birthday"),
    );
    try calendar.addEventMarker(
        EventMarker.init(Date.init(2024, 1, 25), "○")
            .withColor(term_ansi.Color.Green)
            .withDescription("Project deadline"),
    );

    // Set min/max dates (optional)
    calendar.min_date = Date.init(2023, 1, 1);
    calendar.max_date = Date.init(2025, 12, 31);

    // Clear screen
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1b[2J\x1b[H", .{});

    // Print instructions
    try stdout.print("Calendar Widget Demo\n", .{});
    try stdout.print("====================\n\n", .{});
    try stdout.print("Navigation:\n", .{});
    try stdout.print("  ← → ↑ ↓  : Navigate days\n", .{});
    try stdout.print("  PgUp/PgDn: Previous/Next month\n", .{});
    try stdout.print("  Home/End : First/Last day of month\n", .{});
    try stdout.print("  Space    : Select date\n", .{});
    try stdout.print("  T        : Jump to today\n", .{});
    try stdout.print("  N/P      : Next/Previous month\n", .{});
    try stdout.print("  ESC      : Clear selection/Exit\n", .{});
    try stdout.print("  Q        : Quit\n\n", .{});

    // Demo different selection modes
    try stdout.print("Selection modes demo:\n\n", .{});

    // Single selection mode
    try stdout.print("1. Single date selection:\n", .{});
    calendar.selection_mode = .single;
    calendar.selected_date = Date.init(2024, 1, 15);
    try calendar.render(stdout);

    try stdout.print("\n\n2. Range selection:\n", .{});
    calendar.selection_mode = .range;
    calendar.selected_date = null;
    calendar.selected_range = .{
        .start = Date.init(2024, 1, 10),
        .end = Date.init(2024, 1, 20),
    };
    try calendar.render(stdout);

    try stdout.print("\n\n3. Multiple selection:\n", .{});
    calendar.selection_mode = .multiple;
    calendar.selected_range = null;
    try calendar.selected_dates.append(Date.init(2024, 1, 5));
    try calendar.selected_dates.append(Date.init(2024, 1, 12));
    try calendar.selected_dates.append(Date.init(2024, 1, 18));
    try calendar.selected_dates.append(Date.init(2024, 1, 25));
    try calendar.render(stdout);

    // Show different week start options
    try stdout.print("\n\n4. Week starting on Monday:\n", .{});
    calendar.week_start = .Monday;
    try calendar.render(stdout);

    try stdout.print("\n\nPress Enter to continue interactive demo...", .{});
    _ = try std.io.getStdIn().reader().readByte();

    // Clear and start interactive mode
    try stdout.print("\x1b[2J\x1b[H", .{});
    calendar.clearSelection();
    calendar.selection_mode = .single;
    calendar.week_start = .Sunday;

    // Interactive loop (simplified - would need proper input handling in production)
    try stdout.print("Interactive Calendar (press 'q' to quit)\n\n", .{});
    
    var running = true;
    while (running) {
        // Clear and redraw
        try stdout.print("\x1b[3;1H\x1b[J", .{}); // Clear from line 3 down
        try calendar.render(stdout);

        // Show current selection info
        try stdout.print("\n\nCurrent selection: ", .{});
        if (calendar.selected_date) |date| {
            const date_str = try date.format(allocator);
            defer allocator.free(date_str);
            try stdout.print("{s}", .{date_str});
        } else if (calendar.selected_range) |range| {
            const start_str = try range.start.format(allocator);
            defer allocator.free(start_str);
            const end_str = try range.end.format(allocator);
            defer allocator.free(end_str);
            try stdout.print("{s} to {s}", .{ start_str, end_str });
        } else if (calendar.selected_dates.items.len > 0) {
            for (calendar.selected_dates.items, 0..) |date, i| {
                if (i > 0) try stdout.print(", ", .{});
                const date_str = try date.format(allocator);
                defer allocator.free(date_str);
                try stdout.print("{s}", .{date_str});
            }
        } else {
            try stdout.print("None", .{});
        }

        try stdout.print("\n\n> ", .{});

        // Simple input handling (production code would use proper terminal input)
        const input = try std.io.getStdIn().reader().readByte();
        switch (input) {
            'q', 'Q' => running = false,
            'n', 'N' => calendar.nextMonth(),
            'p', 'P' => calendar.previousMonth(),
            ' ' => {
                // Select current hover date or first of month
                const date = calendar.hover_date orelse Date.init(
                    calendar.current_year,
                    calendar.current_month,
                    1,
                );
                try calendar.selectDate(date);
            },
            'c', 'C' => calendar.clearSelection(),
            '1' => calendar.selection_mode = .single,
            '2' => calendar.selection_mode = .range,
            '3' => calendar.selection_mode = .multiple,
            else => {},
        }
    }

    // Clear screen on exit
    try stdout.print("\x1b[2J\x1b[H", .{});
    try stdout.print("Calendar demo completed!\n", .{});
}
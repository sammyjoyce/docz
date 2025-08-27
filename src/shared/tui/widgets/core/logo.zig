//! Logo widget for displaying ASCII art or styled text logos
//! Supports multiple logo styles, colors, and optional animation

const std = @import("std");
const Bounds = @import("../../core/bounds.zig").Bounds;
const Color = @import("../../themes/default.zig").ColorEnum;
const print = @import("../../../term/writer.zig").print;

/// Logo display style
pub const LogoStyle = enum {
    ascii_art, // Multi-line ASCII art
    styled_text, // Styled single or multi-line text
    banner, // Banner-style with borders
    figlet, // Figlet-style large text
};

/// Text alignment within the logo bounds
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Logo widget for displaying branding or visual elements
pub const Logo = struct {
    // Content
    lines: []const []const u8,

    // Configuration
    bounds: Bounds,
    style: LogoStyle,
    alignment: Alignment,
    color: Color,
    background_color: ?Color,
    border: bool,
    padding: u8,

    // State
    current_frame: usize,
    animation_frames: ?[]const []const []const u8,
    animation_speed_ms: u32,
    last_update_time: ?i64,

    // Dependencies
    allocator: std.mem.Allocator,

    /// Initialize a new Logo widget with ASCII art or text
    pub fn init(allocator: std.mem.Allocator, bounds: Bounds, content: []const u8) !Logo {
        // Split content into lines
        var lines_list = std.ArrayList([]const u8).init(allocator);
        defer lines_list.deinit();

        var it = std.mem.tokenize(u8, content, "\n");
        while (it.next()) |line| {
            try lines_list.append(line);
        }

        const lines = try allocator.alloc([]const u8, lines_list.items.len);
        for (lines_list.items, 0..) |line, i| {
            lines[i] = try allocator.dupe(u8, line);
        }

        return Logo{
            .lines = lines,
            .bounds = bounds,
            .style = .ascii_art,
            .alignment = .center,
            .color = Color.bright_cyan,
            .background_color = null,
            .border = false,
            .padding = 1,
            .current_frame = 0,
            .animation_frames = null,
            .animation_speed_ms = 100,
            .last_update_time = null,
            .allocator = allocator,
        };
    }

    /// Initialize with animation frames
    pub fn initAnimated(allocator: std.mem.Allocator, bounds: Bounds, frames: []const []const u8, speed_ms: u32) !Logo {
        if (frames.len == 0) return error.NoFrames;

        // Parse all frames
        const animation_frames = try allocator.alloc([]const []const []const u8, frames.len);
        for (frames, 0..) |frame_content, i| {
            var lines_list = std.ArrayList([]const u8).init(allocator);
            defer lines_list.deinit();

            var it = std.mem.tokenize(u8, frame_content, "\n");
            while (it.next()) |line| {
                try lines_list.append(try allocator.dupe(u8, line));
            }

            animation_frames[i] = try allocator.dupe([]const u8, lines_list.items);
        }

        return Logo{
            .lines = animation_frames[0],
            .bounds = bounds,
            .style = .ascii_art,
            .alignment = .center,
            .color = Color.bright_cyan,
            .background_color = null,
            .border = false,
            .padding = 1,
            .current_frame = 0,
            .animation_frames = animation_frames,
            .animation_speed_ms = speed_ms,
            .last_update_time = null,
            .allocator = allocator,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *Logo) void {
        for (self.lines) |line| {
            self.allocator.free(line);
        }
        self.allocator.free(self.lines);

        if (self.animation_frames) |frames| {
            for (frames) |frame| {
                for (frame) |line| {
                    self.allocator.free(line);
                }
                self.allocator.free(frame);
            }
            self.allocator.free(frames);
        }
    }

    /// Set the logo style
    pub fn withStyle(self: Logo, style: LogoStyle) Logo {
        var new_logo = self;
        new_logo.style = style;
        return new_logo;
    }

    /// Set the text alignment
    pub fn withAlignment(self: Logo, alignment: Alignment) Logo {
        var new_logo = self;
        new_logo.alignment = alignment;
        return new_logo;
    }

    /// Set the foreground color
    pub fn withColor(self: Logo, color: Color) Logo {
        var new_logo = self;
        new_logo.color = color;
        return new_logo;
    }

    /// Set the background color
    pub fn withBackground(self: Logo, color: Color) Logo {
        var new_logo = self;
        new_logo.background_color = color;
        return new_logo;
    }

    /// Enable or disable border
    pub fn withBorder(self: Logo, border: bool) Logo {
        var new_logo = self;
        new_logo.border = border;
        return new_logo;
    }

    /// Set padding around the logo
    pub fn withPadding(self: Logo, padding: u8) Logo {
        var new_logo = self;
        new_logo.padding = padding;
        return new_logo;
    }

    /// Update animation frame if animated
    pub fn update(self: *Logo, current_time_ms: i64) void {
        if (self.animation_frames == null) return;

        if (self.last_update_time) |last_time| {
            const elapsed = current_time_ms - last_time;
            if (elapsed >= self.animation_speed_ms) {
                self.nextFrame();
                self.last_update_time = current_time_ms;
            }
        } else {
            self.last_update_time = current_time_ms;
        }
    }

    /// Move to the next animation frame
    pub fn nextFrame(self: *Logo) void {
        if (self.animation_frames) |frames| {
            self.current_frame = (self.current_frame + 1) % frames.len;
            self.lines = frames[self.current_frame];
        }
    }

    /// Draw the logo to the terminal
    pub fn draw(self: *Logo) void {
        const start_y = self.bounds.y + self.padding;
        const start_x = self.bounds.x + self.padding;
        const max_width = self.bounds.width -| (self.padding * 2);
        const max_height = self.bounds.height -| (self.padding * 2);

        // Draw border if enabled
        if (self.border) {
            self.drawBorder();
        }

        // Clear background if specified
        if (self.background_color) |bg| {
            self.fillBackground(bg);
        }

        // Draw each line of the logo
        for (self.lines, 0..) |line, i| {
            if (i >= max_height) break;

            const y = start_y + i;
            const x = self.calculateXPosition(line, start_x, max_width);

            moveCursor(y, x);

            switch (self.style) {
                .ascii_art => self.drawAsciiLine(line, max_width),
                .styled_text => self.drawStyledLine(line, max_width),
                .banner => self.drawBannerLine(line, max_width, i == 0, i == self.lines.len - 1),
                .figlet => self.drawFigletLine(line, max_width),
            }
        }

        // Reset colors
        print("\x1b[0m", .{});
    }

    fn calculateXPosition(self: *Logo, line: []const u8, start_x: u32, max_width: u32) u32 {
        const line_width = @min(line.len, max_width);

        return switch (self.alignment) {
            .left => start_x,
            .center => start_x + (max_width -| line_width) / 2,
            .right => start_x + (max_width -| line_width),
        };
    }

    fn drawBorder(self: *Logo) void {
        const Box = @import("../../themes/default.zig").Box;

        // Top border
        moveCursor(self.bounds.y, self.bounds.x);
        print("{s}{u}{s}", .{ Box.TOP_LEFT, Box.HORIZONTAL, self.bounds.width -| 2 });
        print("{s}", .{Box.TOP_RIGHT});

        // Side borders
        for (1..self.bounds.height -| 1) |i| {
            moveCursor(self.bounds.y + i, self.bounds.x);
            print("{s}", .{Box.VERTICAL});

            moveCursor(self.bounds.y + i, self.bounds.x + self.bounds.width - 1);
            print("{s}", .{Box.VERTICAL});
        }

        // Bottom border
        moveCursor(self.bounds.y + self.bounds.height - 1, self.bounds.x);
        print("{s}{u}{s}", .{ Box.BOTTOM_LEFT, Box.HORIZONTAL, self.bounds.width -| 2 });
        print("{s}", .{Box.BOTTOM_RIGHT});
    }

    fn fillBackground(self: *Logo, color: Color) void {
        print("\x1b[{d}m", .{@intFromEnum(color) + 10}); // Background color

        for (self.padding..self.bounds.height -| self.padding) |y| {
            moveCursor(self.bounds.y + y, self.bounds.x + self.padding);
            for (self.padding..self.bounds.width -| self.padding) |_| {
                print(" ", .{});
            }
        }
    }

    fn drawAsciiLine(self: *Logo, line: []const u8, max_width: u32) void {
        print("\x1b[{d}m", .{@intFromEnum(self.color)});
        const display_len = @min(line.len, max_width);
        print("{s}", .{line[0..display_len]});
    }

    fn drawStyledLine(self: *Logo, line: []const u8, max_width: u32) void {
        // Apply bold and color
        print("\x1b[1;{d}m", .{@intFromEnum(self.color)});
        const display_len = @min(line.len, max_width);
        print("{s}", .{line[0..display_len]});
    }

    fn drawBannerLine(self: *Logo, line: []const u8, max_width: u32, is_first: bool, is_last: bool) void {
        _ = is_first;
        _ = is_last;

        // Draw with emphasis
        print("\x1b[1;{d}m", .{@intFromEnum(self.color)});

        // Add decorative elements
        print("┃ ", .{});
        const display_len = @min(line.len, max_width -| 4);
        print("{s}", .{line[0..display_len]});

        // Pad to width
        const padding = (max_width -| 4) -| display_len;
        for (0..padding) |_| {
            print(" ", .{});
        }
        print(" ┃", .{});
    }

    fn drawFigletLine(self: *Logo, line: []const u8, max_width: u32) void {
        // Draw with bold and possibly larger appearance
        print("\x1b[1;{d}m", .{@intFromEnum(self.color)});
        const display_len = @min(line.len, max_width);

        // Could implement actual FIGlet rendering here
        // For now, just draw bold text
        print("{s}", .{line[0..display_len]});
    }

    fn moveCursor(row: u32, col: u32) void {
        print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
    }
};

// Pre-defined logos for common use cases
pub const Logos = struct {
    pub const zig_logo =
        \\    ___     
        \\   |_ /     
        \\  / / _     
        \\ /___(_)__ _ 
        \\      |_  |
        \\       / / 
        \\      /___|
        \\           
    ;

    pub const terminal_logo =
        \\╔═══════════════╗
        \\║ > Terminal UI ║
        \\╚═══════════════╝
    ;

    pub const dashboard_logo =
        \\┌─────────────────┐
        \\│  📊 Dashboard   │
        \\└─────────────────┘
    ;

    pub const SPINNER_FRAMES = [_][]const u8{
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    };

    pub const LOADING_FRAMES = [_][]const u8{
        "[    ]",
        "[■   ]",
        "[■■  ]",
        "[■■■ ]",
        "[■■■■]",
    };
};

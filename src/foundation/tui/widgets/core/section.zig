//! Section widget for organized display
//! Extracted from monolithic tui.zig for better modularity

const std = @import("std");
const term_shared = @import("../../../term.zig");
const TermCaps = term_shared.TermCaps;
const print = std.debug.print;

/// Enhanced Section widget with collapsible content and rich styling
pub const Section = struct {
    title: []const u8,
    content: std.ArrayListUnmanaged([]const u8),
    isExpanded: bool,
    has_border: bool,
    indent_level: u32,
    icon: ?[]const u8,
    theme_colors: ThemeColors,
    allocator: std.mem.Allocator,

    pub const ThemeColors = struct {
        title: []const u8,
        content: []const u8,
        border: []const u8,
        icon: []const u8,
        reset: []const u8,

        // Default theme using ANSI colors for compatibility
        pub fn default() ThemeColors {
            return ThemeColors{
                .title = "\x1b[94m", // Bright blue
                .content = "\x1b[37m", // White
                .border = "\x1b[36m", // Cyan
                .icon = "\x1b[93m", // Bright yellow
                .reset = "\x1b[0m", // Reset
            };
        }

        // Rich theme using terminal capabilities
        pub fn rich(caps: TermCaps) ThemeColors {
            if (caps.supportsTrueColor()) {
                return ThemeColors{
                    .title = "\x1b[38;2;100;149;237m", // Cornflower blue
                    .content = "\x1b[38;2;245;245;245m", // White smoke
                    .border = "\x1b[38;2;64;224;208m", // Turquoise
                    .icon = "\x1b[38;2;255;215;0m", // Gold
                    .reset = "\x1b[0m",
                };
            } else if (caps.supports256Color()) {
                return ThemeColors{
                    .title = "\x1b[38;5;12m", // Bright blue
                    .content = "\x1b[38;5;15m", // Bright white
                    .border = "\x1b[38;5;14m", // Bright cyan
                    .icon = "\x1b[38;5;11m", // Bright yellow
                    .reset = "\x1b[0m",
                };
            } else {
                return default();
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, title: []const u8) Section {
        return Section{
            .title = title,
            .content = std.ArrayListUnmanaged([]const u8){},
            .isExpanded = true,
            .has_border = true,
            .indent_level = 0,
            .icon = null,
            .theme_colors = ThemeColors.default(),
            .allocator = allocator,
        };
    }

    pub fn initWithTheme(allocator: std.mem.Allocator, title: []const u8, theme: ThemeColors) Section {
        return Section{
            .title = title,
            .content = std.ArrayListUnmanaged([]const u8){},
            .isExpanded = true,
            .has_border = true,
            .indent_level = 0,
            .icon = null,
            .theme_colors = theme,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Section) void {
        self.content.deinit(self.allocator);
    }

    pub fn setIcon(self: *Section, icon: []const u8) void {
        self.icon = icon;
    }

    pub fn setBorder(self: *Section, has_border: bool) void {
        self.has_border = has_border;
    }

    pub fn setIndent(self: *Section, level: u32) void {
        self.indent_level = level;
    }

    pub fn setTheme(self: *Section, theme: ThemeColors) void {
        self.theme_colors = theme;
    }

    pub fn addLine(self: *Section, line: []const u8) !void {
        try self.content.append(self.allocator, line);
    }

    pub fn addFormattedLine(self: *Section, comptime fmt: []const u8, args: anytype) !void {
        const line = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.content.append(self.allocator, line);
    }

    pub fn toggle(self: *Section) void {
        self.isExpanded = !self.isExpanded;
    }

    pub fn expand(self: *Section) void {
        self.isExpanded = true;
    }

    pub fn collapse(self: *Section) void {
        self.isExpanded = false;
    }

    /// Enhanced drawing with terminal capabilities
    pub fn draw(self: Section) void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const writer = &stdout_writer.interface;
        self.drawWithWriter(writer);
    }

    pub fn drawWithWriter(self: Section, writer: *std.Io.Writer) void {
        self.drawImpl(writer) catch |err| {
            std.log.err("Failed to draw section: {}", .{err});
        };
    }

    fn drawImpl(self: Section, writer: *std.Io.Writer) !void {
        const indent_level = @min(self.indent_level, 10);
        var indent_buf: [20]u8 = [_]u8{' '} ** 20; // Max 10 * 2 = 20 chars
        const indent = indent_buf[0..(indent_level * 2)];
        const expand_icon = if (self.isExpanded) "▼" else "▶";
        const section_icon = self.icon orelse "";

        // Title line with colors and icons
        try writer.writeAll(indent);
        try writer.writeAll(self.theme_colors.title);
        try writer.writeAll(expand_icon);

        if (self.icon != null) {
            try writer.writeAll(self.theme_colors.icon);
            try writer.writeAll(section_icon);
            try writer.writeAll(" ");
        }

        try writer.writeAll(self.title);
        try writer.writeAll(self.theme_colors.reset);
        try writer.writeAll("\n");

        // Content (only if expanded)
        if (self.isExpanded) {
            const content_indent_level = if (self.indent_level > 0) self.indent_level else 1;
            var content_indent_buf: [40]u8 = [_]u8{' '} ** 40; // Max indent
            const content_indent = content_indent_buf[0..(content_indent_level * 4)];

            try writer.writeAll(self.theme_colors.content);

            for (self.content.items) |line| {
                try writer.writeAll(content_indent);
                try writer.writeAll(line);
                try writer.writeAll("\n");
            }

            try writer.writeAll(self.theme_colors.reset);

            if (self.content.items.len > 0) {
                try writer.writeAll("\n");
            }
        }
    }

    /// Draw with unique ID for screen updates (used by enhanced TUI system)
    pub fn drawWithId(self: Section, id: []const u8) void {
        // For now, just draw normally
        // In a full implementation, this would integrate with screen buffering
        _ = id;
        self.draw();
    }

    /// Get the rendered height of the section (useful for layout calculations)
    pub fn getHeight(self: Section) u32 {
        var height: u32 = 1; // Title line

        if (self.isExpanded) {
            height += @intCast(self.content.items.len);
            if (self.content.items.len > 0) {
                height += 1; // Extra newline
            }
        }

        return height;
    }

    /// Check if coordinates fall within this section (for mouse interaction)
    pub fn containsPoint(self: Section, x: u32, y: u32, section_start_y: u32) bool {
        _ = x; // For now, assume any x coordinate is valid
        const height = self.getHeight();
        return y >= section_start_y and y < section_start_y + height;
    }

    /// Handle mouse click on section (toggle expand/collapse)
    pub fn handleClick(self: *Section, x: u32, y: u32, section_start_y: u32) bool {
        if (self.containsPoint(x, y, section_start_y) and y == section_start_y) {
            // Clicked on title line - toggle
            self.toggle();
            return true;
        }
        return false;
    }
};

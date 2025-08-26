//! Section widget for organized display
//! Extracted from monolithic tui.zig for better modularity

const std = @import("std");
const term_ansi = @import("../../term/ansi/color.zig");
const term_caps = @import("../../term/caps.zig");
const print = std.debug.print;

/// Enhanced Section widget with collapsible content and rich styling
pub const Section = struct {
    title: []const u8,
    content: std.ArrayList([]const u8),
    is_expanded: bool,
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
        pub fn rich(caps: term_caps.TermCaps) ThemeColors {
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
            .content = std.ArrayList([]const u8).init(allocator),
            .is_expanded = true,
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
            .content = std.ArrayList([]const u8).init(allocator),
            .is_expanded = true,
            .has_border = true,
            .indent_level = 0,
            .icon = null,
            .theme_colors = theme,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Section) void {
        self.content.deinit();
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
        try self.content.append(line);
    }

    pub fn addFormattedLine(self: *Section, comptime fmt: []const u8, args: anytype) !void {
        const line = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.content.append(line);
    }

    pub fn toggle(self: *Section) void {
        self.is_expanded = !self.is_expanded;
    }

    pub fn expand(self: *Section) void {
        self.is_expanded = true;
    }

    pub fn collapse(self: *Section) void {
        self.is_expanded = false;
    }

    /// Enhanced drawing with terminal capabilities
    pub fn draw(self: Section) void {
        self.drawWithWriter(std.fs.File.stdout().writer().any());
    }

    pub fn drawWithWriter(self: Section, writer: anytype) void {
        self.drawImpl(writer) catch |err| {
            std.log.err("Failed to draw section: {}", .{err});
        };
    }

    fn drawImpl(self: Section, writer: anytype) !void {
        const indent = "  " ** @min(self.indent_level, 10); // Limit indent to prevent overflow
        const expand_icon = if (self.is_expanded) "▼" else "▶";
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
        if (self.is_expanded) {
            const content_indent = if (self.indent_level > 0) "    " ** self.indent_level else "  ";

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

        if (self.is_expanded) {
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

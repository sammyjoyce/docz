//! CLI output formatter
//! Provides rich formatting, adaptive colors using @src/term capabilities

const std = @import("std");
const term_mod = @import("term_shared");
const unified = term_mod.unified;

// Minimal TUI replacements
const BasicTui = struct {
    fn getTerminalSize() struct { width: u16, height: u16 } {
        return .{ .width = 80, .height = 24 };
    }

    const TerminalSize = struct { width: u16, height: u16 };
};

const tui = BasicTui;

/// Enhanced CLI formatter with terminal capability awareness
pub const CliFormatter = struct {
    allocator: std.mem.Allocator,
    caps: term_mod.caps.TermCaps,
    terminal_size: tui.TerminalSize,
    terminal: unified.Terminal,

    // Color scheme adapted to terminal capabilities
    styles: StyleScheme,

    pub const StyleScheme = struct {
        primary: unified.Style,
        secondary: unified.Style,
        accent: unified.Style,
        success: unified.Style,
        warning: unified.Style,
        errColor: unified.Style,
        muted: unified.Style,
        bold: unified.Style,
        dim: unified.Style,
    };

    pub fn init(allocator: std.mem.Allocator) !CliFormatter {
        const terminal = try unified.Terminal.init(allocator);
        const terminal_size = tui.getTerminalSize();

        // Adaptive style scheme based on terminal capabilities
        const styles = if (terminal.caps.supportsTruecolor)
            StyleScheme{
                // 24-bit RGB colors for modern terminals
                .primary = .{ .fg_color = .{ .rgb = .{ .r = 65, .g = 132, .b = 228 } } }, // Blue
                .secondary = .{ .fg_color = .{ .rgb = .{ .r = 46, .g = 160, .b = 67 } } }, // Green
                .accent = .{ .fg_color = .{ .rgb = .{ .r = 245, .g = 121, .b = 0 } } }, // Orange
                .success = .{ .fg_color = .{ .rgb = .{ .r = 46, .g = 204, .b = 113 } } }, // Light Green
                .warning = .{ .fg_color = .{ .rgb = .{ .r = 241, .g = 196, .b = 15 } } }, // Yellow
                .errColor = .{ .fg_color = .{ .rgb = .{ .r = 231, .g = 76, .b = 60 } } }, // Red
                .muted = .{ .fg_color = .{ .rgb = .{ .r = 108, .g = 117, .b = 125 } } }, // Gray
                .bold = .{ .bold = true },
                .dim = .{ .fg_color = .{ .palette = 8 } }, // Dark gray
            }
        else
            StyleScheme{
                // Fallback to basic ANSI colors
                .primary = .{ .fg_color = .{ .ansi = 12 } }, // Bright Blue
                .secondary = .{ .fg_color = .{ .ansi = 10 } }, // Bright Green
                .accent = .{ .fg_color = .{ .ansi = 11 } }, // Bright Yellow
                .success = .{ .fg_color = .{ .ansi = 10 } }, // Bright Green
                .warning = .{ .fg_color = .{ .ansi = 11 } }, // Bright Yellow
                .errColor = .{ .fg_color = .{ .ansi = 9 } }, // Bright Red
                .muted = .{ .fg_color = .{ .ansi = 8 } }, // Dark Gray
                .bold = .{ .bold = true },
                .dim = .{ .fg_color = .{ .ansi = 8 } }, // Dark gray
            };

        return CliFormatter{
            .allocator = allocator,
            .caps = terminal.caps,
            .terminal_size = terminal_size,
            .terminal = terminal,
            .styles = styles,
        };
    }

    pub fn deinit(self: *CliFormatter) void {
        self.terminal.deinit();
    }

    /// Enhanced help display with structured layout
    pub fn printEnhancedHelp(self: *CliFormatter, cli_config: anytype) !void {
        const width = @min(self.terminal_size.width, 80);

        // Header section with enhanced styling
        try self.terminal.printf("{s}DocZ{s}", .{ self.styles.bold, unified.Style{} }, self.styles.primary);
        if (@hasField(@TypeOf(cli_config), "version")) {
            try self.terminal.printf(" {s}v{s}{s}", .{ self.styles.muted, cli_config.version, unified.Style{} }, null);
        }
        try self.terminal.printf(" - {s}{s}{s}\n\n", .{ self.styles.secondary, cli_config.description, unified.Style{} }, null);

        // Usage section
        const usage_content = [_][]const u8{
            "",
            "Basic usage patterns:",
            "",
            "  docz [OPTIONS] [FLAGS] [PROMPT]",
            "  docz auth <SUBCOMMAND>",
            "",
        };

        const usage_section = tui.Section.init("🚀 USAGE", &usage_content, width);
        usage_section.draw();
        try self.terminal.printf("\n", .{}, null);

        // Options section
        self.printOptionsSection(cli_config);

        // Examples section
        self.printExamplesSection(cli_config);

        // Terminal capabilities info
        self.printCapabilitiesInfo();
    }

    /// Enhanced error display
    pub fn printEnhancedError(self: *CliFormatter, err: anytype, _: ?[]const u8) !void {
        const width = @min(self.terminal_size.width, 80);

        // Error header with icon and color
        try self.terminal.printf("\n{s}{s}❌ Error{s}\n", .{ self.colors.bold, self.colors.errColor, self.colors.reset }, null);

        // Error message
        const error_msg = switch (err) {
            error.InvalidArgument => "Invalid argument provided",
            error.MissingValue => "Missing value for option",
            error.UnknownOption => "Unknown option",
            error.InvalidValue => "Invalid value for option",
            error.MutuallyExclusiveOptions => "Mutually exclusive options provided",
            error.OutOfMemory => "Out of memory",
            error.UnknownCommand => "Unknown command",
            error.UnknownSubcommand => "Unknown subcommand",
            else => "An unexpected error occurred",
        };

        const error_content = [_][]const u8{
            "",
            error_msg,
            "",
            "💡 Use --help for usage information",
            "",
        };

        const error_section = tui.Section.init("Error Details", &error_content, width);
        error_section.draw();
        try self.terminal.printf("\n", .{}, null);
    }

    /// Enhanced version display
    pub fn printEnhancedVersion(self: *CliFormatter, cli_config: anytype) !void {
        try self.terminal.printf("{s}{s}DocZ{s}", .{ self.colors.bold, self.colors.primary, self.colors.reset }, null);
        if (@hasField(@TypeOf(cli_config), "version")) {
            try self.terminal.printf(" version {s}{s}{s}\n", .{ self.colors.accent, cli_config.version, self.colors.reset }, null);
        } else {
            try self.terminal.printf(" version {s}0.1.0{s}\n", .{ self.colors.accent, self.colors.reset }, null);
        }

        self.printCapabilitiesInfo();
    }

    // Private helper methods

    fn printOptionsSection(self: *CliFormatter, cli_config: anytype) void {
        const OptsT = @TypeOf(cli_config.options);
        const OptsInfo = @typeInfo(OptsT).@"struct";

        if (OptsInfo.fields.len == 0) return;

        self.terminal.printf("{s}⚙️  OPTIONS:{s}\n\n", .{ self.colors.bold, self.colors.reset }, null) catch {};

        inline for (OptsInfo.fields) |field| {
            const opt = @field(cli_config.options, field.name);

            // Format option line
            if (@hasField(@TypeOf(opt), "short")) {
                const short_char: u8 = @intCast(opt.short);
                self.terminal.printf("  {s}-{c}, --{s}{s} <{s}>    {s}", .{ self.colors.accent, short_char, opt.long, self.colors.reset, opt.type, opt.description }, null) catch {};
            } else {
                self.terminal.printf("      {s}--{s}{s} <{s}>    {s}", .{ self.colors.accent, opt.long, self.colors.reset, opt.type, opt.description }, null) catch {};
            }

            // Default value
            if (@hasField(@TypeOf(opt), "default")) {
                if (comptime std.mem.eql(u8, opt.long, "model")) {
                    self.terminal.printf(" {s}[default: {s}]{s}", .{ self.colors.muted, opt.default, self.colors.reset }, null) catch {};
                } else {
                    self.terminal.printf(" {s}[default: {}]{s}", .{ self.colors.muted, opt.default, self.colors.reset }, null) catch {};
                }
            }
            self.terminal.printf("\n", .{}, null) catch {};
        }
        self.terminal.printf("\n", .{}, null) catch {};
    }

    fn printExamplesSection(self: *CliFormatter, cli_config: anytype) void {
        if (!@hasField(@TypeOf(cli_config), "examples")) return;

        self.terminal.printf("{s}💡 EXAMPLES:{s}\n\n", .{ self.colors.bold, self.colors.reset }, null) catch {};
        self.terminal.printf("Try these commands:\n\n", .{}, null) catch {};

        const ExamplesT = @TypeOf(cli_config.examples);
        const examples_info = @typeInfo(ExamplesT);

        if (examples_info == .@"struct") {
            inline for (examples_info.@"struct".fields) |field| {
                const example = @field(cli_config.examples, field.name);
                self.terminal.printf("  {s}docz {s}{s}  {s}# {s}{s}\n", .{ self.colors.accent, example.command, self.colors.reset, self.colors.muted, example.description, self.colors.reset }, null) catch {};
            }
        }

        if (self.caps.supportsClipboardOsc52) {
            self.terminal.printf("\n{s}💡 Terminal supports clipboard integration{s}\n", .{ self.colors.muted, self.colors.reset }, null) catch {};
        }
        self.terminal.printf("\n", .{}, null) catch {};
    }

    fn printCapabilitiesInfo(self: *CliFormatter) void {
        self.terminal.printf("\n{s}🖥️  TERMINAL CAPABILITIES:{s}\n", .{ self.colors.bold, self.colors.reset }, null) catch {};
        self.terminal.printf("  Size: {s}{}×{} characters{s}\n", .{ self.colors.muted, self.terminal_size.width, self.terminal_size.height, self.colors.reset }, null) catch {};

        const truecolor_status = if (self.caps.supportsTruecolor)
            "✅ 24-bit colors"
        else
            "⚠️  Basic colors";
        self.terminal.printf("  Colors: {s}\n", .{truecolor_status}, null) catch {};

        const hyperlinks_status = if (self.caps.supportsHyperlinkOsc8)
            "✅ Clickable links"
        else
            "❌ Plain text only";
        self.terminal.printf("  Hyperlinks: {s}\n", .{hyperlinks_status}, null) catch {};

        const clipboard_status = if (self.caps.supportsClipboardOsc52)
            "✅ Copy/paste support"
        else
            "❌ No clipboard";
        self.terminal.printf("  Clipboard: {s}\n", .{clipboard_status}, null) catch {};

        self.terminal.printf("\n", .{}, null) catch {};
    }
};

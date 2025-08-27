//! CLI output formatter
//! Provides rich formatting, adaptive colors using @src/term capabilities

const std = @import("std");
const termMod = @import("term_shared");
const term = termMod.term;

// Minimal TUI replacements
const BasicTui = struct {
    fn getTerminalSize() struct { width: u16, height: u16 } {
        return .{ .width = 80, .height = 24 };
    }

    const TerminalSize = struct { width: u16, height: u16 };
};

const tui = BasicTui;

/// CLI formatter with terminal capability awareness
pub const CliFormatter = struct {
    allocator: std.mem.Allocator,
    caps: termMod.caps.TermCaps,
    terminalSize: tui.TerminalSize,
    terminal: term.Terminal,

    // Color scheme adapted to terminal capabilities
    styles: StyleScheme,

    pub const StyleScheme = struct {
        primary: term.Style,
        secondary: term.Style,
        accent: term.Style,
        success: term.Style,
        warning: term.Style,
        errColor: term.Style,
        muted: term.Style,
        bold: term.Style,
        dim: term.Style,
    };

    pub fn init(allocator: std.mem.Allocator) !CliFormatter {
        const terminal = try term.Terminal.init(allocator);
        const terminalSize = tui.getTerminalSize();

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
            .terminalSize = terminalSize,
            .terminal = terminal,
            .styles = styles,
        };
    }

    pub fn deinit(self: *CliFormatter) void {
        self.terminal.deinit();
    }

    /// Enhanced help display with structured layout
    pub fn printHelp(self: *CliFormatter, cli_config: anytype) !void {
        const width = @min(self.terminalSize.width, 80);

        // Header section with styling
        try self.terminal.printf("{s}DocZ{s}", .{ self.styles.bold, term.Style{} }, self.styles.primary);
        if (@hasField(@TypeOf(cli_config), "version")) {
            try self.terminal.printf(" {s}v{s}{s}", .{ self.styles.muted, cli_config.version, term.Style{} }, null);
        }
        try self.terminal.printf(" - {s}{s}{s}\n\n", .{ self.styles.secondary, cli_config.description, term.Style{} }, null);

        // Usage section
        const usageContent = [_][]const u8{
            "",
            "Basic usage patterns:",
            "",
            "  docz [OPTIONS] [FLAGS] [PROMPT]",
            "  docz auth <SUBCOMMAND>",
            "",
        };

        const usageSection = tui.Section.init("🚀 USAGE", &usageContent, width);
        usageSection.draw();
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
        const width = @min(self.terminalSize.width, 80);

        // Error header with icon and color
        try self.terminal.printf("\n{s}{s}❌ Error{s}\n", .{ self.colors.bold, self.colors.errColor, self.colors.reset }, null);

        // Error message
        const errorMsg = switch (err) {
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

        const errorContent = [_][]const u8{
            "",
            errorMsg,
            "",
            "💡 Use --help for usage information",
            "",
        };

        const errorSection = tui.Section.init("Error Details", &errorContent, width);
        errorSection.draw();
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
                const shortChar: u8 = @intCast(opt.short);
                self.terminal.printf("  {s}-{c}, --{s}{s} <{s}>    {s}", .{ self.colors.accent, shortChar, opt.long, self.colors.reset, opt.type, opt.description }, null) catch {};
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
        const examplesInfo = @typeInfo(ExamplesT);

        if (examplesInfo == .@"struct") {
            inline for (examplesInfo.@"struct".fields) |field| {
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
        self.terminal.printf("  Size: {s}{}×{} characters{s}\n", .{ self.colors.muted, self.terminalSize.width, self.terminalSize.height, self.colors.reset }, null) catch {};

        const truecolorStatus = if (self.caps.supportsTruecolor)
            "✅ 24-bit colors"
        else
            "⚠️  Basic colors";
        self.terminal.printf("  Colors: {s}\n", .{truecolorStatus}, null) catch {};

        const hyperlinksStatus = if (self.caps.supportsHyperlinkOsc8)
            "✅ Clickable links"
        else
            "❌ Plain text only";
        self.terminal.printf("  Hyperlinks: {s}\n", .{hyperlinksStatus}, null) catch {};

        const clipboardStatus = if (self.caps.supportsClipboardOsc52)
            "✅ Copy/paste support"
        else
            "❌ No clipboard";
        self.terminal.printf("  Clipboard: {s}\n", .{clipboardStatus}, null) catch {};

        self.terminal.printf("\n", .{}, null) catch {};
    }
};

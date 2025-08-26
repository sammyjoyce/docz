//! Simplified enhanced CLI output formatter
//! Provides rich formatting, adaptive colors using @src/term capabilities

const std = @import("std");
const print = std.debug.print;
const tui = @import("../tui.zig");
const caps_mod = @import("../term/caps.zig");

/// Enhanced CLI formatter with terminal capability awareness
pub const CliFormatter = struct {
    allocator: std.mem.Allocator,
    caps: caps_mod.TermCaps,
    terminal_size: tui.TerminalSize,

    // Color scheme adapted to terminal capabilities
    colors: ColorScheme,

    pub const ColorScheme = struct {
        primary: []const u8,
        secondary: []const u8,
        accent: []const u8,
        success: []const u8,
        warning: []const u8,
        err_color: []const u8,
        muted: []const u8,
        reset: []const u8,
        bold: []const u8,
        dim: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) CliFormatter {
        const caps = caps_mod.detectCaps(allocator) catch caps_mod.TermCaps{
            .supportsTruecolor = false,
            .supportsHyperlinkOsc8 = false,
            .supportsClipboardOsc52 = false,
            .supportsWorkingDirOsc7 = false,
            .supportsTitleOsc012 = false,
            .supportsNotifyOsc9 = false,
            .supportsFinalTermOsc133 = false,
            .supportsColorOsc10_12 = false,
            .supportsKittyKeyboard = false,
            .supportsKittyGraphics = false,
            .supportsSixel = false,
            .supportsModifyOtherKeys = false,
            .supportsXtwinops = false,
            .supportsBracketedPaste = false,
            .supportsFocusEvents = false,
            .supportsSgrMouse = false,
            .supportsSgrPixelMouse = false,
            .supportsLightDarkReport = false,
            .needsTmuxPassthrough = false,
            .needsScreenPassthrough = false,
            .screenChunkLimit = 0,
            .widthMethod = .grapheme,
        };
        const terminal_size = tui.getTerminalSize();

        // Adaptive color scheme based on terminal capabilities
        const colors = if (caps.supportsTruecolor)
            ColorScheme{
                // 24-bit RGB colors for modern terminals
                .primary = "\x1b[38;2;65;132;228m", // Blue
                .secondary = "\x1b[38;2;46;160;67m", // Green
                .accent = "\x1b[38;2;245;121;0m", // Orange
                .success = "\x1b[38;2;46;204;113m", // Light Green
                .warning = "\x1b[38;2;241;196;15m", // Yellow
                .err_color = "\x1b[38;2;231;76;60m", // Red
                .muted = "\x1b[38;2;108;117;125m", // Gray
                .reset = "\x1b[0m",
                .bold = "\x1b[1m",
                .dim = "\x1b[2m",
            }
        else
            ColorScheme{
                // Fallback to basic ANSI colors
                .primary = "\x1b[94m", // Bright Blue
                .secondary = "\x1b[92m", // Bright Green
                .accent = "\x1b[93m", // Bright Yellow
                .success = "\x1b[92m", // Bright Green
                .warning = "\x1b[93m", // Bright Yellow
                .err_color = "\x1b[91m", // Bright Red
                .muted = "\x1b[90m", // Dark Gray
                .reset = "\x1b[0m",
                .bold = "\x1b[1m",
                .dim = "\x1b[2m",
            };

        return CliFormatter{
            .allocator = allocator,
            .caps = caps,
            .terminal_size = terminal_size,
            .colors = colors,
        };
    }

    /// Enhanced help display with structured layout
    pub fn printEnhancedHelp(self: *CliFormatter, cli_config: anytype) !void {
        const width = @min(self.terminal_size.width, 80);

        // Header section with enhanced styling
        print("{s}{s}DocZ{s}", .{ self.colors.bold, self.colors.primary, self.colors.reset });
        if (@hasField(@TypeOf(cli_config), "version")) {
            print(" {s}v{s}{s}", .{ self.colors.muted, cli_config.version, self.colors.reset });
        }
        print(" - {s}{s}{s}\n\n", .{ self.colors.secondary, cli_config.description, self.colors.reset });

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
        print("\n");

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
        print("\n{s}{s}❌ Error{s}\n", .{ self.colors.bold, self.colors.err_color, self.colors.reset });

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
        print("\n");
    }

    /// Enhanced version display
    pub fn printEnhancedVersion(self: *CliFormatter, cli_config: anytype) !void {
        print("{s}{s}DocZ{s}", .{ self.colors.bold, self.colors.primary, self.colors.reset });
        if (@hasField(@TypeOf(cli_config), "version")) {
            print(" version {s}{s}{s}\n", .{ self.colors.accent, cli_config.version, self.colors.reset });
        } else {
            print(" version {s}0.1.0{s}\n", .{ self.colors.accent, self.colors.reset });
        }

        self.printCapabilitiesInfo();
    }

    // Private helper methods

    fn printOptionsSection(self: *CliFormatter, cli_config: anytype) void {
        const OptsT = @TypeOf(cli_config.options);
        const OptsInfo = @typeInfo(OptsT).@"struct";

        if (OptsInfo.fields.len == 0) return;

        print("{s}⚙️  OPTIONS:{s}\n\n", .{ self.colors.bold, self.colors.reset });

        inline for (OptsInfo.fields) |field| {
            const opt = @field(cli_config.options, field.name);

            // Format option line
            if (@hasField(@TypeOf(opt), "short")) {
                const short_char: u8 = @intCast(opt.short);
                print("  {s}-{c}, --{s}{s} <{s}>    {s}", .{ self.colors.accent, short_char, opt.long, self.colors.reset, opt.type, opt.description });
            } else {
                print("      {s}--{s}{s} <{s}>    {s}", .{ self.colors.accent, opt.long, self.colors.reset, opt.type, opt.description });
            }

            // Default value
            if (@hasField(@TypeOf(opt), "default")) {
                if (comptime std.mem.eql(u8, opt.long, "model")) {
                    print(" {s}[default: {s}]{s}", .{ self.colors.muted, opt.default, self.colors.reset });
                } else {
                    print(" {s}[default: {}]{s}", .{ self.colors.muted, opt.default, self.colors.reset });
                }
            }
            print("\n");
        }
        print("\n");
    }

    fn printExamplesSection(self: *CliFormatter, cli_config: anytype) void {
        if (!@hasField(@TypeOf(cli_config), "examples")) return;

        print("{s}💡 EXAMPLES:{s}\n\n", .{ self.colors.bold, self.colors.reset });
        print("Try these commands:\n\n");

        const ExamplesT = @TypeOf(cli_config.examples);
        const examples_info = @typeInfo(ExamplesT);

        if (examples_info == .@"struct") {
            inline for (examples_info.@"struct".fields) |field| {
                const example = @field(cli_config.examples, field.name);
                print("  {s}docz {s}{s}  {s}# {s}{s}\n", .{ self.colors.accent, example.command, self.colors.reset, self.colors.muted, example.description, self.colors.reset });
            }
        }

        if (self.caps.supportsClipboardOsc52) {
            print("\n{s}💡 Terminal supports clipboard integration{s}\n", .{ self.colors.muted, self.colors.reset });
        }
        print("\n");
    }

    fn printCapabilitiesInfo(self: *CliFormatter) void {
        print("\n{s}🖥️  TERMINAL CAPABILITIES:{s}\n", .{ self.colors.bold, self.colors.reset });
        print("  Size: {s}{}×{} characters{s}\n", .{ self.colors.muted, self.terminal_size.width, self.terminal_size.height, self.colors.reset });

        const truecolor_status = if (self.caps.supportsTruecolor)
            "✅ 24-bit colors"
        else
            "⚠️  Basic colors";
        print("  Colors: {s}\n", .{truecolor_status});

        const hyperlinks_status = if (self.caps.supportsHyperlinkOsc8)
            "✅ Clickable links"
        else
            "❌ Plain text only";
        print("  Hyperlinks: {s}\n", .{hyperlinks_status});

        const clipboard_status = if (self.caps.supportsClipboardOsc52)
            "✅ Copy/paste support"
        else
            "❌ No clipboard";
        print("  Clipboard: {s}\n", .{clipboard_status});

        print("\n");
    }
};

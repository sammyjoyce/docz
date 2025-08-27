//! Enhanced CLI output formatter leveraging @src/term capabilities and TUI system
//! Provides rich formatting, adaptive colors, hyperlinks, and clipboard integration

const std = @import("std");
const print = std.debug.print;
// const tui = @import("tui_shared"); // Disabled to avoid module conflicts
const caps_mod = @import("../../term/mod.zig").caps;

// Minimal TUI replacements
const SimpleTui = struct {
    const Color = struct {
        const BRIGHT_BLUE = "";
        const BRIGHT_GREEN = "";
        const BRIGHT_RED = "";
        const BRIGHT_YELLOW = "";
        const BRIGHT_CYAN = "";
        const BRIGHT_MAGENTA = "";
        const DIM = "";
        const BOLD = "";
        const RESET = "";
    };

    fn getTerminalSize() struct { width: u16, height: u16 } {
        return .{ .width = 80, .height = 24 };
    }

    const TerminalSize = struct { width: u16, height: u16 };
};

const tui = SimpleTui;
const color_mod = @import("../../term/mod.zig").ansi.color;
const sgr_mod = @import("../../term/mod.zig").ansi.sgr;
const hyperlink_mod = @import("../../term/mod.zig").ansi.hyperlink;
const clipboard_mod = @import("../../term/mod.zig").ansi.clipboard;
const notification_mod = @import("../../term/mod.zig").ansi.notification;
const title_mod = @import("../../term/mod.zig").ansi.title;

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
        const caps = caps_mod.detectCaps(allocator) catch |err| {
            std.log.warn("Failed to detect terminal capabilities: {any}", .{err});
            // Fallback to basic capabilities
            return CliFormatter{
                .allocator = allocator,
                .caps = caps_mod.TermCaps{
                    .supportsTruecolor = false,
                    .supportsHyperlinkOsc8 = false,
                    .supportsClipboardOsc52 = false,
                    .supportsWorkingDirOsc7 = false,
                    .supportsTitleOsc012 = false,
                    .supportsNotifyOsc9 = false,
                    .supportsFinalTermOsc133 = false,
                    .supportsITerm2Osc1337 = false,
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
                    .supportsLinuxPaletteOscP = false,
                    .supportsDeviceAttributes = false,
                    .supportsCursorStyle = false,
                    .supportsCursorPositionReport = false,
                    .supportsPointerShape = false,
                    .needsTmuxPassthrough = false,
                    .needsScreenPassthrough = false,
                    .screenChunkLimit = 4096,
                    .widthMethod = .grapheme,
                },
                .terminal_size = .{ .width = 80, .height = 24 },
                .colors = ColorScheme{
                    .primary = "\x1b[34m", // Blue
                    .secondary = "\x1b[90m", // Dark gray
                    .accent = "\x1b[36m", // Cyan
                    .success = "\x1b[32m", // Green
                    .warning = "\x1b[33m", // Yellow
                    .err_color = "\x1b[31m", // Red
                    .muted = "\x1b[37m", // Light gray
                    .reset = "\x1b[0m",
                    .bold = "\x1b[1m",
                    .dim = "\x1b[2m",
                },
            };
        };
        const terminal_size = SimpleTui.TerminalSize{ .width = 80, .height = 24 };

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

    /// Enhanced help display with structured layout and hyperlinks
    pub fn printEnhancedHelp(self: *CliFormatter, cli_config: anytype) !void {
        const width = @min(self.terminal_size.width, 80);

        // Update window title if supported
        // Note: title setting would need proper writer implementation

        // Header section with enhanced styling
        print("{s}{s}DocZ{s}", .{ self.colors.bold, self.colors.primary, self.colors.reset });
        if (@hasField(@TypeOf(cli_config), "version")) {
            print(" {s}v{s}{s}", .{ self.colors.muted, cli_config.version, self.colors.reset });
        }
        print(" - {s}{s}{s}\n\n", .{ self.colors.secondary, cli_config.description, self.colors.reset });

        // Usage section with structured layout
        const usage_content = [_][]const u8{
            "",
            "Basic usage patterns:",
            "",
            "  docz [OPTIONS] [FLAGS] [PROMPT]",
            "  docz auth <SUBCOMMAND>",
            "",
        };

        // Print usage section manually
        print("{s}🚀 USAGE{s}\n", .{ self.colors.bold, self.colors.reset });
        print("{s}\n", .{self.colors.dim});
        for (usage_content) |line| {
            print("  {s}\n", .{line});
        }
        print("{s}\n", .{self.colors.reset});

        // Options section with enhanced formatting
        try self.printOptionsSection(cli_config, @intCast(width));

        // Examples section with copy-to-clipboard integration
        try self.printExamplesSection(cli_config, width);

        // Links section with hyperlinks
        try self.printLinksSection(width);

        // Send completion notification if supported
        // Note: notification would need proper writer implementation
    }

    /// Enhanced error display with structured formatting
    pub fn printEnhancedError(self: *CliFormatter, err: anytype, context: ?[]const u8) !void {

        // Error header with icon and color
        print("\n{s}{s}❌ Error{s}\n", .{ self.colors.bold, self.colors.err_color, self.colors.reset });

        // Error message with context-aware handling
        var error_msg: []const u8 = undefined;
        var show_auth_help = false;

        switch (err) {
            error.InvalidArgument => error_msg = "Invalid argument provided",
            error.MissingValue => error_msg = "Missing value for option",
            error.UnknownOption => error_msg = "Unknown option",
            error.InvalidValue => error_msg = "Invalid value for option",
            error.MutuallyExclusiveOptions => error_msg = "Mutually exclusive options provided",
            error.OutOfMemory => error_msg = "Out of memory",
            error.UnknownCommand => error_msg = "Unknown command",
            error.UnknownSubcommand => {
                // Check if this is an auth-related error
                if (context) |ctx| {
                    if (std.mem.eql(u8, ctx, "auth") or std.mem.startsWith(u8, ctx, "auth ")) {
                        error_msg = "Missing or invalid subcommand for 'auth'";
                        show_auth_help = true;
                    } else {
                        error_msg = "Unknown subcommand";
                    }
                } else {
                    error_msg = "Unknown subcommand";
                }
            },
            else => error_msg = "An unexpected error occurred",
        }

        var error_content = std.array_list.Managed([]const u8).init(self.allocator);
        defer error_content.deinit();

        try error_content.append("");
        try error_content.append(error_msg);

        // Add auth-specific help if needed
        if (show_auth_help) {
            try error_content.append("");
            try error_content.append("Available auth subcommands:");
            try error_content.append("  • login   - Start authentication process");
            try error_content.append("  • status  - Check authentication status");
            try error_content.append("  • refresh - Refresh authentication token");
            try error_content.append("");
            try error_content.append("Example: docz auth login");
        }

        try error_content.append("");
        try error_content.append("💡 Use --help for usage information");
        try error_content.append("");

        // Print error section manually
        print("{s}{s}Error Details{s}\n", .{ self.colors.bold, self.colors.err_color, self.colors.reset });
        print("{s}\n", .{self.colors.dim});

        // Print context if available
        if (context) |ctx| {
            const ctx_line = try std.fmt.allocPrint(self.allocator, "Context: {s}", .{ctx});
            defer self.allocator.free(ctx_line);
            print("  {s}\n", .{ctx_line});
        }

        for (error_content.items) |line| {
            print("  {s}\n", .{line});
        }
        print("{s}\n", .{self.colors.reset});
    }

    /// Enhanced version display with system info
    pub fn printEnhancedVersion(self: *CliFormatter, cli_config: anytype) !void {
        print("{s}{s}DocZ{s}", .{ self.colors.bold, self.colors.primary, self.colors.reset });
        if (@hasField(@TypeOf(cli_config), "version")) {
            print(" version {s}{s}{s}\n", .{ self.colors.accent, cli_config.version, self.colors.reset });
        } else {
            print(" version {s}0.1.0{s}\n", .{ self.colors.accent, self.colors.reset });
        }

        // Terminal capabilities info
        var caps_content = std.array_list.Managed([]const u8).init(self.allocator);
        defer caps_content.deinit();

        try caps_content.append("");
        try caps_content.append("🖥️  Terminal Capabilities:");
        try caps_content.append("");

        const size_info = try std.fmt.allocPrint(self.allocator, "   Size: {}×{} characters", .{ self.terminal_size.width, self.terminal_size.height });
        try caps_content.append(size_info);

        const truecolor_status = if (self.caps.supportsTruecolor) "✅ Supported" else "❌ Not supported";
        const truecolor_line = try std.fmt.allocPrint(self.allocator, "   Truecolor: {s}", .{truecolor_status});
        try caps_content.append(truecolor_line);

        const hyperlinks_status = if (self.caps.supportsHyperlinkOsc8) "✅ Supported" else "❌ Not supported";
        const hyperlinks_line = try std.fmt.allocPrint(self.allocator, "   Hyperlinks: {s}", .{hyperlinks_status});
        try caps_content.append(hyperlinks_line);

        const clipboard_status = if (self.caps.supportsClipboardOsc52) "✅ Supported" else "❌ Not supported";
        const clipboard_line = try std.fmt.allocPrint(self.allocator, "   Clipboard: {s}", .{clipboard_status});
        try caps_content.append(clipboard_line);

        try caps_content.append("");

        // Print system information section manually
        print("{s}System Information{s}\n", .{ self.colors.bold, self.colors.reset });
        print("{s}\n", .{self.colors.dim});
        for (caps_content.items) |line| {
            print("  {s}\n", .{line});
        }
        print("{s}\n", .{self.colors.reset});

        // Free allocated strings
        self.allocator.free(size_info);
        self.allocator.free(truecolor_line);
        self.allocator.free(hyperlinks_line);
        self.allocator.free(clipboard_line);
    }

    /// Copy text to system clipboard if supported
    pub fn copyToClipboard(self: *CliFormatter, text: []const u8) !bool {
        if (!self.caps.supportsClipboardOsc52) return false;

        // Use stdout writer for clipboard operations
        const writer = std.io.getStdOut().writer();
        clipboard_mod.writeClipboard(writer, self.allocator, self.caps, text) catch return false;

        print("{s}📋 Copied to clipboard{s}\n", .{ self.colors.muted, self.colors.reset });
        return true;
    }

    /// Enhanced progress indicator
    pub fn showProgress(self: *CliFormatter, message: []const u8, current: u32, total: u32) !void {
        const percent = if (total > 0) (current * 100) / total else 0;
        const bar_width = @min(40, self.terminal_size.width - 20);
        const filled = (percent * bar_width) / 100;

        print("\r{s}{s}{s} [", .{ self.colors.primary, message, self.colors.reset });

        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled) {
                print("{s}█{s}", .{ self.colors.accent, self.colors.reset });
            } else {
                print("░");
            }
        }

        print("] {s}{}%{s}", .{ self.colors.muted, percent, self.colors.reset });
    }

    /// Finish progress and clear line
    pub fn finishProgress(self: *CliFormatter, message: []const u8) !void {
        print("\r{s}✅ {s}{s}\n", .{ self.colors.success, message, self.colors.reset });
    }

    // Private helper methods

    fn printOptionsSection(_: *CliFormatter, cli_config: anytype, _: u32) !void {
        const OptsT = @TypeOf(cli_config.options);
        const OptsInfo = @typeInfo(OptsT).@"struct";

        if (OptsInfo.fields.len == 0) return;

        print("⚙️  OPTIONS:\n\n", .{});

        inline for (OptsInfo.fields) |field| {
            const opt = @field(cli_config.options, field.name);

            // Simple formatted output
            if (@hasField(@TypeOf(opt), "short")) {
                const short_char: u8 = @intCast(opt.short);
                print("  -{c}, --{s} <{s}>    {s}", .{ short_char, opt.long, opt.type, opt.description });
            } else {
                print("      --{s} <{s}>    {s}", .{ opt.long, opt.type, opt.description });
            }

            // Default value
            if (@hasField(@TypeOf(opt), "default")) {
                if (comptime std.mem.eql(u8, opt.long, "model")) {
                    print(" [default: {s}]", .{opt.default});
                } else {
                    print(" [default: {}]", .{opt.default});
                }
            }
            print("\n", .{});
        }

        print("\n", .{});
    }

    /// Print examples section from CLI configuration
    pub fn printExamplesSection(self: *CliFormatter, cli_config: anytype, width: u16) !void {
        _ = width; // unused parameter
        print("{s}💡 EXAMPLES:{s}\n\n", .{ self.colors.bold, self.colors.reset });

        // Check if examples exist in config
        if (@hasField(@TypeOf(cli_config), "examples")) {
            const examples = cli_config.examples;
            // Try to iterate over examples array
            inline for (examples) |example| {
                if (@hasField(@TypeOf(example), "command")) {
                    print("      {s}\n", .{example.command});
                } else if (@hasField(@TypeOf(example), "description")) {
                    print("      {s}\n", .{example.description});
                } else {
                    // Handle as string directly
                    print("      {s}\n", .{example});
                }
            }
        }

        // Always include tui-demo as it's a core feature
        print("      docz tui-demo\n", .{});
        print("\n", .{});
    }

    /// Print links section (stub implementation)
    pub fn printLinksSection(self: *CliFormatter, width: u16) !void {
        _ = width; // unused parameter
        print("{s}🔗 LINKS:{s}\n\n", .{ self.colors.bold, self.colors.reset });
        print("      Repository: https://github.com/username/docz\n", .{});
        print("      Documentation: https://docs.docz.dev\n", .{});
        print("\n", .{});
    }
};

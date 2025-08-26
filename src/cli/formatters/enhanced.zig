//! Enhanced CLI output formatter leveraging @src/term capabilities and TUI system
//! Provides rich formatting, adaptive colors, hyperlinks, and clipboard integration

const std = @import("std");
const print = std.debug.print;
// const tui = @import("tui_shared"); // Disabled to avoid module conflicts
const caps_mod = @import("../../term/caps.zig");

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
const color_mod = @import("../../term/ansi/color.zig");
const sgr_mod = @import("../../term/ansi/sgr.zig");
const hyperlink_mod = @import("../../term/ansi/hyperlink.zig");
const clipboard_mod = @import("../../term/ansi/clipboard.zig");
const notification_mod = @import("../../term/ansi/notification.zig");
const title_mod = @import("../../term/ansi/title.zig");

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
            return caps_mod.TermCaps.basic();
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

        const usage_section = tui.Section.init("🚀 USAGE", &usage_content, width);
        usage_section.draw();
        print("\n");

        // Options section with enhanced formatting
        try self.printOptionsSection(cli_config, width);

        // Examples section with copy-to-clipboard integration
        try self.printExamplesSection(cli_config, width);

        // Links section with hyperlinks
        try self.printLinksSection(width);

        // Send completion notification if supported
        // Note: notification would need proper writer implementation
    }

    /// Enhanced error display with structured formatting
    pub fn printEnhancedError(self: *CliFormatter, err: anytype, context: ?[]const u8) !void {
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

        var error_content = std.ArrayList([]const u8).init(self.allocator);
        defer error_content.deinit();

        try error_content.append("");
        try error_content.append(error_msg);
        if (context) |ctx| {
            const ctx_line = try std.fmt.allocPrint(self.allocator, "Context: {s}", .{ctx});
            try error_content.append(ctx_line);
        }
        try error_content.append("");
        try error_content.append("💡 Use --help for usage information");
        try error_content.append("");

        const error_section = tui.Section.init("Error Details", error_content.items, width);
        error_section.draw();
        print("\n");
    }

    /// Enhanced version display with system info
    pub fn printEnhancedVersion(self: *CliFormatter, cli_config: anytype) !void {
        const width = @min(self.terminal_size.width, 80);

        print("{s}{s}DocZ{s}", .{ self.colors.bold, self.colors.primary, self.colors.reset });
        if (@hasField(@TypeOf(cli_config), "version")) {
            print(" version {s}{s}{s}\n", .{ self.colors.accent, cli_config.version, self.colors.reset });
        } else {
            print(" version {s}0.1.0{s}\n", .{ self.colors.accent, self.colors.reset });
        }

        // Terminal capabilities info
        var caps_content = std.ArrayList([]const u8).init(self.allocator);
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

        const caps_section = tui.Section.init("System Information", caps_content.items, width);
        caps_section.draw();
        print("\n");
    }

    /// Copy text to system clipboard if supported
    pub fn copyToClipboard(self: *CliFormatter, text: []const u8) !bool {
        if (!self.caps.supportsClipboardOsc52) return false;

        clipboard_mod.writeClipboard(self.writer, self.allocator, self.caps, text) catch return false;

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

        print("⚙️  OPTIONS:\n\n");

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
            print("\n");
        }

        print("\n");
    }
};

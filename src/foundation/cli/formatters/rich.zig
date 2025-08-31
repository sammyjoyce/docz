//! CLI output formatter leveraging @src/term capabilities and TUI system
//! Provides rich formatting, adaptive colors, hyperlinks, clipboard integration

const std = @import("std");
// const components = @import("../../components.zig");
const termMod = @import("../../term.zig");
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
pub const Formatter = struct {
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

    pub fn init(allocator: std.mem.Allocator) !Formatter {
        const terminal = try term.Terminal.init(allocator);
        const terminalSize = BasicTui.TerminalSize{ .width = 80, .height = 24 };

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

        return Formatter{
            .allocator = allocator,
            .caps = terminal.caps,
            .terminalSize = terminalSize,
            .terminal = terminal,
            .styles = styles,
        };
    }

    /// Help display with structured layout and hyperlinks
    pub fn printHelp(self: *Formatter, cli_config: anytype) !void {
        const width = @min(self.terminalSize.width, 80);

        // Header section with styling
        try self.terminal.printf("{s}DocZ{s}", .{ self.styles.bold, term.Style{} }, self.styles.primary);
        if (@hasField(@TypeOf(cli_config), "version")) {
            try self.terminal.printf(" {s}v{s}{s}", .{ self.styles.muted, cli_config.version, term.Style{} }, null);
        }
        try self.terminal.printf(" - {s}{s}{s}\n\n", .{ self.styles.secondary, cli_config.description, term.Style{} }, null);

        // Usage section with structured layout
        const usageContent = [_][]const u8{
            "",
            "Basic usage patterns:",
            "",
            "  docz [OPTIONS] [FLAGS] [PROMPT]",
            "  docz auth <SUBCOMMAND>",
            "",
        };

        // Print usage section manually
        try self.terminal.printf("🚀 USAGE\n", .{}, self.styles.bold);
        try self.terminal.printf("\n", .{}, self.styles.dim);
        for (usageContent) |line| {
            try self.terminal.printf("  {s}\n", .{line}, null);
        }
        try self.terminal.printf("\n", .{}, term.Style{});

        // Options section with formatting
        try self.printOptionsSection(cli_config, @intCast(width));

        // Examples section with copy-to-clipboard integration
        try self.printExamplesSection(cli_config, width);

        // Links section with hyperlinks
        try self.printLinksSection(width);
    }

    /// Error display with structured formatting
    pub fn printError(self: *Formatter, err: anytype, context: ?[]const u8) !void {
        // Error header with icon and color
        try self.terminal.printf("\n❌ Error\n", .{}, self.styles.errColor);

        // Error message with context-aware handling
        var errorMsg: []const u8 = undefined;
        var showAuthHelp = false;

        switch (err) {
            error.InvalidArgument => errorMsg = "Invalid argument provided",
            error.MissingValue => errorMsg = "Missing value for option",
            error.UnknownOption => errorMsg = "Unknown option",
            error.InvalidValue => errorMsg = "Invalid value for option",
            error.MutuallyExclusiveOptions => errorMsg = "Mutually exclusive options provided",
            error.OutOfMemory => errorMsg = "Out of memory",
            error.UnknownCommand => errorMsg = "Unknown command",
            error.UnknownSubcommand => {
                // Check if this is an auth-related error
                if (context) |ctx| {
                    if (std.mem.eql(u8, ctx, "auth") or std.mem.startsWith(u8, ctx, "auth ")) {
                        errorMsg = "Missing or invalid subcommand for 'auth'";
                        showAuthHelp = true;
                    } else {
                        errorMsg = "Unknown subcommand";
                    }
                } else {
                    errorMsg = "Unknown subcommand";
                }
            },
            else => errorMsg = "An unexpected error occurred",
        }

        var errorContent = std.array_list.Managed([]const u8).init(self.allocator);
        defer errorContent.deinit();

        try errorContent.append("");
        try errorContent.append(errorMsg);
        try errorContent.append("");
        try errorContent.append("💡 Use --help for usage information");
        try errorContent.append("");

        // Print error section manually
        try self.terminal.printf("Error Details\n", .{}, self.styles.errColor);
        try self.terminal.printf("\n", .{}, self.styles.dim);

        // Print context if available
        if (context) |ctx| {
            const ctxLine = try std.fmt.allocPrint(self.allocator, "Context: {s}", .{ctx});
            defer self.allocator.free(ctxLine);
            try self.terminal.printf("  {s}\n", .{ctxLine}, null);
        }

        // Print auth-specific help if needed
        if (showAuthHelp) {
            try self.terminal.printf("\n", .{}, null);
            const title = try std.fmt.allocPrint(self.allocator, "Available auth subcommands:", .{});
            defer self.allocator.free(title);
            try self.terminal.printf("  {s}\n", .{title}, null);

            // Use comptime reflection to generate subcommand list
            const authSubcommands = comptime blk: {
                const AuthSubcommand = @import("../../cli/core/types.zig").AuthSubcommand;
                const info = @typeInfo(AuthSubcommand).@"enum";
                var cmds: [info.fields.len][]const u8 = undefined;

                for (info.fields, 0..) |field, i| {
                    cmds[i] = field.name;
                }

                break :blk cmds;
            };

            // Generate descriptions for each subcommand
            inline for (authSubcommands) |cmd| {
                const description = comptime blk: {
                    if (std.mem.eql(u8, cmd, "login")) {
                        break :blk "Start authentication process";
                    } else if (std.mem.eql(u8, cmd, "status")) {
                        break :blk "Check authentication status";
                    } else if (std.mem.eql(u8, cmd, "refresh")) {
                        break :blk "Refresh authentication token";
                    } else {
                        break :blk "Unknown subcommand";
                    }
                };

                const line = try std.fmt.allocPrint(self.allocator, "  • {s}   - {s}", .{ cmd, description });
                defer self.allocator.free(line);
                try self.terminal.printf("  {s}\n", .{line}, null);
            }

            try self.terminal.printf("\n", .{}, null);
            const example = try std.fmt.allocPrint(self.allocator, "Example: docz auth login", .{});
            defer self.allocator.free(example);
            try self.terminal.printf("  {s}\n", .{example}, null);
        }

        for (errorContent.items) |line| {
            try self.terminal.printf("  {s}\n", .{line}, null);
        }
        try self.terminal.printf("\n", .{}, term.Style{});
    }

    /// Version display with system info
    pub fn printVersion(self: *Formatter, cli_config: anytype) !void {
        try self.terminal.printf("{s}DocZ{s}", .{ self.styles.bold, term.Style{} }, self.styles.primary);
        if (@hasField(@TypeOf(cli_config), "version")) {
            try self.terminal.printf(" version {s}{s}{s}\n", .{ self.styles.accent, cli_config.version, term.Style{} }, null);
        } else {
            try self.terminal.printf(" version {s}0.1.0{s}\n", .{ self.styles.accent, term.Style{} }, null);
        }

        // Terminal capabilities info
        var capsContent = std.array_list.Managed([]const u8).init(self.allocator);
        defer capsContent.deinit();

        try capsContent.append("");
        try capsContent.append("🖥️  Terminal Capabilities:");
        try capsContent.append("");

        const sizeInfo = try std.fmt.allocPrint(self.allocator, "   Size: {}×{} characters", .{ self.terminalSize.width, self.terminalSize.height });
        try capsContent.append(sizeInfo);

        const truecolorStatus = if (self.caps.supportsTruecolor) "✅ Supported" else "❌ Not supported";
        const truecolorLine = try std.fmt.allocPrint(self.allocator, "   Truecolor: {s}", .{truecolorStatus});
        try capsContent.append(truecolorLine);

        const hyperlinksStatus = if (self.caps.supportsHyperlinkOsc8) "✅ Supported" else "❌ Not supported";
        const hyperlinksLine = try std.fmt.allocPrint(self.allocator, "   Hyperlinks: {s}", .{hyperlinksStatus});
        try capsContent.append(hyperlinksLine);

        const clipboardStatus = if (self.caps.supportsClipboardOsc52) "✅ Supported" else "❌ Not supported";
        const clipboardLine = try std.fmt.allocPrint(self.allocator, "   Clipboard: {s}", .{clipboardStatus});
        try capsContent.append(clipboardLine);

        try capsContent.append("");

        // Print system information section manually
        try self.terminal.printf("System Information\n", .{}, self.styles.bold);
        try self.terminal.printf("\n", .{}, self.styles.dim);
        for (capsContent.items) |line| {
            try self.terminal.printf("  {s}\n", .{line}, null);
        }
        try self.terminal.printf("\n", .{}, term.Style{});

        // Free allocated strings
        self.allocator.free(sizeInfo);
        self.allocator.free(truecolorLine);
        self.allocator.free(hyperlinksLine);
        self.allocator.free(clipboardLine);
    }

    pub fn deinit(self: *Formatter) void {
        self.terminal.deinit();
    }

    /// Copy text to system clipboard if supported
    pub fn copyToClipboard(self: *Formatter, text: []const u8) !bool {
        if (!self.caps.supportsClipboardOsc52) return false;

        try self.terminal.copyToClipboard(text);
        try self.terminal.printf("📋 Copied to clipboard\n", .{}, self.styles.muted);
        return true;
    }

    /// Progress indicator
    pub fn showProgress(self: *Formatter, message: []const u8, current: u32, total: u32) !void {
        const percent = if (total > 0) (current * 100) / total else 0;
        const barWidth = @min(40, self.terminalSize.width - 20);
        const filled = (percent * barWidth) / 100;

        try self.terminal.printf("\r{s} [", .{message}, self.styles.primary);

        var i: u32 = 0;
        while (i < barWidth) : (i += 1) {
            if (i < filled) {
                try self.terminal.printf("█", .{}, self.styles.accent);
            } else {
                try self.terminal.printf("░", .{}, null);
            }
        }

        try self.terminal.printf("] {d}%", .{percent}, self.styles.muted);
    }

    /// Finish progress and clear line
    pub fn finishProgress(self: *Formatter, message: []const u8) !void {
        try self.terminal.printf("\r✅ {s}\n", .{message}, self.styles.success);
    }

    // Private helper methods

    fn printOptionsSection(self: *Formatter, cli_config: anytype, _: u32) !void {
        const OptsT = @TypeOf(cli_config.options);
        const OptsInfo = @typeInfo(OptsT).@"struct";

        if (OptsInfo.fields.len == 0) return;

        try self.terminal.printf("⚙️  OPTIONS:\n\n", .{}, null);

        inline for (OptsInfo.fields) |field| {
            const opt = @field(cli_config.options, field.name);

            // Simple formatted output
            if (@hasField(@TypeOf(opt), "short")) {
                const shortChar: u8 = @intCast(opt.short);
                try self.terminal.printf("  -{c}, --{s} <{s}>    {s}", .{ shortChar, opt.long, opt.type, opt.description }, self.styles.accent);
            } else {
                try self.terminal.printf("      --{s} <{s}>    {s}", .{ opt.long, opt.type, opt.description }, self.styles.accent);
            }

            // Default value
            if (@hasField(@TypeOf(opt), "default")) {
                if (comptime std.mem.eql(u8, opt.long, "model")) {
                    try self.terminal.printf(" [default: {s}]", .{opt.default}, self.styles.muted);
                } else {
                    try self.terminal.printf(" [default: {}]", .{opt.default}, self.styles.muted);
                }
            }
            try self.terminal.printf("\n", .{}, null);
        }

        try self.terminal.printf("\n", .{}, null);
    }

    /// Print examples section from CLI configuration
    pub fn printExamplesSection(self: *Formatter, cli_config: anytype, width: u16) !void {
        _ = width; // unused parameter
        try self.terminal.printf("💡 EXAMPLES:\n\n", .{}, self.styles.bold);

        // Check if examples exist in config
        if (@hasField(@TypeOf(cli_config), "examples")) {
            const examples = cli_config.examples;
            // Try to iterate over examples array
            inline for (examples) |example| {
                if (@hasField(@TypeOf(example), "command")) {
                    try self.terminal.printf("      {s}\n", .{example.command}, null);
                } else if (@hasField(@TypeOf(example), "description")) {
                    try self.terminal.printf("      {s}\n", .{example.description}, null);
                } else {
                    // Handle as string directly
                    try self.terminal.printf("      {s}\n", .{example}, null);
                }
            }
        }

        // Always include tui-demo as it's a core feature
        try self.terminal.printf("      docz tui-demo\n", .{}, null);
        try self.terminal.printf("\n", .{}, null);
    }

    /// Print links section (stub implementation)
    pub fn printLinksSection(self: *Formatter, width: u16) !void {
        _ = width; // unused parameter
        try self.terminal.printf("🔗 LINKS:\n\n", .{}, self.styles.bold);
        try self.terminal.printf("      Repository: https://github.com/username/docz\n", .{}, null);
        try self.terminal.printf("      Documentation: https://docs.docz.dev\n", .{}, null);
        try self.terminal.printf("\n", .{}, null);
    }
};

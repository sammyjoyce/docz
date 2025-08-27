//! Theme Export/Import Functionality
//! Handles exporting themes to various formats and importing from external sources

const std = @import("std");
const ColorScheme = @import("color_scheme.zig").ColorScheme;
const Color = @import("color_scheme.zig").Color;
const RGB = @import("color_scheme.zig").RGB;

pub const ThemeExporter = struct {
    allocator: std.mem.Allocator,

    pub const ExportFormat = enum {
        zon, // Native Zig Object Notation
        json, // JSON format
        yaml, // YAML format
        toml, // TOML format
        css, // CSS variables
        iterm2, // iTerm2 color scheme
        terminal, // Windows Terminal
        vscode, // VS Code theme
        sublime, // Sublime Text theme
        vim, // Vim colorscheme
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Export theme to specified format
    pub fn exportTheme(self: *Self, theme: *ColorScheme, format: ExportFormat) ![]u8 {
        return switch (format) {
            .zon => try self.exportToZon(theme),
            .json => try self.exportToJson(theme),
            .yaml => try self.exportToYaml(theme),
            .toml => try self.exportToToml(theme),
            .css => try self.exportToCss(theme),
            .iterm2 => try self.exportToITerm2(theme),
            .terminal => try self.exportToWindowsTerminal(theme),
            .vscode => try self.exportToVSCode(theme),
            .sublime => try self.exportToSublime(theme),
            .vim => try self.exportToVim(theme),
        };
    }

    /// Export to ZON format
    fn exportToZon(self: *Self, theme: *ColorScheme) ![]u8 {
        return try theme.toZon(self.allocator);
    }

    /// Export to JSON format
    fn exportToJson(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"name\": \"{s}\",\n", .{theme.name});
        try writer.print("  \"description\": \"{s}\",\n", .{theme.description});
        try writer.print("  \"author\": \"{s}\",\n", .{theme.author});
        try writer.print("  \"version\": \"{s}\",\n", .{theme.version});
        try writer.print("  \"is_dark\": {},\n", .{theme.is_dark});

        try writer.writeAll("  \"colors\": {\n");
        try self.writeJsonColor(writer, "background", theme.background, false);
        try self.writeJsonColor(writer, "foreground", theme.foreground, false);
        try self.writeJsonColor(writer, "cursor", theme.cursor, false);
        try self.writeJsonColor(writer, "selection", theme.selection, false);

        try self.writeJsonColor(writer, "black", theme.black, false);
        try self.writeJsonColor(writer, "red", theme.red, false);
        try self.writeJsonColor(writer, "green", theme.green, false);
        try self.writeJsonColor(writer, "yellow", theme.yellow, false);
        try self.writeJsonColor(writer, "blue", theme.blue, false);
        try self.writeJsonColor(writer, "magenta", theme.magenta, false);
        try self.writeJsonColor(writer, "cyan", theme.cyan, false);
        try self.writeJsonColor(writer, "white", theme.white, true);
        try writer.writeAll("  }\n");

        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    fn writeJsonColor(self: *Self, writer: anytype, name: []const u8, color: Color, is_last: bool) !void {
        const hex = try color.rgb.toHex(self.allocator);
        defer self.allocator.free(hex);

        try writer.print("    \"{s}\": \"{s}\"", .{ name, hex });
        if (!is_last) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    /// Export to YAML format
    fn exportToYaml(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.print("name: {s}\n", .{theme.name});
        try writer.print("description: {s}\n", .{theme.description});
        try writer.print("author: {s}\n", .{theme.author});
        try writer.print("version: {s}\n", .{theme.version});
        try writer.print("is_dark: {}\n", .{theme.is_dark});
        try writer.writeAll("\ncolors:\n");

        try self.writeYamlColor(writer, "background", theme.background);
        try self.writeYamlColor(writer, "foreground", theme.foreground);
        try self.writeYamlColor(writer, "cursor", theme.cursor);
        try self.writeYamlColor(writer, "selection", theme.selection);

        return buffer.toOwnedSlice();
    }

    fn writeYamlColor(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        const hex = try color.rgb.toHex(self.allocator);
        defer self.allocator.free(hex);

        try writer.print("  {s}: \"{s}\"\n", .{ name, hex });
    }

    /// Export to TOML format
    fn exportToToml(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.writeAll("[theme]\n");
        try writer.print("name = \"{s}\"\n", .{theme.name});
        try writer.print("description = \"{s}\"\n", .{theme.description});
        try writer.print("author = \"{s}\"\n", .{theme.author});
        try writer.print("version = \"{s}\"\n", .{theme.version});
        try writer.print("is_dark = {}\n", .{theme.is_dark});

        try writer.writeAll("\n[colors]\n");
        try self.writeTomlColor(writer, "background", theme.background);
        try self.writeTomlColor(writer, "foreground", theme.foreground);

        return buffer.toOwnedSlice();
    }

    fn writeTomlColor(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        const hex = try color.rgb.toHex(self.allocator);
        defer self.allocator.free(hex);

        try writer.print("{s} = \"{s}\"\n", .{ name, hex });
    }

    /// Export to CSS variables
    fn exportToCss(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.writeAll(":root {\n");
        try writer.print("  /* {s} Theme */\n", .{theme.name});
        try writer.print("  /* Author: {s} */\n", .{theme.author});
        try writer.print("  /* {s} */\n\n", .{theme.description});

        try self.writeCssVariable(writer, "--background", theme.background);
        try self.writeCssVariable(writer, "--foreground", theme.foreground);
        try self.writeCssVariable(writer, "--cursor", theme.cursor);
        try self.writeCssVariable(writer, "--selection", theme.selection);

        try self.writeCssVariable(writer, "--primary", theme.primary);
        try self.writeCssVariable(writer, "--secondary", theme.secondary);
        try self.writeCssVariable(writer, "--success", theme.success);
        try self.writeCssVariable(writer, "--warning", theme.warning);
        try self.writeCssVariable(writer, "--error", theme.error_color);
        try self.writeCssVariable(writer, "--info", theme.info);

        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    fn writeCssVariable(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        const hex = try color.rgb.toHex(self.allocator);
        defer self.allocator.free(hex);

        try writer.print("  {s}: {s};\n", .{ name, hex });
    }

    /// Export to iTerm2 format
    fn exportToITerm2(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try writer.writeAll("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
        try writer.writeAll("<plist version=\"1.0\">\n");
        try writer.writeAll("<dict>\n");

        try self.writeITerm2Color(writer, "Background Color", theme.background);
        try self.writeITerm2Color(writer, "Foreground Color", theme.foreground);
        try self.writeITerm2Color(writer, "Cursor Color", theme.cursor);
        try self.writeITerm2Color(writer, "Selection Color", theme.selection);

        // ANSI colors
        try self.writeITerm2Color(writer, "Ansi 0 Color", theme.black);
        try self.writeITerm2Color(writer, "Ansi 1 Color", theme.red);
        try self.writeITerm2Color(writer, "Ansi 2 Color", theme.green);
        try self.writeITerm2Color(writer, "Ansi 3 Color", theme.yellow);
        try self.writeITerm2Color(writer, "Ansi 4 Color", theme.blue);
        try self.writeITerm2Color(writer, "Ansi 5 Color", theme.magenta);
        try self.writeITerm2Color(writer, "Ansi 6 Color", theme.cyan);
        try self.writeITerm2Color(writer, "Ansi 7 Color", theme.white);

        try writer.writeAll("</dict>\n");
        try writer.writeAll("</plist>\n");

        return buffer.toOwnedSlice();
    }

    fn writeITerm2Color(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        _ = self;
        try writer.print("  <key>{s}</key>\n", .{name});
        try writer.writeAll("  <dict>\n");

        const r = @as(f32, @floatFromInt(color.rgb.r)) / 255.0;
        const g = @as(f32, @floatFromInt(color.rgb.g)) / 255.0;
        const b = @as(f32, @floatFromInt(color.rgb.b)) / 255.0;

        try writer.print("    <key>Red Component</key>\n    <real>{d}</real>\n", .{r});
        try writer.print("    <key>Green Component</key>\n    <real>{d}</real>\n", .{g});
        try writer.print("    <key>Blue Component</key>\n    <real>{d}</real>\n", .{b});

        try writer.writeAll("  </dict>\n");
    }

    /// Export to Windows Terminal format
    fn exportToWindowsTerminal(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"name\": \"{s}\",\n", .{theme.name});

        const bg_hex = try theme.background.rgb.toHex(self.allocator);
        defer self.allocator.free(bg_hex);
        const fg_hex = try theme.foreground.rgb.toHex(self.allocator);
        defer self.allocator.free(fg_hex);
        const cursor_hex = try theme.cursor.rgb.toHex(self.allocator);
        defer self.allocator.free(cursor_hex);
        const selection_hex = try theme.selection.rgb.toHex(self.allocator);
        defer self.allocator.free(selection_hex);

        try writer.print("  \"background\": \"{s}\",\n", .{bg_hex});
        try writer.print("  \"foreground\": \"{s}\",\n", .{fg_hex});
        try writer.print("  \"cursorColor\": \"{s}\",\n", .{cursor_hex});
        try writer.print("  \"selectionBackground\": \"{s}\",\n", .{selection_hex});

        // Write ANSI colors
        const black_hex = try theme.black.rgb.toHex(self.allocator);
        defer self.allocator.free(black_hex);
        try writer.print("  \"black\": \"{s}\",\n", .{black_hex});

        const red_hex = try theme.red.rgb.toHex(self.allocator);
        defer self.allocator.free(red_hex);
        try writer.print("  \"red\": \"{s}\"\n", .{red_hex});

        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    /// Export to VS Code theme format
    fn exportToVSCode(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.writeAll("{\n");
        try writer.print("  \"name\": \"{s}\",\n", .{theme.name});
        try writer.writeAll("  \"type\": ");
        if (theme.is_dark) {
            try writer.writeAll("\"dark\",\n");
        } else {
            try writer.writeAll("\"light\",\n");
        }

        try writer.writeAll("  \"colors\": {\n");

        const bg_hex = try theme.background.rgb.toHex(self.allocator);
        defer self.allocator.free(bg_hex);
        const fg_hex = try theme.foreground.rgb.toHex(self.allocator);
        defer self.allocator.free(fg_hex);

        try writer.print("    \"editor.background\": \"{s}\",\n", .{bg_hex});
        try writer.print("    \"editor.foreground\": \"{s}\",\n", .{fg_hex});

        const cursor_hex = try theme.cursor.rgb.toHex(self.allocator);
        defer self.allocator.free(cursor_hex);
        try writer.print("    \"editorCursor.foreground\": \"{s}\",\n", .{cursor_hex});

        const selection_hex = try theme.selection.rgb.toHex(self.allocator);
        defer self.allocator.free(selection_hex);
        try writer.print("    \"editor.selectionBackground\": \"{s}\"\n", .{selection_hex});

        try writer.writeAll("  }\n");
        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    /// Export to Sublime Text format
    fn exportToSublime(self: *Self, theme: *ColorScheme) ![]u8 {
        // Similar to VS Code format but with Sublime-specific keys
        return try self.exportToJson(theme);
    }

    /// Export to Vim colorscheme format
    fn exportToVim(self: *Self, theme: *ColorScheme) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();

        try writer.print("\" Vim color scheme: {s}\n", .{theme.name});
        try writer.print("\" Author: {s}\n", .{theme.author});
        try writer.print("\" {s}\n\n", .{theme.description});

        try writer.writeAll("set background=");
        if (theme.is_dark) {
            try writer.writeAll("dark\n");
        } else {
            try writer.writeAll("light\n");
        }

        try writer.writeAll("highlight clear\n");
        try writer.writeAll("if exists(\"syntax_on\")\n");
        try writer.writeAll("  syntax reset\n");
        try writer.writeAll("endif\n\n");

        try writer.print("let g:colors_name = \"{s}\"\n\n", .{theme.name});

        // Write color definitions
        try self.writeVimHighlight(writer, "Normal", theme.foreground, theme.background);
        try self.writeVimHighlight(writer, "Cursor", theme.cursor, null);
        try self.writeVimHighlight(writer, "Visual", null, theme.selection);

        return buffer.toOwnedSlice();
    }

    fn writeVimHighlight(self: *Self, writer: anytype, group: []const u8, fg: ?Color, bg: ?Color) !void {
        _ = self;
        try writer.print("highlight {s}", .{group});

        if (fg) |color| {
            try writer.print(" guifg=#{x:0>2}{x:0>2}{x:0>2}", .{ color.rgb.r, color.rgb.g, color.rgb.b });
            try writer.print(" ctermfg={}", .{color.ansi256});
        }

        if (bg) |color| {
            try writer.print(" guibg=#{x:0>2}{x:0>2}{x:0>2}", .{ color.rgb.r, color.rgb.g, color.rgb.b });
            try writer.print(" ctermbg={}", .{color.ansi256});
        }

        try writer.writeAll("\n");
    }
};

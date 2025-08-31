const std = @import("std");
const term = @import("../term.zig");
const caps_mod = term;
const QualityTiers = @import("quality_tiers.zig").QualityTiers;
const render_mod = @import("../render.zig");
const Renderer = render_mod.Renderer;
const RenderMode = render_mod.RenderTier;
const ColorUnion = term.ansi.color.Color;
const Color = term.ansi.color.BasicColor;
const RGBColor = term.ansi.color.RGBColor;
const hyperlink = term.ansi.hyperlink;

/// Options for markdown rendering
pub const MarkdownOptions = struct {
    /// Maximum width for text wrapping
    maxWidth: usize = 80,
    /// Enable terminal color output
    colorEnabled: bool = true,
    /// Render quality tier (affects visual elements)
    qualityTier: RenderMode = .standard,
    /// Enable hyperlinks (OSC 8) when supported
    enableHyperlinks: bool = true,
    /// Indentation for nested elements
    indentSize: usize = 2,
    /// Enable syntax highlighting in code blocks
    enableSyntaxHighlight: bool = true,
    /// Show line numbers in code blocks
    showLineNumbers: bool = false,
    /// Table alignment padding
    tablePadding: usize = 1,
};

/// Markdown element types for parsing
const MarkdownElement = union(enum) {
    heading: Heading,
    paragraph: []const u8,
    bold: []const u8,
    italic: []const u8,
    bold_italic: []const u8,
    inline_code: []const u8,
    code_block: CodeBlock,
    link: Link,
    list_item: ListItem,
    blockquote: []const u8,
    horizontal_rule: void,
    table: Table,
    text: []const u8,

    const Heading = struct {
        level: u8, // 1-6
        text: []const u8,
    };

    const CodeBlock = struct {
        language: ?[]const u8,
        content: []const u8,
    };

    const Link = struct {
        text: []const u8,
        url: []const u8,
    };

    const ListItem = struct {
        ordered: bool,
        level: usize,
        index: ?usize, // For ordered lists
        text: []const u8,
    };

    const Table = struct {
        headers: [][]const u8,
        alignments: []Alignment,
        rows: [][]const []const u8,

        const Alignment = enum {
            left,
            center,
            right,
        };
    };
};

/// Color scheme for different markdown elements based on quality tier
const ColorScheme = struct {
    headingColors: [6]ColorUnion,
    boldColor: ?ColorUnion,
    italicColor: ?ColorUnion,
    codeBg: ?ColorUnion,
    codeFg: ?ColorUnion,
    linkColor: ?ColorUnion,
    blockquoteColor: ?ColorUnion,
    tableBorderColor: ?ColorUnion,

    pub fn getForTier(tier: RenderMode) ColorScheme {
        return switch (tier) {
            .rich => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .rgb = RGBColor{ .r = 255, .g = 107, .b = 107 } }, // H1 - bright red
                    ColorUnion{ .rgb = RGBColor{ .r = 255, .g = 193, .b = 107 } }, // H2 - bright orange
                    ColorUnion{ .rgb = RGBColor{ .r = 255, .g = 255, .b = 107 } }, // H3 - bright yellow
                    ColorUnion{ .rgb = RGBColor{ .r = 107, .g = 255, .b = 107 } }, // H4 - bright green
                    ColorUnion{ .rgb = RGBColor{ .r = 107, .g = 193, .b = 255 } }, // H5 - bright cyan
                    ColorUnion{ .rgb = RGBColor{ .r = 193, .g = 107, .b = 255 } }, // H6 - bright purple
                },
                .boldColor = ColorUnion{ .basic = .bright_white },
                .italicColor = ColorUnion{ .basic = .bright_cyan },
                .codeBg = ColorUnion{ .rgb = RGBColor{ .r = 40, .g = 40, .b = 40 } },
                .codeFg = ColorUnion{ .rgb = RGBColor{ .r = 107, .g = 255, .b = 107 } },
                .linkColor = ColorUnion{ .rgb = RGBColor{ .r = 107, .g = 193, .b = 255 } },
                .blockquoteColor = ColorUnion{ .basic = .bright_black },
                .tableBorderColor = ColorUnion{ .basic = .bright_blue },
            },
            .standard => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .basic = .bright_red },
                    ColorUnion{ .basic = .bright_yellow },
                    ColorUnion{ .basic = .bright_green },
                    ColorUnion{ .basic = .bright_cyan },
                    ColorUnion{ .basic = .bright_blue },
                    ColorUnion{ .basic = .bright_magenta },
                },
                .boldColor = ColorUnion{ .basic = .bright_white },
                .italicColor = ColorUnion{ .basic = .cyan },
                .codeBg = null,
                .codeFg = ColorUnion{ .basic = .green },
                .linkColor = ColorUnion{ .basic = .blue },
                .blockquoteColor = ColorUnion{ .basic = .bright_black },
                .tableBorderColor = ColorUnion{ .basic = .blue },
            },
            .compatible => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .basic = .red },
                    ColorUnion{ .basic = .yellow },
                    ColorUnion{ .basic = .green },
                    ColorUnion{ .basic = .cyan },
                    ColorUnion{ .basic = .blue },
                    ColorUnion{ .basic = .magenta },
                },
                .boldColor = null,
                .italicColor = null,
                .codeBg = null,
                .codeFg = null,
                .linkColor = null,
                .blockquoteColor = null,
                .tableBorderColor = null,
            },
            .minimal => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .basic = .white },
                    ColorUnion{ .basic = .white },
                    ColorUnion{ .basic = .white },
                    ColorUnion{ .basic = .white },
                    ColorUnion{ .basic = .white },
                    ColorUnion{ .basic = .white },
                },
                .boldColor = null,
                .italicColor = null,
                .codeBg = null,
                .codeFg = null,
                .linkColor = null,
                .blockquoteColor = null,
                .tableBorderColor = null,
            },
        };
    }
};

/// Main markdown renderer
pub const Markdown = struct {
    allocator: std.mem.Allocator,
    options: MarkdownOptions,
    colorScheme: ColorScheme,
    output: std.ArrayList(u8),
    capabilities: ?caps_mod.TermCaps,

    pub fn init(allocator: std.mem.Allocator, options: MarkdownOptions) Markdown {
        return Markdown{
            .allocator = allocator,
            .options = options,
            .colorScheme = ColorScheme.getForTier(options.qualityTier),
            .output = std.ArrayList(u8).init(allocator),
            .capabilities = null, // Can be set if terminal capabilities are known
        };
    }

    pub fn deinit(self: *Markdown) void {
        self.output.deinit();
    }

    /// Set terminal capabilities for advanced features
    pub fn setCapabilities(self: *Markdown, caps: caps_mod.TermCaps) void {
        self.capabilities = caps;
    }

    /// Main entry point - render markdown to formatted terminal output
    pub fn renderMarkdown(self: *Markdown, markdown: []const u8) ![]u8 {
        self.output.clearRetainingCapacity();

        var lines = std.mem.tokenize(u8, markdown, "\n");
        var in_code_block = false;
        var code_block_content = std.ArrayList(u8).init(self.allocator);
        defer code_block_content.deinit();
        var code_block_lang: ?[]const u8 = null;

        while (lines.next()) |line| {
            // Handle code blocks
            if (std.mem.startsWith(u8, line, "```")) {
                if (in_code_block) {
                    // End code block
                    try self.renderCodeBlock(code_block_lang, code_block_content.items);
                    code_block_content.clearRetainingCapacity();
                    code_block_lang = null;
                    in_code_block = false;
                } else {
                    // Start code block
                    in_code_block = true;
                    if (line.len > 3) {
                        code_block_lang = std.mem.trim(u8, line[3..], " \t");
                    }
                }
                continue;
            }

            if (in_code_block) {
                if (code_block_content.items.len > 0) {
                    try code_block_content.append('\n');
                }
                try code_block_content.appendSlice(line);
                continue;
            }

            // Parse and render line
            try self.renderLine(line);
        }

        // Handle unclosed code block
        if (in_code_block) {
            try self.renderCodeBlock(code_block_lang, code_block_content.items);
        }

        return try self.output.toOwnedSlice();
    }

    fn renderLine(self: *Markdown, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Horizontal rule
        if (trimmed.len >= 3 and (std.mem.eql(u8, trimmed[0..3], "---") or
            std.mem.eql(u8, trimmed[0..3], "***") or
            std.mem.eql(u8, trimmed[0..3], "___")))
        {
            try self.renderHorizontalRule();
            return;
        }

        // Headings
        if (trimmed.len > 0 and trimmed[0] == '#') {
            var level: u8 = 0;
            var i: usize = 0;
            while (i < trimmed.len and trimmed[i] == '#' and level < 6) : (i += 1) {
                level += 1;
            }
            if (i < trimmed.len and trimmed[i] == ' ') {
                const heading_text = std.mem.trim(u8, trimmed[i..], " \t#");
                try self.renderHeading(level, heading_text);
                return;
            }
        }

        // Blockquotes
        if (trimmed.len > 0 and trimmed[0] == '>') {
            const quote_text = if (trimmed.len > 1 and trimmed[1] == ' ')
                std.mem.trim(u8, trimmed[2..], " \t")
            else
                std.mem.trim(u8, trimmed[1..], " \t");
            try self.renderBlockquote(quote_text);
            return;
        }

        // Lists
        if (trimmed.len > 0) {
            // Unordered lists
            if ((trimmed[0] == '-' or trimmed[0] == '*' or trimmed[0] == '+') and
                trimmed.len > 1 and trimmed[1] == ' ')
            {
                const list_text = std.mem.trim(u8, trimmed[2..], " \t");
                try self.renderListItem(false, 0, null, list_text);
                return;
            }

            // Ordered lists
            var num_end: usize = 0;
            while (num_end < trimmed.len and trimmed[num_end] >= '0' and trimmed[num_end] <= '9') {
                num_end += 1;
            }
            if (num_end > 0 and num_end < trimmed.len and trimmed[num_end] == '.' and
                num_end + 1 < trimmed.len and trimmed[num_end + 1] == ' ')
            {
                const index = std.fmt.parseInt(usize, trimmed[0..num_end], 10) catch 0;
                const list_text = std.mem.trim(u8, trimmed[num_end + 2 ..], " \t");
                try self.renderListItem(true, 0, index, list_text);
                return;
            }
        }

        // Tables (simple detection - lines with pipes)
        if (std.mem.indexOf(u8, trimmed, "|") != null) {
            // This is a simplified table detection
            // A full implementation would need to collect multiple lines
            try self.renderTableRow(trimmed);
            return;
        }

        // Regular paragraph with inline formatting
        if (trimmed.len > 0) {
            try self.renderParagraph(trimmed);
        } else {
            try self.output.append('\n');
        }
    }

    fn renderHeading(self: *Markdown, level: u8, text: []const u8) !void {
        const color = if (self.options.colorEnabled)
            self.color_scheme.heading_colors[level - 1]
        else
            null;

        // Render heading decoration based on quality tier
        switch (self.options.qualityTier) {
            .rich, .standard => {
                // Add spacing
                try self.output.append('\n');

                // Apply color and style
                if (color) |c| {
                    try self.applyColor(c);
                    try self.applyStyle(.bold, true);
                }

                // Add heading prefix for visual hierarchy
                const prefix = switch (level) {
                    1 => "══════ ",
                    2 => "────── ",
                    3 => "▶▶▶ ",
                    4 => "▶▶ ",
                    5 => "▶ ",
                    6 => "• ",
                    else => "",
                };
                try self.output.appendSlice(prefix);

                // Render formatted text
                try self.renderInlineFormatting(text);

                // Add suffix for H1 and H2
                const suffix = switch (level) {
                    1 => " ══════",
                    2 => " ──────",
                    else => "",
                };
                try self.output.appendSlice(suffix);

                // Reset styles
                if (color != null) {
                    try self.resetStyle();
                }

                try self.output.appendSlice("\n\n");
            },
            .compatible => {
                // Simple underline style for H1 and H2
                try self.output.append('\n');
                try self.renderInlineFormatting(text);
                try self.output.append('\n');

                if (level == 1) {
                    for (0..text.len) |_| {
                        try self.output.append('=');
                    }
                    try self.output.append('\n');
                } else if (level == 2) {
                    for (0..text.len) |_| {
                        try self.output.append('-');
                    }
                    try self.output.append('\n');
                }
                try self.output.append('\n');
            },
            .minimal => {
                // Plain text with level indicator
                try self.output.append('\n');
                for (0..level) |_| {
                    try self.output.append('#');
                }
                try self.output.append(' ');
                try self.output.appendSlice(text);
                try self.output.appendSlice("\n\n");
            },
        }
    }

    fn renderParagraph(self: *Markdown, text: []const u8) !void {
        try self.renderInlineFormatting(text);
        try self.output.append('\n');
    }

    fn renderInlineFormatting(self: *Markdown, text: []const u8) !void {
        var i: usize = 0;
        while (i < text.len) {
            // Check for inline code
            if (i < text.len - 1 and text[i] == '`') {
                const end = std.mem.indexOf(u8, text[i + 1 ..], "`");
                if (end) |e| {
                    const code = text[i + 1 .. i + 1 + e];
                    try self.renderInlineCode(code);
                    i = i + e + 2;
                    continue;
                }
            }

            // Check for links [text](url)
            if (text[i] == '[') {
                const close = std.mem.indexOf(u8, text[i..], "]");
                if (close) |c| {
                    if (i + c + 1 < text.len and text[i + c + 1] == '(') {
                        const paren_close = std.mem.indexOf(u8, text[i + c + 2 ..], ")");
                        if (paren_close) |p| {
                            const link_text = text[i + 1 .. i + c];
                            const url = text[i + c + 2 .. i + c + 2 + p];
                            try self.renderLink(link_text, url);
                            i = i + c + p + 3;
                            continue;
                        }
                    }
                }
            }

            // Check for bold/italic
            if (i < text.len - 1 and (text[i] == '*' or text[i] == '_')) {
                const marker = text[i];

                // Check for bold (** or __)
                if (i < text.len - 3 and text[i + 1] == marker) {
                    const search_str = [_]u8{ marker, marker };
                    const end = std.mem.indexOf(u8, text[i + 2 ..], &search_str);
                    if (end) |e| {
                        const bold_text = text[i + 2 .. i + 2 + e];
                        try self.renderBold(bold_text);
                        i = i + e + 4;
                        continue;
                    }
                } else {
                    // Check for italic (* or _)
                    const search_str = [_]u8{marker};
                    const end = std.mem.indexOf(u8, text[i + 1 ..], &search_str);
                    if (end) |e| {
                        const italic_text = text[i + 1 .. i + 1 + e];
                        try self.renderItalic(italic_text);
                        i = i + e + 2;
                        continue;
                    }
                }
            }

            // Regular character
            try self.output.append(text[i]);
            i += 1;
        }
    }

    fn renderBold(self: *Markdown, text: []const u8) !void {
        if (self.options.colorEnabled and self.color_scheme.bold_color != null) {
            try self.applyStyle(.bold, true);
            if (self.color_scheme.bold_color) |color| {
                try self.applyColor(color);
            }
        }
        try self.output.appendSlice(text);
        if (self.options.colorEnabled and self.color_scheme.bold_color != null) {
            try self.resetStyle();
        }
    }

    fn renderItalic(self: *Markdown, text: []const u8) !void {
        if (self.options.color_enabled and self.color_scheme.italic_color != null) {
            try self.applyStyle(.italic, true);
            if (self.color_scheme.italic_color) |color| {
                try self.applyColor(color);
            }
        }
        try self.output.appendSlice(text);
        if (self.options.color_enabled and self.color_scheme.italic_color != null) {
            try self.resetStyle();
        }
    }

    fn renderInlineCode(self: *Markdown, code: []const u8) !void {
        if (self.options.colorEnabled) {
            if (self.color_scheme.code_bg) |bg| {
                try self.applyBackgroundColor(bg);
            }
            if (self.color_scheme.code_fg) |fg| {
                try self.applyColor(fg);
            }
        }

        try self.output.append(' ');
        try self.output.appendSlice(code);
        try self.output.append(' ');

        if (self.options.color_enabled and
            (self.color_scheme.code_bg != null or self.color_scheme.code_fg != null))
        {
            try self.resetStyle();
        }
    }

    fn renderCodeBlock(self: *Markdown, language: ?[]const u8, content: []const u8) !void {
        const tier_config = switch (self.options.quality_tier) {
            .rich, .standard => struct {
                top: []const u8 = "┌──────────────────────────────────────┐",
                bot: []const u8 = "└──────────────────────────────────────┘",
                side: []const u8 = "│",
            }{},
            .compatible => struct {
                top: []const u8 = "+--------------------------------------+",
                bot: []const u8 = "+--------------------------------------+",
                side: []const u8 = "|",
            }{},
            .minimal => struct {
                top: []const u8 = "",
                bot: []const u8 = "",
                side: []const u8 = "",
            }{},
        };

        // Top border
        if (tier_config.top.len > 0) {
            try self.output.appendSlice(tier_config.top);
            try self.output.append('\n');
        }

        // Language label
        if (language) |lang| {
            if (tier_config.side.len > 0) {
                try self.output.appendSlice(tier_config.side);
                try self.output.append(' ');
            }
            try self.output.appendSlice("Language: ");
            try self.output.appendSlice(lang);
            try self.output.append('\n');
        }

        // Code content
        var code_lines = std.mem.tokenize(u8, content, "\n");
        var line_num: usize = 1;

        while (code_lines.next()) |line| {
            if (tier_config.side.len > 0) {
                try self.output.appendSlice(tier_config.side);
                try self.output.append(' ');
            }

            if (self.options.showLineNumbers) {
                try std.fmt.format(self.output.writer(), "{d:>4} ", .{line_num});
                line_num += 1;
            }

            if (self.options.color_enabled and self.color_scheme.code_fg != null) {
                try self.applyColor(self.color_scheme.code_fg.?);
            }

            try self.output.appendSlice(line);

            if (self.options.color_enabled and self.color_scheme.code_fg != null) {
                try self.resetStyle();
            }

            try self.output.append('\n');
        }

        // Bottom border
        if (tier_config.bot.len > 0) {
            try self.output.appendSlice(tier_config.bot);
            try self.output.append('\n');
        }

        try self.output.append('\n');
    }

    fn renderLink(self: *Markdown, text: []const u8, url: []const u8) !void {
        if (self.options.enableHyperlinks and self.capabilities != null and
            self.capabilities.?.supportsHyperlinkOsc8)
        {
            const writer = self.output.writer();
            try hyperlink.startHyperlink(writer, self.capabilities.?, url, "");

            if (self.color_scheme.link_color) |color| {
                try self.applyColor(color);
            }
            try self.output.appendSlice(text);
            if (self.color_scheme.link_color != null) {
                try self.resetStyle();
            }

            try hyperlink.endHyperlink(writer, self.capabilities.?);
        } else {
            // Fallback format
            if (self.color_scheme.link_color) |color| {
                try self.applyColor(color);
            }
            try self.output.appendSlice(text);
            if (self.color_scheme.link_color != null) {
                try self.resetStyle();
            }
            try self.output.appendSlice(" (");
            try self.output.appendSlice(url);
            try self.output.append(')');
        }
    }

    fn renderListItem(self: *Markdown, ordered: bool, level: usize, index: ?usize, text: []const u8) !void {
        // Indentation
        for (0..level * self.options.indentSize) |_| {
            try self.output.append(' ');
        }

        // List marker
        if (ordered) {
            if (index) |idx| {
                try std.fmt.format(self.output.writer(), "{d}. ", .{idx});
            } else {
                try self.output.appendSlice("1. ");
            }
        } else {
            const bullet = switch (self.options.quality_tier) {
                .rich, .standard => "• ",
                .compatible => "* ",
                .minimal => "- ",
            };
            try self.output.appendSlice(bullet);
        }

        // List item text
        try self.renderInlineFormatting(text);
        try self.output.append('\n');
    }

    fn renderBlockquote(self: *Markdown, text: []const u8) !void {
        const prefix = switch (self.options.quality_tier) {
            .rich, .standard => "│ ",
            .compatible => "| ",
            .minimal => "> ",
        };

        if (self.color_scheme.blockquote_color) |color| {
            try self.applyColor(color);
        }

        try self.output.appendSlice(prefix);
        try self.renderInlineFormatting(text);

        if (self.color_scheme.blockquote_color != null) {
            try self.resetStyle();
        }

        try self.output.append('\n');
    }

    fn renderHorizontalRule(self: *Markdown) !void {
        try self.output.append('\n');

        const rule = switch (self.options.quality_tier) {
            .rich => "═══════════════════════════════════════════════════════════════════════",
            .standard => "───────────────────────────────────────────────────────────────────────",
            .compatible => "-----------------------------------------------------------------------",
            .minimal => "---",
        };

        const width = @min(rule.len, self.options.maxWidth);
        try self.output.appendSlice(rule[0..width]);
        try self.output.appendSlice("\n\n");
    }

    fn renderTableRow(self: *Markdown, row: []const u8) !void {
        // Simple pipe-separated table rendering
        var cells = std.mem.tokenize(u8, row, "|");

        if (self.color_scheme.table_border_color) |color| {
            try self.applyColor(color);
        }

        while (cells.next()) |cell| {
            const trimmed = std.mem.trim(u8, cell, " \t");
            try self.output.append('|');

            // Add padding
            for (0..self.options.tablePadding) |_| {
                try self.output.append(' ');
            }

            // Cell content
            if (self.color_scheme.table_border_color != null) {
                try self.resetStyle();
            }
            try self.renderInlineFormatting(trimmed);
            if (self.color_scheme.table_border_color) |color| {
                try self.applyColor(color);
            }

            // Add padding
            for (0..self.options.tablePadding) |_| {
                try self.output.append(' ');
            }
        }

        try self.output.append('|');

        if (self.color_scheme.table_border_color != null) {
            try self.resetStyle();
        }

        try self.output.append('\n');
    }

    // ANSI escape sequence helpers
    fn applyColor(self: *Markdown, color: ColorUnion) !void {
        const ansi_code = switch (color) {
            .basic => |c| switch (c) {
                .black => "30",
                .red => "31",
                .green => "32",
                .yellow => "33",
                .blue => "34",
                .magenta => "35",
                .cyan => "36",
                .white => "37",
                .bright_black => "90",
                .bright_red => "91",
                .bright_green => "92",
                .bright_yellow => "93",
                .bright_blue => "94",
                .bright_magenta => "95",
                .bright_cyan => "96",
                .bright_white => "97",
            },
            .indexed => |idx| blk: {
                var buf: [16]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "38;5;{d}", .{@intFromEnum(idx)});
                break :blk str;
            },
            .rgb => |rgb| blk: {
                var buf: [32]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "38;2;{d};{d};{d}", .{ rgb.r, rgb.g, rgb.b });
                break :blk str;
            },
        };

        try self.output.appendSlice("\x1b[");
        try self.output.appendSlice(ansi_code);
        try self.output.append('m');
    }

    fn applyBackgroundColor(self: *Markdown, color: ColorUnion) !void {
        const ansi_code = switch (color) {
            .basic => |c| switch (c) {
                .black => "40",
                .red => "41",
                .green => "42",
                .yellow => "43",
                .blue => "44",
                .magenta => "45",
                .cyan => "46",
                .white => "47",
                .bright_black => "100",
                .bright_red => "101",
                .bright_green => "102",
                .bright_yellow => "103",
                .bright_blue => "104",
                .bright_magenta => "105",
                .bright_cyan => "106",
                .bright_white => "107",
            },
            .indexed => |idx| blk: {
                var buf: [16]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "48;5;{d}", .{@intFromEnum(idx)});
                break :blk str;
            },
            .rgb => |rgb| blk: {
                var buf: [32]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "48;2;{d};{d};{d}", .{ rgb.r, rgb.g, rgb.b });
                break :blk str;
            },
        };

        try self.output.appendSlice("\x1b[");
        try self.output.appendSlice(ansi_code);
        try self.output.append('m');
    }

    fn applyStyle(self: *Markdown, style: enum { bold, italic, underline }, enable: bool) !void {
        const code = switch (style) {
            .bold => if (enable) "1" else "22",
            .italic => if (enable) "3" else "23",
            .underline => if (enable) "4" else "24",
        };
        try self.output.appendSlice("\x1b[");
        try self.output.appendSlice(code);
        try self.output.append('m');
    }

    fn resetStyle(self: *Markdown) !void {
        try self.output.appendSlice("\x1b[0m");
    }
};

/// Convenience function to render markdown with default options
pub fn renderMarkdown(
    allocator: std.mem.Allocator,
    markdown_text: []const u8,
    options: MarkdownOptions,
) ![]u8 {
    var renderer = Markdown.init(allocator, options);
    defer renderer.deinit();
    return try renderer.renderMarkdown(markdown_text);
}

// Tests
test "markdown heading rendering" {
    const allocator = std.testing.allocator;

    const markdown = "# Heading 1\n## Heading 2\n### Heading 3";
    const options = MarkdownOptions{ .color_enabled = false, .quality_tier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "# Heading 1") != null) catch unreachable;
}

test "markdown inline formatting" {
    const allocator = std.testing.allocator;

    const markdown = "This is **bold** and *italic* text with `code`";
    const options = MarkdownOptions{ .color_enabled = false, .quality_tier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "bold") != null) catch unreachable;
    std.testing.expect(std.mem.indexOf(u8, result, "italic") != null) catch unreachable;
    std.testing.expect(std.mem.indexOf(u8, result, "code") != null) catch unreachable;
}

test "markdown code block rendering" {
    const allocator = std.testing.allocator;

    const markdown = "```zig\nconst x = 10;\n```";
    const options = MarkdownOptions{ .color_enabled = false, .quality_tier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "const x = 10;") != null) catch unreachable;
}

test "markdown list rendering" {
    const allocator = std.testing.allocator;

    const markdown = "- Item 1\n- Item 2\n1. First\n2. Second";
    const options = MarkdownOptions{ .color_enabled = false, .quality_tier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "- Item 1") != null) catch unreachable;
    std.testing.expect(std.mem.indexOf(u8, result, "1. First") != null) catch unreachable;
}

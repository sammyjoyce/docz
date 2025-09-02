const std = @import("std");
const term = @import("../term.zig");
const caps_mod = term;
const QualityTiers = @import("quality_tiers.zig").QualityTiers;
const render_mod = @import("../render.zig");
const Renderer = render_mod.Renderer;
const RenderMode = render_mod.RenderTier;
const ColorUnion = term.color.Color;
const Color = term.ansi.AnsiColor;
const hyperlink = term.ansi;

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
            .ultra => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .rgb = .{ .r = 255, .g = 107, .b = 107 } },
                    ColorUnion{ .rgb = .{ .r = 255, .g = 193, .b = 107 } },
                    ColorUnion{ .rgb = .{ .r = 255, .g = 255, .b = 107 } },
                    ColorUnion{ .rgb = .{ .r = 107, .g = 255, .b = 107 } },
                    ColorUnion{ .rgb = .{ .r = 107, .g = 193, .b = 255 } },
                    ColorUnion{ .rgb = .{ .r = 193, .g = 107, .b = 255 } },
                },
                .boldColor = ColorUnion{ .ansi = 15 },
                .italicColor = ColorUnion{ .ansi = 14 },
                .codeBg = ColorUnion{ .rgb = .{ .r = 40, .g = 40, .b = 40 } },
                .codeFg = ColorUnion{ .rgb = .{ .r = 107, .g = 255, .b = 107 } },
                .linkColor = ColorUnion{ .rgb = .{ .r = 107, .g = 193, .b = 255 } },
                .blockquoteColor = ColorUnion{ .ansi = 8 },
                .tableBorderColor = ColorUnion{ .ansi = 12 },
            },
            .rich => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .rgb = .{ .r = 255, .g = 107, .b = 107 } }, // H1 - bright red
                    ColorUnion{ .rgb = .{ .r = 255, .g = 193, .b = 107 } }, // H2 - bright orange
                    ColorUnion{ .rgb = .{ .r = 255, .g = 255, .b = 107 } }, // H3 - bright yellow
                    ColorUnion{ .rgb = .{ .r = 107, .g = 255, .b = 107 } }, // H4 - bright green
                    ColorUnion{ .rgb = .{ .r = 107, .g = 193, .b = 255 } }, // H5 - bright cyan
                    ColorUnion{ .rgb = .{ .r = 193, .g = 107, .b = 255 } }, // H6 - bright purple
                },
                .boldColor = ColorUnion{ .ansi = 15 }, // bright_white
                .italicColor = ColorUnion{ .ansi = 14 }, // bright_cyan
                .codeBg = ColorUnion{ .rgb = .{ .r = 40, .g = 40, .b = 40 } },
                .codeFg = ColorUnion{ .rgb = .{ .r = 107, .g = 255, .b = 107 } },
                .linkColor = ColorUnion{ .rgb = .{ .r = 107, .g = 193, .b = 255 } },
                .blockquoteColor = ColorUnion{ .ansi = 8 }, // bright_black
                .tableBorderColor = ColorUnion{ .ansi = 12 }, // bright_blue
            },
            .standard => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .ansi = 9 }, // bright_red
                    ColorUnion{ .ansi = 11 }, // bright_yellow
                    ColorUnion{ .ansi = 10 }, // bright_green
                    ColorUnion{ .ansi = 14 }, // bright_cyan
                    ColorUnion{ .ansi = 12 }, // bright_blue
                    ColorUnion{ .ansi = 13 }, // bright_magenta
                },
                .boldColor = ColorUnion{ .ansi = 15 }, // bright_white
                .italicColor = ColorUnion{ .ansi = 6 }, // cyan
                .codeBg = null,
                .codeFg = ColorUnion{ .ansi = 2 }, // green
                .linkColor = ColorUnion{ .ansi = 4 }, // blue
                .blockquoteColor = ColorUnion{ .ansi = 8 }, // bright_black
                .tableBorderColor = ColorUnion{ .ansi = 4 }, // blue
            },
            .minimal => ColorScheme{
                .headingColors = [_]ColorUnion{
                    ColorUnion{ .ansi = 7 }, // white
                    ColorUnion{ .ansi = 7 }, // white
                    ColorUnion{ .ansi = 7 }, // white
                    ColorUnion{ .ansi = 7 }, // white
                    ColorUnion{ .ansi = 7 }, // white
                    ColorUnion{ .ansi = 7 }, // white
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
    capabilities: ?term.capabilities.TermCaps,

    pub fn init(allocator: std.mem.Allocator, options: MarkdownOptions) Markdown {
        return Markdown{
            .allocator = allocator,
            .options = options,
            .colorScheme = ColorScheme.getForTier(options.qualityTier),
            .output = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
            .capabilities = null, // Can be set if terminal capabilities are known
        };
    }

    pub fn deinit(self: *Markdown) void {
        self.output.deinit(self.allocator);
    }

    /// Set terminal capabilities for advanced features
    pub fn setCapabilities(self: *Markdown, caps: caps_mod.capabilities.TermCaps) void {
        self.capabilities = caps;
    }

    /// Main entry point - render markdown to formatted terminal output
    pub fn renderMarkdown(self: *Markdown, markdown: []const u8) ![]u8 {
        self.output.clearRetainingCapacity();

        var lines = std.mem.splitScalar(u8, markdown, '\n');
        var in_code_block = false;
        var code_block_content = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer code_block_content.deinit(self.allocator);
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
                    try code_block_content.append(self.allocator, '\n');
                }
                try code_block_content.appendSlice(self.allocator, line);
                continue;
            }

            // Parse and render line
            try self.renderLine(line);
        }

        // Handle unclosed code block
        if (in_code_block) {
            try self.renderCodeBlock(code_block_lang, code_block_content.items);
        }

        return try self.output.toOwnedSlice(self.allocator);
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
            try self.output.append(self.allocator, '\n');
        }
    }

    fn renderHeading(self: *Markdown, level: u8, text: []const u8) !void {
        const color = if (self.options.colorEnabled)
            self.colorScheme.headingColors[level - 1]
        else
            null;

        // Render heading decoration based on quality tier
        switch (self.options.qualityTier) {
            .ultra, .rich => {
                // Add spacing
                try self.output.append(self.allocator, '\n');

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
                try self.output.appendSlice(self.allocator, prefix);

                // Render formatted text
                try self.renderInlineFormatting(text);

                // Add suffix for H1 and H2
                const suffix = switch (level) {
                    1 => " ══════",
                    2 => " ──────",
                    else => "",
                };
                try self.output.appendSlice(self.allocator, suffix);

                // Reset styles
                if (color != null) {
                    try self.resetStyle();
                }

                try self.output.appendSlice(self.allocator, "\n\n");
            },
            .standard => {
                // Simple underline style for H1 and H2
                try self.output.append(self.allocator, '\n');
                try self.renderInlineFormatting(text);
                try self.output.append(self.allocator, '\n');

                if (level == 1) {
                    for (0..text.len) |_| {
                        try self.output.append(self.allocator, '=');
                    }
                    try self.output.append(self.allocator, '\n');
                } else if (level == 2) {
                    for (0..text.len) |_| {
                        try self.output.append(self.allocator, '-');
                    }
                    try self.output.append(self.allocator, '\n');
                }
                try self.output.append(self.allocator, '\n');
            },
            .minimal => {
                // Plain text with level indicator
                try self.output.append(self.allocator, '\n');
                for (0..level) |_| {
                    try self.output.append(self.allocator, '#');
                }
                try self.output.append(self.allocator, ' ');
                try self.output.appendSlice(self.allocator, text);
                try self.output.appendSlice(self.allocator, "\n\n");
            },
        }
    }

    fn renderParagraph(self: *Markdown, text: []const u8) !void {
        try self.renderInlineFormatting(text);
        try self.output.append(self.allocator, '\n');
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
            try self.output.append(self.allocator, text[i]);
            i += 1;
        }
    }

    fn renderBold(self: *Markdown, text: []const u8) !void {
        if (self.options.colorEnabled and self.colorScheme.boldColor != null) {
            try self.applyStyle(.bold, true);
            if (self.colorScheme.boldColor) |color| {
                try self.applyColor(color);
            }
        }
        try self.output.appendSlice(self.allocator, text);
        if (self.options.colorEnabled and self.colorScheme.boldColor != null) {
            try self.resetStyle();
        }
    }

    fn renderItalic(self: *Markdown, text: []const u8) !void {
        if (self.options.colorEnabled and self.colorScheme.italicColor != null) {
            try self.applyStyle(.italic, true);
            if (self.colorScheme.italicColor) |color| {
                try self.applyColor(color);
            }
        }
        try self.output.appendSlice(self.allocator, text);
        if (self.options.colorEnabled and self.colorScheme.italicColor != null) {
            try self.resetStyle();
        }
    }

    fn renderInlineCode(self: *Markdown, code: []const u8) !void {
        if (self.options.colorEnabled) {
            if (self.colorScheme.codeBg) |bg| {
                try self.applyBackgroundColor(bg);
            }
            if (self.colorScheme.codeFg) |fg| {
                try self.applyColor(fg);
            }
        }

        try self.output.append(self.allocator, ' ');
        try self.output.appendSlice(self.allocator, code);
        try self.output.append(self.allocator, ' ');

        if (self.options.colorEnabled and
            (self.colorScheme.codeBg != null or self.colorScheme.codeFg != null))
        {
            try self.resetStyle();
        }
    }

    fn renderCodeBlock(self: *Markdown, language: ?[]const u8, content: []const u8) !void {
        const Border = struct { top: []const u8, bot: []const u8, side: []const u8 };
        const tier_config: Border = switch (self.options.qualityTier) {
            .ultra, .rich => .{
                .top = "┌──────────────────────────────────────┐",
                .bot = "└──────────────────────────────────────┘",
                .side = "│",
            },
            .standard => .{
                .top = "+--------------------------------------+",
                .bot = "+--------------------------------------+",
                .side = "|",
            },
            .minimal => .{ .top = "", .bot = "", .side = "" },
        };

        // Top border
        if (tier_config.top.len > 0) {
            try self.output.appendSlice(self.allocator, tier_config.top);
            try self.output.append(self.allocator, '\n');
        }

        // Language label
        if (language) |lang| {
            if (tier_config.side.len > 0) {
                try self.output.appendSlice(self.allocator, tier_config.side);
                try self.output.append(self.allocator, ' ');
            }
            try self.output.appendSlice(self.allocator, "Language: ");
            try self.output.appendSlice(self.allocator, lang);
            try self.output.append(self.allocator, '\n');
        }

        // Code content
        var code_lines = std.mem.splitScalar(u8, content, '\n');
        var line_num: usize = 1;

        while (code_lines.next()) |line| {
            if (tier_config.side.len > 0) {
                try self.output.appendSlice(self.allocator, tier_config.side);
                try self.output.append(self.allocator, ' ');
            }

            if (self.options.showLineNumbers) {
                try std.fmt.format(self.output.writer(self.allocator), "{d:>4} ", .{line_num});
                line_num += 1;
            }

            if (self.options.colorEnabled and self.colorScheme.codeFg != null) {
                try self.applyColor(self.colorScheme.codeFg.?);
            }

            try self.output.appendSlice(self.allocator, line);

            if (self.options.colorEnabled and self.colorScheme.codeFg != null) {
                try self.resetStyle();
            }

            try self.output.append(self.allocator, '\n');
        }

        // Bottom border
        if (tier_config.bot.len > 0) {
            try self.output.appendSlice(self.allocator, tier_config.bot);
            try self.output.append(self.allocator, '\n');
        }

        try self.output.append(self.allocator, '\n');
    }

    fn renderLink(self: *Markdown, text: []const u8, url: []const u8) !void {
        // Simple fallback: text (url)
        try self.output.appendSlice(self.allocator, text);
        try self.output.appendSlice(self.allocator, " (");
        try self.output.appendSlice(self.allocator, url);
        try self.output.append(self.allocator, ')');
    }

    fn renderListItem(self: *Markdown, ordered: bool, level: usize, index: ?usize, text: []const u8) !void {
        // Indentation
        for (0..level * self.options.indentSize) |_| {
            try self.output.append(self.allocator, ' ');
        }

        // List marker
        if (ordered) {
            if (index) |idx| {
                try std.fmt.format(self.output.writer(self.allocator), "{d}. ", .{idx});
            } else {
                try self.output.appendSlice(self.allocator, "1. ");
            }
        } else {
            const bullet = if (self.options.qualityTier == .minimal) "- " else "• ";
            try self.output.appendSlice(self.allocator, bullet);
        }

        // List item text
        try self.renderInlineFormatting(text);
        try self.output.append(self.allocator, '\n');
    }

    fn renderBlockquote(self: *Markdown, text: []const u8) !void {
        const prefix = switch (self.options.qualityTier) {
            .ultra, .rich, .standard => "│ ",
            .minimal => "> ",
        };

        if (self.colorScheme.blockquoteColor) |color| {
            try self.applyColor(color);
        }

        try self.output.appendSlice(self.allocator, prefix);
        try self.renderInlineFormatting(text);

        if (self.colorScheme.blockquoteColor != null) {
            try self.resetStyle();
        }

        try self.output.append(self.allocator, '\n');
    }

    fn renderHorizontalRule(self: *Markdown) !void {
        try self.output.append(self.allocator, '\n');

        const rule = switch (self.options.qualityTier) {
            .ultra, .rich => "═══════════════════════════════════════════════════════════════════════",
            .standard => "-----------------------------------------------------------------------",
            .minimal => "---",
        };

        const width = @min(rule.len, self.options.maxWidth);
        try self.output.appendSlice(self.allocator, rule[0..width]);
        try self.output.appendSlice(self.allocator, "\n\n");
    }

    fn renderTableRow(self: *Markdown, row: []const u8) !void {
        // Simple pipe-separated table rendering
        var cells = std.mem.splitScalar(u8, row, '|');

        if (self.colorScheme.tableBorderColor) |color| {
            try self.applyColor(color);
        }

        while (cells.next()) |cell| {
            const trimmed = std.mem.trim(u8, cell, " \t");
            try self.output.append(self.allocator, '|');

            // Add padding
            for (0..self.options.tablePadding) |_| {
                try self.output.append(self.allocator, ' ');
            }

            // Cell content
            if (self.colorScheme.tableBorderColor != null) {
                try self.resetStyle();
            }
            try self.renderInlineFormatting(trimmed);
            if (self.colorScheme.tableBorderColor) |color| {
                try self.applyColor(color);
            }

            // Add padding
            for (0..self.options.tablePadding) |_| {
                try self.output.append(self.allocator, ' ');
            }
        }

        try self.output.append(self.allocator, '|');

        if (self.colorScheme.tableBorderColor != null) {
            try self.resetStyle();
        }

        try self.output.append(self.allocator, '\n');
    }

    // ANSI escape sequence helpers
    fn applyColor(self: *Markdown, color: ColorUnion) !void {
        const writer = self.output.writer(self.allocator);
        try color.toAnsiFg(writer);
    }

    fn applyBackgroundColor(self: *Markdown, color: ColorUnion) !void {
        const writer = self.output.writer(self.allocator);
        try color.toAnsiBg(writer);
    }

    fn applyStyle(self: *Markdown, style: enum { bold, italic, underline }, enable: bool) !void {
        const code = switch (style) {
            .bold => if (enable) "1" else "22",
            .italic => if (enable) "3" else "23",
            .underline => if (enable) "4" else "24",
        };
        try self.output.appendSlice(self.allocator, "\x1b[");
        try self.output.appendSlice(self.allocator, code);
        try self.output.append(self.allocator, 'm');
    }

    fn resetStyle(self: *Markdown) !void {
        try self.output.appendSlice(self.allocator, "\x1b[0m");
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
    const options = MarkdownOptions{ .colorEnabled = false, .qualityTier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "# Heading 1") != null) catch unreachable;
}

test "markdown inline formatting" {
    const allocator = std.testing.allocator;

    const markdown = "This is **bold** and *italic* text with `code`";
    const options = MarkdownOptions{ .colorEnabled = false, .qualityTier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "bold") != null) catch unreachable;
    std.testing.expect(std.mem.indexOf(u8, result, "italic") != null) catch unreachable;
    std.testing.expect(std.mem.indexOf(u8, result, "code") != null) catch unreachable;
}

test "markdown code block rendering" {
    const allocator = std.testing.allocator;

    const markdown = "```zig\nconst x = 10;\n```";
    const options = MarkdownOptions{ .colorEnabled = false, .qualityTier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "const x = 10;") != null) catch unreachable;
}

test "markdown list rendering" {
    const allocator = std.testing.allocator;

    const markdown = "- Item 1\n- Item 2\n1. First\n2. Second";
    const options = MarkdownOptions{ .colorEnabled = false, .qualityTier = .minimal };

    const result = try renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);

    std.testing.expect(std.mem.indexOf(u8, result, "- Item 1") != null) catch unreachable;
    std.testing.expect(std.mem.indexOf(u8, result, "1. First") != null) catch unreachable;
}

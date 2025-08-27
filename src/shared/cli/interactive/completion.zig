//! Autocomplete with fuzzy search using terminal capabilities
//! Leverages @src/term for rich terminal interactions

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_cursor = term_shared.ansi.cursor;
const term_screen = term_shared.ansi.screen;
const term_hyperlink = term_shared.ansi.hyperlink;
const term_caps = term_shared.caps;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const CompletionItem = struct {
    text: []const u8,
    description: ?[]const u8 = null,
    category: ?[]const u8 = null,
    score: f32 = 0.0,
    help_url: ?[]const u8 = null,
    icon: ?[]const u8 = null, // Unicode icon or emoji
    preview_text: ?[]const u8 = null, // Preview content for graphics/code
    thumbnail_path: ?[]const u8 = null, // Path to thumbnail image
    has_preview: bool = false, // Whether this item supports preview

    pub fn init(text: []const u8) CompletionItem {
        return .{ .text = text };
    }

    pub fn withDescription(self: CompletionItem, desc: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = desc,
            .category = self.category,
            .score = self.score,
            .help_url = self.help_url,
            .icon = self.icon,
            .preview_text = self.preview_text,
            .thumbnail_path = self.thumbnail_path,
            .has_preview = self.has_preview,
        };
    }

    pub fn withCategory(self: CompletionItem, cat: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = cat,
            .score = self.score,
            .help_url = self.help_url,
            .icon = self.icon,
            .preview_text = self.preview_text,
            .thumbnail_path = self.thumbnail_path,
            .has_preview = self.has_preview,
        };
    }

    pub fn withHelpURL(self: CompletionItem, url: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = self.category,
            .score = self.score,
            .help_url = url,
            .icon = self.icon,
            .preview_text = self.preview_text,
            .thumbnail_path = self.thumbnail_path,
            .has_preview = self.has_preview,
        };
    }

    pub fn withIcon(self: CompletionItem, icon_char: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = self.category,
            .score = self.score,
            .help_url = self.help_url,
            .icon = icon_char,
            .preview_text = self.preview_text,
            .thumbnail_path = self.thumbnail_path,
            .has_preview = self.has_preview,
        };
    }

    pub fn withPreview(self: CompletionItem, preview: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = self.category,
            .score = self.score,
            .help_url = self.help_url,
            .icon = self.icon,
            .preview_text = preview,
            .thumbnail_path = self.thumbnail_path,
            .has_preview = true,
        };
    }

    pub fn withThumbnail(self: CompletionItem, thumbnail_path: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = self.category,
            .score = self.score,
            .help_url = self.help_url,
            .icon = self.icon,
            .preview_text = self.preview_text,
            .thumbnail_path = thumbnail_path,
            .has_preview = true,
        };
    }
};

/// Fuzzy matcher for intelligent completion scoring
pub const FuzzyMatcher = struct {
    const MATCH_BONUS = 16;
    const CAMEL_BONUS = 30;
    const CONSECUTIVE_BONUS = 15;
    const SEPARATOR_BONUS = 30;
    const FIRST_LETTER_BONUS = 15;

    /// Calculate fuzzy match score between query and candidate
    pub fn score(query: []const u8, candidate: []const u8) f32 {
        if (query.len == 0) return 1.0;
        if (candidate.len == 0) return 0.0;

        const query_lower = std.ascii.allocLowerString(std.heap.page_allocator, query) catch return 0.0;
        defer std.heap.page_allocator.free(query_lower);

        const candidate_lower = std.ascii.allocLowerString(std.heap.page_allocator, candidate) catch return 0.0;
        defer std.heap.page_allocator.free(candidate_lower);

        var score_value: f32 = 0;
        var query_idx: usize = 0;
        var consecutive: u32 = 0;

        for (candidate_lower, 0..) |ch, i| {
            if (query_idx >= query_lower.len) break;

            if (ch == query_lower[query_idx]) {
                score_value += MATCH_BONUS;

                // Bonus for consecutive matches
                if (consecutive > 0) {
                    score_value += consecutive * CONSECUTIVE_BONUS;
                }
                consecutive += 1;

                // Bonus for first letter
                if (i == 0) {
                    score_value += FIRST_LETTER_BONUS;
                }

                // Bonus for camelCase/word boundaries
                if (i > 0) {
                    const prev_ch = candidate[i - 1];
                    if ((prev_ch == '_' or prev_ch == '-' or prev_ch == ' ') or
                        (std.ascii.isLower(prev_ch) and std.ascii.isUpper(candidate[i])))
                    {
                        score_value += CAMEL_BONUS;
                    }

                    if (prev_ch == '_' or prev_ch == '-' or prev_ch == ' ') {
                        score_value += SEPARATOR_BONUS;
                    }
                }

                query_idx += 1;
            } else {
                consecutive = 0;
            }
        }

        // Penalty for unmatched characters
        if (query_idx < query_lower.len) {
            return 0.0;
        }

        // Normalize by candidate length to prefer shorter matches
        return score_value / @as(f32, @floatFromInt(candidate.len));
    }
};

/// Enhanced completion engine with terminal capabilities
pub const CompletionEngine = struct {
    items: std.ArrayList(CompletionItem),
    filtered_items: std.ArrayList(CompletionItem),
    selected_index: usize,
    matcher: FuzzyMatcher,
    caps: term_caps.TermCaps,
    allocator: Allocator,
    show_previews: bool,
    show_icons: bool,
    show_thumbnails: bool,

    pub fn init(allocator: Allocator) !CompletionEngine {
        return CompletionEngine{
            .items = std.ArrayList(CompletionItem).init(allocator),
            .filtered_items = std.ArrayList(CompletionItem).init(allocator),
            .selected_index = 0,
            .matcher = FuzzyMatcher{},
            .caps = term_caps.getTermCaps(),
            .allocator = allocator,
            .show_previews = true,
            .show_icons = true,
            .show_thumbnails = true,
        };
    }

    pub fn deinit(self: *CompletionEngine) void {
        self.items.deinit();
        self.filtered_items.deinit();
    }

    pub fn addItem(self: *CompletionEngine, item: CompletionItem) !void {
        try self.items.append(item);
    }

    pub fn addItems(self: *CompletionEngine, items: []const CompletionItem) !void {
        for (items) |item| {
            try self.addItem(item);
        }
    }

    /// Filter items based on query with fuzzy matching
    pub fn filter(self: *CompletionEngine, query: []const u8) !void {
        self.filtered_items.clearRetainingCapacity();

        for (self.items.items) |item| {
            var scored_item = item;
            scored_item.score = self.matcher.score(query, item.text);
            if (scored_item.score > 0.0) {
                try self.filtered_items.append(scored_item);
            }
        }

        // Sort by score descending
        std.mem.sort(CompletionItem, self.filtered_items.items, {}, struct {
            pub fn lessThan(_: void, a: CompletionItem, b: CompletionItem) bool {
                return a.score > b.score;
            }
        }.lessThan);

        // Reset selection
        self.selected_index = 0;
    }

    pub fn selectNext(self: *CompletionEngine) void {
        if (self.filtered_items.items.len > 0) {
            self.selected_index = (self.selected_index + 1) % self.filtered_items.items.len;
        }
    }

    pub fn selectPrev(self: *CompletionEngine) void {
        if (self.filtered_items.items.len > 0) {
            self.selected_index = if (self.selected_index == 0)
                self.filtered_items.items.len - 1
            else
                self.selected_index - 1;
        }
    }

    pub fn getSelected(self: CompletionEngine) ?CompletionItem {
        if (self.selected_index < self.filtered_items.items.len) {
            return self.filtered_items.items[self.selected_index];
        }
        return null;
    }

    pub fn configureDisplay(self: *CompletionEngine, previews: bool, icons: bool, thumbnails: bool) void {
        self.show_previews = previews;
        self.show_icons = icons;
        self.show_thumbnails = thumbnails;
    }

    /// Render completion popup with advanced terminal features including previews
    pub fn render(self: CompletionEngine, writer: anytype) !void {
        if (self.filtered_items.items.len == 0) return;

        const max_items = @min(self.filtered_items.items.len, 10);
        const selected_item = self.getSelected();
        const show_preview_panel = self.show_previews and selected_item != null and selected_item.?.has_preview;

        // Calculate layout dimensions
        const main_width: u32 = if (show_preview_panel) 50 else 70;
        const preview_width: u32 = if (show_preview_panel) 40 else 0;
        const total_height = max_items + 2;

        // Save cursor position
        try term_cursor.saveCursor(writer, self.caps);

        // Clear screen area for popup
        try self.clearRenderArea(writer, total_height);

        // Move to start position
        try term_cursor.cursorUp(writer, self.caps, @intCast(total_height));

        // Render main completion panel
        try self.renderMainPanel(writer, max_items, main_width);

        // Render preview panel if enabled and available
        if (show_preview_panel) {
            try self.renderPreviewPanel(writer, selected_item.?, preview_width, total_height);
        }

        // Restore cursor position
        try term_cursor.restoreCursor(writer, self.caps);
    }

    /// Clear the rendering area
    fn clearRenderArea(self: CompletionEngine, writer: anytype, height: u32) !void {
        for (0..height) |_| {
            try term_screen.clearLineAll(writer, self.caps);
            try term_cursor.cursorDown(writer, self.caps, 1);
        }
    }

    /// Render the main completion panel
    fn renderMainPanel(self: CompletionEngine, writer: anytype, max_items: usize, panel_width: u32) !void {
        // Draw header
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("┌─ Enhanced Completions ");

        // Add capability indicators
        const indicators = [_]struct { bool, []const u8 }{
            .{ self.caps.supportsKittyGraphics(), "🖼" },
            .{ self.caps.supportsHyperlinks(), "🔗" },
            .{ self.caps.supportsClipboard(), "📋" },
        };

        for (indicators) |indicator| {
            if (indicator[0]) {
                try writer.writeAll(indicator[1]);
            }
        }

        // Fill rest of header
        const header_content_len = 24 + 3; // Base text + max 3 indicators
        const padding_needed = if (panel_width > header_content_len) panel_width - header_content_len else 0;
        for (0..padding_needed) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n");

        // Render completion items
        for (self.filtered_items.items[0..max_items], 0..) |item, i| {
            try self.renderCompletionItem(writer, item, i == self.selected_index, panel_width);
        }

        // Close main panel
        try writer.writeAll("└");
        for (0..panel_width) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘\n");
        try term_ansi.resetStyle(writer, self.caps);
    }

    /// Render a single completion item with enhanced features
    fn renderCompletionItem(self: CompletionEngine, writer: anytype, item: CompletionItem, is_selected: bool, panel_width: u32) !void {
        try writer.writeAll("│");

        // Selection indicator
        if (is_selected) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 80);
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            } else {
                try term_ansi.setBackground256(writer, self.caps, 18);
                try term_ansi.setForeground256(writer, self.caps, 15);
            }
            try writer.writeAll("►");
        } else {
            try writer.writeAll(" ");
        }

        // Icon if available and enabled
        if (self.show_icons and item.icon != null) {
            try writer.print(" {s}", .{item.icon.?});
        } else {
            try writer.writeAll("  ");
        }

        // Category tag
        var content_length: usize = 3; // Selection + icon + space
        if (item.category) |cat| {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 147, 112, 219);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 5);
            }
            try writer.print("[{s}]", .{cat});
            content_length += cat.len + 2;

            // Reset for main text
            if (is_selected) {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 15);
                }
            }
        }

        // Main completion text with hyperlink support
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 152, 251, 152);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 10);
        }

        if (item.help_url) |url| {
            try term_hyperlink.writeHyperlink(writer, self.allocator, self.caps, url, item.text);
        } else {
            try writer.writeAll(item.text);
        }
        content_length += item.text.len;

        // Preview indicator
        if (item.has_preview) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 215, 0);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 11);
            }
            try writer.writeAll(" 🔍");
            content_length += 2;
        }

        // Description (truncated to fit)
        if (item.description) |desc| {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 169, 169, 169);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }

            const available_space = if (panel_width > content_length + 3) panel_width - content_length - 3 else 0;
            const max_desc_len = @min(desc.len, available_space);

            if (max_desc_len > 0) {
                if (max_desc_len < desc.len) {
                    try writer.print(" - {s}...", .{desc[0 .. max_desc_len - 3]});
                } else {
                    try writer.print(" - {s}", .{desc});
                }
                content_length += max_desc_len + 3;
            }
        }

        try term_ansi.resetStyle(writer, self.caps);

        // Pad to panel edge
        const remaining_space = if (panel_width > content_length) panel_width - content_length else 0;
        for (0..remaining_space) |_| {
            try writer.writeAll(" ");
        }

        try writer.writeAll("│\n");
    }

    /// Render preview panel showing details for selected item
    fn renderPreviewPanel(self: CompletionEngine, writer: anytype, item: CompletionItem, panel_width: u32, panel_height: u32) !void {
        // Position cursor for preview panel (to the right of main panel)
        try term_cursor.cursorUp(writer, self.caps, @intCast(panel_height));
        try term_cursor.cursorRight(writer, self.caps, 52); // Main panel width + border

        // Preview panel header
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 215, 0);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 11);
        }

        try writer.writeAll("┌─ Preview ");
        for (0..panel_width - 10) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n");

        // Move to next line and right position for preview content
        try term_cursor.cursorRight(writer, self.caps, 52);

        // Render preview content
        try self.renderPreviewContent(writer, item, panel_width, panel_height - 2);

        // Preview panel footer
        try term_cursor.cursorDown(writer, self.caps, 1);
        try term_cursor.cursorRight(writer, self.caps, 52);
        try writer.writeAll("└");
        for (0..panel_width) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘");

        try term_ansi.resetStyle(writer, self.caps);
    }

    /// Render the actual preview content
    fn renderPreviewContent(self: CompletionEngine, writer: anytype, item: CompletionItem, width: u32, height: u32) !void {
        _ = height; // May use in future for multi-line previews

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 7);
        }

        // Show preview text if available
        if (item.preview_text) |preview| {
            try writer.writeAll("│ ");

            const max_preview_len = if (width > 4) width - 4 else 0;
            const display_len = @min(preview.len, max_preview_len);

            if (display_len < preview.len) {
                try writer.print("{s}... ", .{preview[0 .. display_len - 3]});
            } else {
                try writer.print("{s} ", .{preview[0..display_len]});
            }

            // Pad to width
            const content_len = display_len + 2;
            const padding = if (width > content_len) width - content_len else 0;
            for (0..padding) |_| {
                try writer.writeAll(" ");
            }
            try writer.writeAll("│\n");
        } else {
            // Show enhanced info
            try writer.writeAll("│ ");

            var info_parts = std.ArrayList([]const u8).init(self.allocator);
            defer info_parts.deinit();

            if (item.help_url != null) try info_parts.append("📖 Help");
            if (item.thumbnail_path != null) try info_parts.append("🖼 Thumbnail");
            if (item.category != null) try info_parts.append("🏷 Tagged");

            if (info_parts.items.len > 0) {
                for (info_parts.items, 0..) |part, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(part);
                }
            } else {
                try writer.writeAll("No preview available");
            }

            // Pad to width (simplified)
            const padding = width / 2;
            for (0..padding) |_| {
                try writer.writeAll(" ");
            }
            try writer.writeAll("│\n");
        }

        // Move to next preview line position
        try term_cursor.cursorRight(writer, self.caps, 52);

        try term_ansi.resetStyle(writer, self.caps);
    }

    /// Clear the completion popup from screen
    pub fn clear(self: CompletionEngine, writer: anytype) !void {
        const max_items = @min(self.filtered_items.items.len, 10);
        if (max_items == 0) return;

        // Save current position
        try term_cursor.saveCursor(writer, self.caps);

        // Move up and clear the completion area
        try term_cursor.cursorUp(writer, self.caps, @intCast(max_items + 2));
        for (0..max_items + 2) |_| {
            try term_screen.clearLineAll(writer, self.caps);
            try term_cursor.cursorDown(writer, self.caps, 1);
        }

        // Restore position
        try term_cursor.restoreCursor(writer, self.caps);
    }
};

/// Predefined completion sets for common use cases
pub const CompletionSets = struct {
    /// CLI commands completion with enhanced features
    pub fn getCliCommands(allocator: Allocator) ![]CompletionItem {
        const commands = [_]CompletionItem{
            CompletionItem.init("chat")
                .withDescription("Start interactive chat session")
                .withCategory("cmd")
                .withIcon("💬")
                .withPreview("Launch interactive chat with Claude AI assistant")
                .withHelpUrl("https://docs.anthropic.com/claude/docs"),

            CompletionItem.init("auth")
                .withDescription("Authentication management")
                .withCategory("cmd")
                .withIcon("🔐")
                .withPreview("Manage authentication credentials and tokens")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/authentication"),

            CompletionItem.init("oauth")
                .withDescription("Setup OAuth authentication")
                .withCategory("auth")
                .withIcon("🔑")
                .withPreview("Configure OAuth 2.0 authentication flow")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/oauth"),

            CompletionItem.init("help")
                .withDescription("Show help information")
                .withCategory("cmd")
                .withIcon("❓")
                .withPreview("Display comprehensive help and usage information"),

            CompletionItem.init("version")
                .withDescription("Show version information")
                .withCategory("info")
                .withIcon("ℹ️")
                .withPreview("Display current version and build information"),

            CompletionItem.init("status")
                .withDescription("Check authentication status")
                .withCategory("auth")
                .withIcon("📊")
                .withPreview("Check current authentication state and token validity"),

            CompletionItem.init("refresh")
                .withDescription("Refresh OAuth token")
                .withCategory("auth")
                .withIcon("🔄")
                .withPreview("Refresh expired OAuth authentication tokens"),

            CompletionItem.init("quit")
                .withDescription("Exit the application")
                .withCategory("cmd")
                .withIcon("🚪")
                .withPreview("Gracefully exit the DocZ application"),

            CompletionItem.init("exit")
                .withDescription("Exit the application")
                .withCategory("cmd")
                .withIcon("🚪")
                .withPreview("Gracefully exit the DocZ application"),

            // Enhanced demo commands
            CompletionItem.init("demo:graphics")
                .withDescription("Graphics capabilities demonstration")
                .withCategory("demo")
                .withIcon("🎨")
                .withPreview("Test terminal graphics support (Kitty/Sixel protocols)")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/terminal-graphics"),

            CompletionItem.init("demo:completion")
                .withDescription("Enhanced completion features demo")
                .withCategory("demo")
                .withIcon("✨")
                .withPreview("Showcase advanced completion with previews and hyperlinks"),
        };

        const result = try allocator.alloc(CompletionItem, commands.len);
        @memcpy(result, &commands);
        return result;
    }

    /// Model names completion with enhanced metadata
    pub fn getModelNames(allocator: Allocator) ![]CompletionItem {
        const models = [_]CompletionItem{
            CompletionItem.init("claude-3-5-sonnet-20241022")
                .withDescription("Latest Claude 3.5 Sonnet model")
                .withCategory("model")
                .withIcon("🧠")
                .withPreview("Advanced reasoning, coding, math. 200K context window. Balanced speed/capability.")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/models-overview#claude-3-5-sonnet"),

            CompletionItem.init("claude-3-haiku-20240307")
                .withDescription("Fast, efficient Claude 3 Haiku")
                .withCategory("model")
                .withIcon("⚡")
                .withPreview("Fastest model for quick tasks. 200K context window. Great for basic queries.")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/models-overview#claude-3-haiku"),

            CompletionItem.init("claude-3-opus-20240229")
                .withDescription("Most capable Claude 3 model")
                .withCategory("model")
                .withIcon("🚀")
                .withPreview("Highest intelligence for complex tasks. 200K context window. Premium tier.")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/models-overview#claude-3-opus"),
        };

        const result = try allocator.alloc(CompletionItem, models.len);
        @memcpy(result, &models);
        return result;
    }
};

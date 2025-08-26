//! Enhanced autocomplete with fuzzy search using advanced terminal capabilities
//! Leverages @src/term for rich terminal interactions

const std = @import("std");
const term_ansi = @import("../../term/ansi/color.zig");
const term_cursor = @import("../../term/ansi/cursor.zig");
const term_screen = @import("../../term/ansi/screen.zig");
const term_hyperlink = @import("../../term/ansi/hyperlink.zig");
const term_caps = @import("../../term/caps.zig");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const CompletionItem = struct {
    text: []const u8,
    description: ?[]const u8 = null,
    category: ?[]const u8 = null,
    score: f32 = 0.0,
    help_url: ?[]const u8 = null,

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
        };
    }

    pub fn withCategory(self: CompletionItem, cat: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = cat,
            .score = self.score,
            .help_url = self.help_url,
        };
    }

    pub fn withHelpUrl(self: CompletionItem, url: []const u8) CompletionItem {
        return .{
            .text = self.text,
            .description = self.description,
            .category = self.category,
            .score = self.score,
            .help_url = url,
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

    pub fn init(allocator: Allocator) !CompletionEngine {
        return CompletionEngine{
            .items = std.ArrayList(CompletionItem).init(allocator),
            .filtered_items = std.ArrayList(CompletionItem).init(allocator),
            .selected_index = 0,
            .matcher = FuzzyMatcher{},
            .caps = term_caps.getTermCaps(),
            .allocator = allocator,
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

    /// Render completion popup with advanced terminal features
    pub fn render(self: CompletionEngine, writer: anytype) !void {
        if (self.filtered_items.items.len == 0) return;

        const max_items = @min(self.filtered_items.items.len, 10);

        // Save cursor position
        try term_cursor.saveCursor(writer, self.caps);

        // Move cursor up to create space for completion popup
        try term_cursor.cursorUp(writer, self.caps, @intCast(max_items + 2));

        // Clear the completion area
        for (0..max_items + 2) |_| {
            try term_screen.clearLineAll(writer, self.caps);
            try term_cursor.cursorDown(writer, self.caps, 1);
        }

        // Move back up to start drawing
        try term_cursor.cursorUp(writer, self.caps, @intCast(max_items + 2));

        // Draw border with enhanced colors if supported
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237); // Cornflower blue
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12); // Bright blue
        }

        try writer.writeAll("┌─ Completions ─────────────────────────┐\n");

        // Render completion items
        for (self.filtered_items.items[0..max_items], 0..) |item, i| {
            const is_selected = i == self.selected_index;

            try writer.writeAll("│ ");

            if (is_selected) {
                // Highlight selected item
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 80);
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                } else {
                    try term_ansi.setBackground256(writer, self.caps, 18);
                    try term_ansi.setForeground256(writer, self.caps, 15);
                }
                try writer.writeAll("► ");
            } else {
                try writer.writeAll("  ");
            }

            // Category tag if available
            if (item.category) |cat| {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 147, 112, 219); // Medium purple
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 5);
                }
                try writer.print("[{s}] ", .{cat});
            }

            // Main completion text
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 152, 251, 152); // Light green
            } else {
                try term_ansi.setForeground256(writer, self.caps, 10);
            }

            // Add hyperlink if help URL is available
            if (item.help_url) |url| {
                try term_hyperlink.writeHyperlink(writer, self.caps, self.allocator, item.text, url);
            } else {
                try writer.writeAll(item.text);
            }

            // Reset colors
            try term_ansi.resetStyle(writer, self.caps);

            // Description
            if (item.description) |desc| {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 169, 169, 169); // Dark gray
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 8);
                }

                const max_desc_len = 25;
                if (desc.len > max_desc_len) {
                    try writer.print(" - {s}...", .{desc[0..max_desc_len]});
                } else {
                    try writer.print(" - {s}", .{desc});
                }
            }

            // Score display for debugging (only if debug mode)
            if (std.process.hasEnvVar(self.allocator, "DOCZ_DEBUG")) |has_debug| {
                if (has_debug) {
                    try writer.print(" ({d:.1})", .{item.score});
                }
            } else |_| {}

            try term_ansi.resetStyle(writer, self.caps);

            // Pad to edge and close border
            try writer.writeAll("                 │\n");
        }

        // Close border
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }
        try writer.writeAll("└───────────────────────────────────────┘\n");
        try term_ansi.resetStyle(writer, self.caps);

        // Restore cursor position
        try term_cursor.restoreCursor(writer, self.caps);
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
    /// CLI commands completion
    pub fn getCliCommands(allocator: Allocator) ![]CompletionItem {
        const commands = [_]CompletionItem{
            CompletionItem.init("chat")
                .withDescription("Start interactive chat session")
                .withCategory("cmd")
                .withHelpUrl("https://docs.anthropic.com/claude/docs"),

            CompletionItem.init("auth")
                .withDescription("Authentication management")
                .withCategory("cmd")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/authentication"),

            CompletionItem.init("oauth")
                .withDescription("Setup OAuth authentication")
                .withCategory("auth")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/oauth"),

            CompletionItem.init("help")
                .withDescription("Show help information")
                .withCategory("cmd"),

            CompletionItem.init("version")
                .withDescription("Show version information")
                .withCategory("info"),

            CompletionItem.init("status")
                .withDescription("Check authentication status")
                .withCategory("auth"),

            CompletionItem.init("refresh")
                .withDescription("Refresh OAuth token")
                .withCategory("auth"),

            CompletionItem.init("quit")
                .withDescription("Exit the application")
                .withCategory("cmd"),

            CompletionItem.init("exit")
                .withDescription("Exit the application")
                .withCategory("cmd"),
        };

        const result = try allocator.alloc(CompletionItem, commands.len);
        @memcpy(result, &commands);
        return result;
    }

    /// Model names completion
    pub fn getModelNames(allocator: Allocator) ![]CompletionItem {
        const models = [_]CompletionItem{
            CompletionItem.init("claude-3-5-sonnet-20241022")
                .withDescription("Latest Claude 3.5 Sonnet model")
                .withCategory("model"),

            CompletionItem.init("claude-3-haiku-20240307")
                .withDescription("Fast, efficient Claude 3 Haiku")
                .withCategory("model"),

            CompletionItem.init("claude-3-opus-20240229")
                .withDescription("Most capable Claude 3 model")
                .withCategory("model"),
        };

        const result = try allocator.alloc(CompletionItem, models.len);
        @memcpy(result, &models);
        return result;
    }
};

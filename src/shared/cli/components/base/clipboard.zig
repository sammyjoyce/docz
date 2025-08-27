//! Comprehensive clipboard integration for CLI workflows
//! Provides copy/paste functionality using OSC 52 and fallback methods

const std = @import("std");
const components = @import("../../../components/mod.zig");
const term_shared = @import("../../../term/mod.zig");
const term_clipboard = term_shared.ansi.clipboard;
const term_caps = term_shared.caps;
const term_ansi = term_shared.ansi.color;
const notification = @import("../../notifications.zig");
const Allocator = std.mem.Allocator;

pub const ClipboardError = error{
    NotSupported,
    AccessDenied,
    TooLarge,
    InvalidData,
};

pub const ClipboardEntry = struct {
    content: []const u8,
    timestamp: i64,
    content_type: []const u8, // "text", "json", "url", "command", etc.
    source: []const u8, // Which component/command created this entry

    pub fn init(content: []const u8, content_type: []const u8, source: []const u8) ClipboardEntry {
        return .{
            .content = content,
            .timestamp = std.time.timestamp(),
            .content_type = content_type,
            .source = source,
        };
    }
};

pub const Clipboard = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    notificationManager: ?*notification.NotificationHandler,
    history: std.ArrayList(ClipboardEntry),
    maxHistorySize: usize,
    autoTrimLargeContent: bool,
    maxContentSize: usize,
    writer: ?*std.Io.Writer,

    pub fn init(allocator: Allocator) Clipboard {
        return .{
            .allocator = allocator,
            .caps = term_caps.detectCaps(allocator) catch term_caps.TermCaps{
                .supportsTruecolor = false,
                .supportsKittyGraphics = false,
                .supportsSixel = false,
                .supportsHyperlinkOsc8 = false,
                .supportsClipboardOsc52 = false,
                .supportsNotifyOsc9 = false,
                .supportsTitleOsc012 = false,
                .supportsWorkingDirOsc7 = false,
                .supportsFinalTermOsc133 = false,
                .supportsITerm2Osc1337 = false,
                .supportsColorOsc10_12 = false,
                .supportsKittyKeyboard = false,
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
            .notificationManager = null,
            .history = std.ArrayList(ClipboardEntry).init(allocator),
            .maxHistorySize = 50,
            .autoTrimLargeContent = true,
            .maxContentSize = 10000, // 10KB limit for clipboard
            .writer = null,
        };
    }

    pub fn deinit(self: *Clipboard) void {
        // Free all history content
        for (self.history.items) |entry| {
            self.allocator.free(entry.content);
        }
        self.history.deinit();
    }

    pub fn setWriter(self: *Clipboard, writer: *std.Io.Writer) void {
        self.writer = writer;
    }

    pub fn setNotificationManager(self: *Clipboard, manager: *notification.NotificationHandler) void {
        self.notificationManager = manager;
    }

    pub fn configure(
        self: *Clipboard,
        options: struct {
            maxHistorySize: usize = 50,
            autoTrimLargeContent: bool = true,
            maxContentSize: usize = 10000,
        },
    ) void {
        self.maxHistorySize = options.maxHistorySize;
        self.autoTrimLargeContent = options.autoTrimLargeContent;
        self.maxContentSize = options.maxContentSize;
    }

    /// Copy text to system clipboard using OSC 52
    pub fn copy(self: *Clipboard, content: []const u8, content_type: []const u8, source: []const u8) !void {
        if (!self.caps.supportsClipboard()) {
            return ClipboardError.NotSupported;
        }

        if (self.writer == null) {
            return error.NoWriter;
        }

        // Validate content size
        var final_content = content;
        var owned_content: ?[]u8 = null;
        defer if (owned_content) |owned| self.allocator.free(owned);

        if (content.len > self.maxContentSize) {
            if (self.autoTrimLargeContent) {
                owned_content = try self.allocator.alloc(u8, self.maxContentSize);
                @memcpy(owned_content.?[0 .. self.maxContentSize - 3], content[0 .. self.maxContentSize - 3]);
                @memcpy(owned_content.?[self.maxContentSize - 3 ..], "...");
                final_content = owned_content.?;

                if (self.notificationManager) |mgr| {
                    _ = try mgr.notify(.warning, "Clipboard", "Content was truncated due to size limit");
                }
            } else {
                return ClipboardError.TooLarge;
            }
        }

        // Write to clipboard using OSC 52
        try term_clipboard.writeClipboard(self.writer.?, self.allocator, self.caps, final_content);

        // Add to history
        try self.addToHistory(final_content, content_type, source);

        // Send notification
        if (self.notificationManager) |mgr| {
            const notification_msg = try std.fmt.allocPrint(
                self.allocator,
                "Copied {d} characters to clipboard",
                .{final_content.len},
            );
            defer self.allocator.free(notification_msg);

            _ = try mgr.notify(.success, "Clipboard", notification_msg);
        }

        try self.renderCopyConfirmation(final_content, content_type);
    }

    /// Copy structured data (JSON, command output, etc.)
    pub fn copyStructured(self: *Clipboard, data: anytype, source: []const u8) !void {
        const json_content = try std.json.stringifyAlloc(self.allocator, data, .{ .whitespace = .indent_2 });
        defer self.allocator.free(json_content);

        try self.copy(json_content, "json", source);
    }

    /// Copy a command for easy re-execution
    pub fn copyCommand(self: *Clipboard, command: []const u8, args: []const []const u8) !void {
        var command_str = std.ArrayList(u8).init(self.allocator);
        defer command_str.deinit();

        try command_str.appendSlice(command);

        for (args) |arg| {
            try command_str.append(' ');

            // Quote arguments with spaces
            if (std.mem.indexOf(u8, arg, " ")) |_| {
                try command_str.append('"');
                try command_str.appendSlice(arg);
                try command_str.append('"');
            } else {
                try command_str.appendSlice(arg);
            }
        }

        try self.copy(command_str.items, "command", "cli");
    }

    /// Copy URL with validation
    pub fn copyURL(self: *Clipboard, url: []const u8, source: []const u8) !void {
        // Basic URL validation
        if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
            return ClipboardError.InvalidData;
        }

        try self.copy(url, "url", source);
    }

    /// Read from system clipboard (if supported)
    pub fn paste(self: *Clipboard) !?[]const u8 {
        // OSC 52 supports writing but reading is limited
        // For now, return the most recent history entry
        if (self.history.items.len > 0) {
            const recent_entry = self.history.items[self.history.items.len - 1];
            return try self.allocator.dupe(u8, recent_entry.content);
        }

        return null;
    }

    /// Show clipboard history
    pub fn showHistory(self: *Clipboard) !void {
        if (self.writer == null) return error.NoWriter;

        try self.renderHistoryHeader();

        if (self.history.items.len == 0) {
            try self.renderEmptyHistory();
            return;
        }

        // Show recent entries (most recent first)
        const display_count = @min(self.history.items.len, 10);
        var i: usize = self.history.items.len;
        var display_index: usize = 1;

        while (i > 0 and display_index <= display_count) {
            i -= 1;
            const entry = self.history.items[i];

            try self.renderHistoryEntry(display_index, entry);
            display_index += 1;
        }

        try self.renderHistoryFooter();
    }

    /// Clear clipboard history
    pub fn clearHistory(self: *Clipboard) !void {
        for (self.history.items) |entry| {
            self.allocator.free(entry.content);
        }
        self.history.clearRetainingCapacity();

        if (self.notificationManager) |mgr| {
            _ = try mgr.notify(.info, "Clipboard", "History cleared");
        }
    }

    /// Export clipboard history to file
    pub fn exportHistory(self: *Clipboard, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        const writer = file.writer();

        // Write header
        try writer.writeAll("# DocZ Clipboard History Export\n");
        try writer.print("# Exported at: {d}\n", .{std.time.timestamp()});
        try writer.writeAll("# Total entries: ");
        try writer.print("{d}\n\n", .{self.history.items.len});

        // Write each entry
        for (self.history.items, 0..) |entry, i| {
            try writer.print("## Entry {d}\n", .{i + 1});
            try writer.print("- Timestamp: {d}\n", .{entry.timestamp});
            try writer.print("- Type: {s}\n", .{entry.content_type});
            try writer.print("- Source: {s}\n", .{entry.source});
            try writer.print("- Size: {d} characters\n", .{entry.content.len});
            try writer.writeAll("```\n");
            try writer.writeAll(entry.content);
            try writer.writeAll("\n```\n\n");
        }

        if (self.notificationManager) |mgr| {
            _ = try mgr.notify(.success, "Clipboard", "History exported successfully");
        }
    }

    // Private helper methods

    fn addToHistory(self: *Clipboard, content: []const u8, content_type: []const u8, source: []const u8) !void {
        // Create a copy of the content for history
        const content_copy = try self.allocator.dupe(u8, content);
        const type_copy = try self.allocator.dupe(u8, content_type);
        const source_copy = try self.allocator.dupe(u8, source);

        const entry = ClipboardEntry{
            .content = content_copy,
            .timestamp = std.time.timestamp(),
            .content_type = type_copy,
            .source = source_copy,
        };

        try self.history.append(entry);

        // Trim history if too large
        if (self.history.items.len > self.maxHistorySize) {
            const removed = self.history.orderedRemove(0);
            self.allocator.free(removed.content);
            self.allocator.free(removed.content_type);
            self.allocator.free(removed.source);
        }
    }

    fn renderCopyConfirmation(self: *Clipboard, content: []const u8, content_type: []const u8) !void {
        if (self.writer == null) return;
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 10);
        }

        try writer.writeAll("📋 ");

        // Show preview of copied content
        const preview_len = @min(content.len, 50);
        const preview = content[0..preview_len];
        const truncated = content.len > preview_len;

        try writer.print("Copied ({s}): {s}", .{ content_type, preview });
        if (truncated) {
            try writer.writeAll("...");
        }

        try writer.writeAll("\n");
        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderHistoryHeader(self: *Clipboard) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 12);
        }

        try writer.writeAll("\n┌─────────────────────────────────────────────────┐\n");
        try writer.print("│ 📋 Clipboard History ({d} entries)              │\n", .{self.history.items.len});
        try writer.writeAll("└─────────────────────────────────────────────────┘\n\n");

        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderEmptyHistory(self: *Clipboard) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 8);
        }

        try writer.writeAll("   No clipboard history available.\n");
        try writer.writeAll("   Copy some content to see it appear here.\n\n");

        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderHistoryEntry(self: *Clipboard, index: usize, entry: ClipboardEntry) !void {
        const writer = self.writer.?;

        // Entry header
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 11);
        }

        try writer.print("{d}. ", .{index});

        // Content type badge
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 12);
        }
        try writer.print("[{s}] ", .{entry.content_type});

        // Content preview
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 15);
        }

        const preview_len = @min(entry.content.len, 60);
        var preview_content = std.ArrayList(u8).init(self.allocator);
        defer preview_content.deinit();

        // Replace newlines with spaces for preview
        for (entry.content[0..preview_len]) |char| {
            if (char == '\n' or char == '\r') {
                try preview_content.append(' ');
            } else {
                try preview_content.append(char);
            }
        }

        try writer.writeAll(preview_content.items);
        if (entry.content.len > preview_len) {
            try writer.writeAll("...");
        }

        // Metadata
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 8);
        }

        const elapsed = std.time.timestamp() - entry.timestamp;
        try writer.print(" ({s}, {d}s ago, {d} chars)\n", .{ entry.source, elapsed, entry.content.len });

        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderHistoryFooter(self: *Clipboard) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 8);
        }

        try writer.writeAll("\nCommands: 'docz clipboard clear' to clear history\n");
        try writer.writeAll("          'docz clipboard export <file>' to export\n\n");

        try term_ansi.resetStyle(writer.*, self.caps);
    }
};

/// Global clipboard manager instance for easy access across CLI components
pub var globalClipboard: ?*Clipboard = null;

pub fn initGlobalClipboard(allocator: Allocator) !void {
    if (globalClipboard != null) return;

    const manager = try allocator.create(Clipboard);
    manager.* = Clipboard.init(allocator);
    globalClipboard = manager;
}

pub fn deinitGlobalClipboard(allocator: Allocator) void {
    if (globalClipboard) |manager| {
        manager.deinit();
        allocator.destroy(manager);
        globalClipboard = null;
    }
}

/// Quick copy helper for use across CLI components
pub fn quickCopy(content: []const u8, content_type: []const u8, source: []const u8) !void {
    if (globalClipboard) |manager| {
        try manager.copy(content, content_type, source);
    } else {
        return error.ClipboardNotInitialized;
    }
}

/// Quick copy for commands with automatic formatting
pub fn copyCommand(command: []const u8, args: []const []const u8) !void {
    if (globalClipboard) |manager| {
        try manager.copyCommand(command, args);
    } else {
        return error.ClipboardNotInitialized;
    }
}

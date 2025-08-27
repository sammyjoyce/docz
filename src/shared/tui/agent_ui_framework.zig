//! Agent UI Framework
//!
//! This framework provides standardized UI patterns that all agents can use.
//! It includes OAuth flow integration helpers, markdown editing capabilities,
//! consistent theming and styling, keyboard shortcut management, and notification systems.

const std = @import("std");
const renderer_mod = @import("../core/renderer.zig");
const bounds_mod = @import("../core/bounds.zig");
const notification_mod = @import("../notifications.zig");
const progress_mod = @import("../widgets/rich/progress.zig");
const text_input_mod = @import("../widgets/rich/text_input.zig");
const theme_manager_mod = @import("../../theme_manager/mod.zig");
const input_system = @import("../../components/input.zig");
const oauth_mod = @import("../../auth/oauth/mod.zig");
const markdown_renderer = @import("../../render/markdown_renderer.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Style = renderer_mod.Style;
const NotificationController = notification_mod.NotificationController;
const NotificationType = notification_mod.NotificationType;
const ProgressBar = progress_mod.ProgressBar;
const TextInput = text_input_mod.TextInput;
const ThemeManager = theme_manager_mod.ThemeManager;
const InputManager = input_system.InputManager;

/// Standard UI patterns that all agents can use
pub const StandardUIPatterns = struct {
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    theme_manager: *ThemeManager,
    notification_controller: NotificationController,
    input_manager: InputManager,

    /// Initialize the standard UI framework
    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, theme_manager: *ThemeManager) !StandardUIPatterns {
        const notification_controller = NotificationController.init(allocator, renderer);
        const input_manager = try InputManager.init(allocator);

        return StandardUIPatterns{
            .allocator = allocator,
            .renderer = renderer,
            .theme_manager = theme_manager,
            .notification_controller = notification_controller,
            .input_manager = input_manager,
        };
    }

    pub fn deinit(self: *StandardUIPatterns) void {
        self.notification_controller.deinit();
        self.input_manager.deinit();
    }

    /// Show a standard confirmation dialog
    pub fn showConfirmationDialog(self: *StandardUIPatterns, title: []const u8, message: []const u8) !bool {
        const theme = self.theme_manager.getCurrentTheme();

        // Create dialog bounds
        const terminal_size = bounds_mod.getTerminalSize();
        const dialog_width = @min(60, terminal_size.width - 4);
        const dialog_height = 8;
        const dialog_x = (terminal_size.width - dialog_width) / 2;
        const dialog_y = (terminal_size.height - dialog_height) / 2;

        const dialog_bounds = renderer_mod.Bounds{
            .x = dialog_x,
            .y = dialog_y,
            .width = dialog_width,
            .height = dialog_height,
        };

        // Draw dialog background
        const bg_style = Style{
            .bg_color = theme.background,
            .fg_color = theme.foreground,
            .bold = false,
        };

        try self.renderer.drawRect(dialog_bounds, bg_style);

        // Draw dialog border
        const border_style = Style{
            .bg_color = theme.background,
            .fg_color = theme.primary,
            .bold = true,
        };

        try self.renderer.drawBorder(dialog_bounds, border_style, .rounded);

        // Draw title
        const title_bounds = renderer_mod.Bounds{
            .x = dialog_x + 2,
            .y = dialog_y + 1,
            .width = dialog_width - 4,
            .height = 1,
        };

        const title_ctx = RenderContext{
            .bounds = title_bounds,
            .style = .{ .fg_color = theme.primary, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(title_ctx, title);

        // Draw message
        const message_bounds = renderer_mod.Bounds{
            .x = dialog_x + 2,
            .y = dialog_y + 3,
            .width = dialog_width - 4,
            .height = 2,
        };

        const message_ctx = RenderContext{
            .bounds = message_bounds,
            .style = .{ .fg_color = theme.foreground },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(message_ctx, message);

        // Draw buttons
        const button_y = dialog_y + dialog_height - 2;
        const yes_button_bounds = renderer_mod.Bounds{
            .x = dialog_x + 4,
            .y = button_y,
            .width = 8,
            .height = 1,
        };

        const no_button_bounds = renderer_mod.Bounds{
            .x = dialog_x + dialog_width - 12,
            .y = button_y,
            .width = 8,
            .height = 1,
        };

        // Draw Yes button
        const button_ctx = RenderContext{
            .bounds = yes_button_bounds,
            .style = .{ .fg_color = theme.success, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(button_ctx, "[Y]es");

        // Draw No button
        const no_button_ctx = RenderContext{
            .bounds = no_button_bounds,
            .style = .{ .fg_color = theme.error_color, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(no_button_ctx, "[N]o");

        // Wait for input
        while (true) {
            if (try self.input_manager.pollEvent()) |event| {
                switch (event) {
                    .key_press => |key_event| {
                        switch (key_event.code) {
                            .char => |char| {
                                switch (char) {
                                    'y', 'Y' => return true,
                                    'n', 'N' => return false,
                                    else => {},
                                }
                            },
                            .escape => return false,
                            else => {},
                        }
                    },
                    else => {},
                }
            }
            std.time.sleep(10_000_000); // 10ms
        }
    }

    /// Show a progress dialog with cancel option
    pub fn showProgressDialog(self: *StandardUIPatterns, title: []const u8, operation: []const u8) !*ProgressDialog {
        const dialog = try self.allocator.create(ProgressDialog);
        dialog.* = try ProgressDialog.init(self.allocator, self.renderer, self.theme_manager, title, operation);
        return dialog;
    }

    /// Show a notification with standard styling
    pub fn showNotification(self: *StandardUIPatterns, notification_type: NotificationType, title: []const u8, message: []const u8) !void {
        // Use the new notification controller API
        switch (notification_type) {
            .info => try self.notification_controller.info(title, message),
            .success => try self.notification_controller.success(title, message),
            .warning => try self.notification_controller.warning(title, message),
            .@"error" => try self.notification_controller.errorNotification(title, message),
            .debug => try self.notification_controller.debug(title, message),
            .critical => try self.notification_controller.critical(title, message),
            .progress => try self.notification_controller.progress(title, message, 0.0),
        }
    }
};

/// Progress dialog with cancel capability
pub const ProgressDialog = struct {
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    theme_manager: *ThemeManager,
    progress_bar: ProgressBar,
    title: []const u8,
    operation: []const u8,
    cancelled: bool = false,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, theme_manager: *ThemeManager, title: []const u8, operation: []const u8) !ProgressDialog {
        const progress_bar = try ProgressBar.init(allocator, operation, .gradient);

        return ProgressDialog{
            .allocator = allocator,
            .renderer = renderer,
            .theme_manager = theme_manager,
            .progress_bar = progress_bar,
            .title = try allocator.dupe(u8, title),
            .operation = try allocator.dupe(u8, operation),
        };
    }

    pub fn deinit(self: *ProgressDialog) void {
        self.allocator.free(self.title);
        self.allocator.free(self.operation);
        self.progress_bar.deinit();
    }

    pub fn updateProgress(self: *ProgressDialog, progress: f32) !void {
        try self.progress_bar.setProgress(progress);
    }

    pub fn isCancelled(self: *ProgressDialog) bool {
        return self.cancelled;
    }

    pub fn cancel(self: *ProgressDialog) void {
        self.cancelled = true;
    }
};

/// OAuth flow integration helpers
pub const OAuthIntegration = struct {
    allocator: std.mem.Allocator,
    oauth_manager: oauth_mod.OAuthManager,

    pub fn init(allocator: std.mem.Allocator, config: oauth_mod.OAuthConfig) !OAuthIntegration {
        const oauth_manager = try oauth_mod.OAuthManager.init(allocator, config);

        return OAuthIntegration{
            .allocator = allocator,
            .oauth_manager = oauth_manager,
        };
    }

    pub fn deinit(self: *OAuthIntegration) void {
        self.oauth_manager.deinit();
    }

    /// Run complete OAuth flow with UI integration
    pub fn runOAuthFlow(self: *OAuthIntegration, ui_patterns: *StandardUIPatterns) !oauth_mod.OAuthCredentials {
        // Show initial setup notification
        try ui_patterns.showNotification(.info, "OAuth Setup", "Starting authentication flow...");

        // Generate authorization URL
        const auth_url = try self.oauth_manager.generateAuthUrl();
        defer self.allocator.free(auth_url);

        // Show URL to user
        const url_message = try std.fmt.allocPrint(self.allocator, "Please visit: {s}", .{auth_url});
        defer self.allocator.free(url_message);

        try ui_patterns.showNotification(.info, "Authorization URL", url_message);

        // Wait for authorization code
        const code = try self.waitForAuthCode(ui_patterns);
        defer self.allocator.free(code);

        // Show progress for token exchange
        const progress_dialog = try ui_patterns.showProgressDialog("OAuth Setup", "Exchanging authorization code for tokens...");
        defer {
            progress_dialog.deinit();
            self.allocator.destroy(progress_dialog);
        }

        try progress_dialog.updateProgress(0.5);

        // Exchange code for tokens
        const credentials = try self.oauth_manager.exchangeCode(code);
        try progress_dialog.updateProgress(1.0);

        // Show success notification
        try ui_patterns.showNotification(.success, "OAuth Complete", "Authentication successful!");

        return credentials;
    }

    /// Wait for authorization code with UI feedback
    fn waitForAuthCode(self: *OAuthIntegration, ui_patterns: *StandardUIPatterns) ![]const u8 {
        _ = self; // Method doesn't use self but needs to be instance method for future extensibility
        const theme = ui_patterns.theme_manager.getCurrentTheme();

        // Create input field for code entry
        const input_bounds = renderer_mod.Bounds{
            .x = 4,
            .y = 10,
            .width = 60,
            .height = 3,
        };

        const input_ctx = RenderContext{
            .bounds = input_bounds,
            .style = .{ .fg_color = theme.foreground },
            .zIndex = 0,
            .clipRegion = null,
        };

        // Draw input prompt
        const prompt_bounds = renderer_mod.Bounds{
            .x = 4,
            .y = 8,
            .width = 60,
            .height = 2,
        };

        const prompt_ctx = RenderContext{
            .bounds = prompt_bounds,
            .style = .{ .fg_color = theme.primary, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        try ui_patterns.renderer.drawText(prompt_ctx, "Enter authorization code:");
        try ui_patterns.renderer.drawText(input_ctx, "Waiting for code... (Ctrl+V to paste, Enter to submit)");

        // Wait for user input
        var code_buffer = std.ArrayList(u8).init(ui_patterns.allocator);
        defer code_buffer.deinit();

        while (true) {
            if (try ui_patterns.input_manager.pollEvent()) |event| {
                switch (event) {
                    .key_press => |key_event| {
                        switch (key_event.code) {
                            .enter => {
                                if (code_buffer.items.len > 0) {
                                    return ui_patterns.allocator.dupe(u8, code_buffer.items);
                                }
                            },
                            .char => |char| {
                                try code_buffer.append(char);
                            },
                            .backspace => {
                                if (code_buffer.items.len > 0) {
                                    _ = code_buffer.pop();
                                }
                            },
                            .escape => {
                                return error.UserCancelled;
                            },
                            else => {},
                        }
                    },
                    .paste => |paste_event| {
                        try code_buffer.appendSlice(paste_event.text);
                    },
                    else => {},
                }
            }
            std.time.sleep(10_000_000); // 10ms
        }
    }
};

/// Markdown editing capabilities
pub const MarkdownEditor = struct {
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    theme_manager: *ThemeManager,
    content: std.ArrayList(u8),
    cursor_position: usize = 0,
    scroll_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, theme_manager: *ThemeManager) !MarkdownEditor {
        return MarkdownEditor{
            .allocator = allocator,
            .renderer = renderer,
            .theme_manager = theme_manager,
            .content = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *MarkdownEditor) void {
        self.content.deinit();
    }

    /// Load markdown content
    pub fn loadContent(self: *MarkdownEditor, content: []const u8) !void {
        try self.content.resize(0);
        try self.content.appendSlice(content);
        self.cursor_position = 0;
        self.scroll_offset = 0;
    }

    /// Get current content
    pub fn getContent(self: *MarkdownEditor) []const u8 {
        return self.content.items;
    }

    /// Insert text at cursor position
    pub fn insertText(self: *MarkdownEditor, text: []const u8) !void {
        try self.content.insertSlice(self.cursor_position, text);
        self.cursor_position += text.len;
    }

    /// Delete character at cursor position
    pub fn deleteChar(self: *MarkdownEditor) void {
        if (self.cursor_position < self.content.items.len) {
            _ = self.content.orderedRemove(self.cursor_position);
        }
    }

    /// Move cursor
    pub fn moveCursor(self: *MarkdownEditor, direction: enum { left, right, up, down }) void {
        switch (direction) {
            .left => {
                if (self.cursor_position > 0) {
                    self.cursor_position -= 1;
                }
            },
            .right => {
                if (self.cursor_position < self.content.items.len) {
                    self.cursor_position += 1;
                }
            },
            .up => {
                // Find previous line
                var pos = self.cursor_position;
                if (pos > 0) {
                    pos -= 1;
                    while (pos > 0 and self.content.items[pos] != '\n') {
                        pos -= 1;
                    }
                    if (pos > 0) {
                        self.cursor_position = pos;
                    }
                }
            },
            .down => {
                // Find next line
                var pos = self.cursor_position;
                while (pos < self.content.items.len and self.content.items[pos] != '\n') {
                    pos += 1;
                }
                if (pos < self.content.items.len) {
                    pos += 1;
                    self.cursor_position = pos;
                }
            },
        }
    }

    /// Render the editor
    pub fn render(self: *MarkdownEditor, bounds: renderer_mod.Bounds) !void {
        const theme = self.theme_manager.getCurrentTheme();

        // Draw editor border
        const border_style = Style{
            .bg_color = theme.background,
            .fg_color = theme.primary,
            .bold = true,
        };

        try self.renderer.drawBorder(bounds, border_style, .single);

        // Draw content area
        const content_bounds = renderer_mod.Bounds{
            .x = bounds.x + 1,
            .y = bounds.y + 1,
            .width = bounds.width - 2,
            .height = bounds.height - 2,
        };

        // Calculate visible content
        const visible_lines = content_bounds.height;
        const start_line = self.scroll_offset;
        var current_line: usize = 0;
        var char_index: usize = 0;

        // Find start of visible content
        while (char_index < self.content.items.len and current_line < start_line) {
            if (self.content.items[char_index] == '\n') {
                current_line += 1;
            }
            char_index += 1;
        }

        // Render visible lines
        var line_start = char_index;
        var render_y = content_bounds.y;

        while (render_y < content_bounds.y + visible_lines and char_index < self.content.items.len) {
            // Find end of current line
            var line_end = line_start;
            while (line_end < self.content.items.len and self.content.items[line_end] != '\n') {
                line_end += 1;
            }

            const line_content = self.content.items[line_start..line_end];
            const line_bounds = renderer_mod.Bounds{
                .x = content_bounds.x,
                .y = render_y,
                .width = content_bounds.width,
                .height = 1,
            };

            const line_ctx = RenderContext{
                .bounds = line_bounds,
                .style = .{ .fg_color = theme.foreground },
                .zIndex = 0,
                .clipRegion = null,
            };

            try self.renderer.drawText(line_ctx, line_content);

            // Check if cursor is on this line
            if (self.cursor_position >= line_start and self.cursor_position <= line_end) {
                const cursor_x = content_bounds.x + (self.cursor_position - line_start);
                const cursor_bounds = renderer_mod.Bounds{
                    .x = @intCast(cursor_x),
                    .y = render_y,
                    .width = 1,
                    .height = 1,
                };

                const cursor_ctx = RenderContext{
                    .bounds = cursor_bounds,
                    .style = .{ .fg_color = theme.cursor, .bg_color = theme.cursor_bg, .bold = true },
                    .zIndex = 0,
                    .clipRegion = null,
                };

                try self.renderer.drawText(cursor_ctx, "█");
            }

            render_y += 1;
            line_start = line_end + 1;
            char_index = line_start;
        }
    }
};

/// Keyboard shortcut management
pub const KeyboardShortcuts = struct {
    allocator: std.mem.Allocator,
    shortcuts: std.StringHashMap(ShortcutAction),

    pub const ShortcutAction = struct {
        description: []const u8,
        action: *const fn (*anyopaque) void,
        context: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) !KeyboardShortcuts {
        return KeyboardShortcuts{
            .allocator = allocator,
            .shortcuts = std.StringHashMap(ShortcutAction).init(allocator),
        };
    }

    pub fn deinit(self: *KeyboardShortcuts) void {
        var it = self.shortcuts.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.description);
        }
        self.shortcuts.deinit();
    }

    /// Register a keyboard shortcut
    pub fn registerShortcut(self: *KeyboardShortcuts, key_sequence: []const u8, description: []const u8, action: *const fn (*anyopaque) void, context: *anyopaque) !void {
        const key_dup = try self.allocator.dupe(u8, key_sequence);
        const desc_dup = try self.allocator.dupe(u8, description);

        try self.shortcuts.put(key_dup, ShortcutAction{
            .description = desc_dup,
            .action = action,
            .context = context,
        });
    }

    /// Handle key press and execute shortcut if matched
    pub fn handleKeyPress(self: *KeyboardShortcuts, key_sequence: []const u8) bool {
        if (self.shortcuts.get(key_sequence)) |shortcut| {
            shortcut.action(shortcut.context);
            return true;
        }
        return false;
    }

    /// Get all registered shortcuts
    pub fn getAllShortcuts(self: *KeyboardShortcuts) []const struct { key: []const u8, description: []const u8 } {
        var result = std.ArrayList(struct { key: []const u8, description: []const u8 }).init(self.allocator);
        defer result.deinit();

        var it = self.shortcuts.iterator();
        while (it.next()) |entry| {
            result.append(.{
                .key = entry.key_ptr.*,
                .description = entry.value_ptr.description,
            }) catch continue;
        }

        return result.toOwnedSlice() catch &[_]struct { key: []const u8, description: []const u8 }{};
    }
};

/// Convenience functions for common UI patterns
pub const UIFactory = struct {
    /// Create a standard agent header
    pub fn createAgentHeader(allocator: std.mem.Allocator, agent_name: []const u8, agent_version: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "🤖 {s} v{s} - AI Agent", .{ agent_name, agent_version });
    }

    /// Create a standard status message
    pub fn createStatusMessage(allocator: std.mem.Allocator, status_type: NotificationType, message: []const u8) ![]const u8 {
        const icon = switch (status_type) {
            .info => "ℹ️",
            .success => "✅",
            .warning => "⚠️",
            .@"error" => "❌",
        };

        return std.fmt.allocPrint(allocator, "{s} {s}", .{ icon, message });
    }

    /// Create a progress indicator message
    pub fn createProgressMessage(allocator: std.mem.Allocator, operation: []const u8, progress: f32) ![]const u8 {
        const percentage = @as(u32, @intFromFloat(progress * 100));
        return std.fmt.allocPrint(allocator, "{s}... {d}%", .{ operation, percentage });
    }
};

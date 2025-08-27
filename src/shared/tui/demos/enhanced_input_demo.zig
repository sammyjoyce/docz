//! Enhanced Input Demo
//! Demonstrates the new comprehensive input system with focus, paste, and mouse features
const std = @import("std");
const tui = @import("../mod.zig");
const input_system = @import("../core/input/mod.zig");
const enhanced_text_input = @import("../widgets/enhanced/enhanced_text_input.zig");
const term = @import("../../../term/unified.zig");

const DemoState = struct {
    allocator: std.mem.Allocator,
    event_system: input_system.EventSystem,
    focus_manager: input_system.FocusManager,
    paste_manager: input_system.PasteManager,
    mouse_manager: input_system.MouseManager,

    // Widgets
    text_input1: enhanced_text_input.EnhancedTextInput,
    text_input2: enhanced_text_input.EnhancedTextInput,
    password_input: enhanced_text_input.EnhancedTextInput,

    // Demo state
    current_widget: u8,
    event_log: std.ArrayListUnmanaged([]const u8),
    mouse_position: input_system.Position,
    last_paste: ?[]const u8,

    // Rendering
    renderer: tui.Renderer,
    terminal_size: tui.TerminalSize,
    should_exit: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var demo = Self{
            .allocator = allocator,
            .event_system = input_system.EventSystem.init(allocator),
            .focus_manager = input_system.FocusManager.init(allocator),
            .paste_manager = input_system.PasteManager.init(allocator),
            .mouse_manager = input_system.MouseManager.init(allocator),
            .text_input1 = undefined,
            .text_input2 = undefined,
            .password_input = undefined,
            .current_widget = 0,
            .event_log = std.ArrayListUnmanaged([]const u8){},
            .mouse_position = input_system.Position{ .x = 0, .y = 0 },
            .last_paste = null,
            .renderer = undefined,
            .terminal_size = try tui.getTerminalSize(),
            .should_exit = false,
        };

        // Initialize renderer
        const caps = try term.detectCapabilities();
        demo.renderer = try tui.createRenderer(allocator, caps);

        // Initialize widgets
        demo.text_input1 = try enhanced_text_input.EnhancedTextInput.init(
            allocator,
            tui.Bounds{ .x = 2, .y = 3, .width = 40, .height = 3 },
            "Enter text here...",
            &demo.focus_manager,
            &demo.paste_manager,
            &demo.mouse_manager,
        );

        demo.text_input2 = try enhanced_text_input.EnhancedTextInput.init(
            allocator,
            tui.Bounds{ .x = 2, .y = 7, .width = 40, .height = 3 },
            "Second input field...",
            &demo.focus_manager,
            &demo.paste_manager,
            &demo.mouse_manager,
        );

        demo.password_input = try enhanced_text_input.EnhancedTextInput.init(
            allocator,
            tui.Bounds{ .x = 2, .y = 11, .width = 40, .height = 3 },
            "Password...",
            &demo.focus_manager,
            &demo.paste_manager,
            &demo.mouse_manager,
        );
        demo.password_input.setPassword(true);

        // Set up callbacks
        demo.text_input1.on_change = Self.onTextChange;
        demo.text_input2.on_change = Self.onTextChange;
        demo.password_input.on_change = Self.onPasswordChange;

        // Register global event handlers
        try demo.registerEventHandlers();

        return demo;
    }

    pub fn deinit(self: *Self) void {
        self.text_input1.deinit();
        self.text_input2.deinit();
        self.password_input.deinit();

        // Clean up event log
        for (self.event_log.items) |msg| {
            self.allocator.free(msg);
        }
        self.event_log.deinit(self.allocator);

        if (self.last_paste) |paste| {
            self.allocator.free(paste);
        }

        self.event_system.deinit();
        self.focus_manager.deinit();
        self.paste_manager.deinit();
        self.mouse_manager.deinit();
        self.renderer.deinit();
    }

    fn registerEventHandlers(self: *Self) !void {
        // Global mouse tracking
        const mouse_handler = input_system.MouseHandler{
            .func = struct {
                fn handle(demo_ptr: *Self) *const fn (input_system.MouseEvent) bool {
                    return struct {
                        fn inner(event: input_system.MouseEvent) bool {
                            const mouse = event.mouse();
                            demo_ptr.mouse_position = input_system.Position{ .x = mouse.x, .y = mouse.y };
                            return false; // Allow other handlers to process
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.mouse_manager.addHandler(mouse_handler);

        // Global focus tracking
        const focus_handler = input_system.FocusHandler{
            .func = struct {
                fn handle(demo_ptr: *Self) *const fn (bool) void {
                    return struct {
                        fn inner(has_focus: bool) void {
                            const msg = if (has_focus) "Application gained focus" else "Application lost focus";
                            demo_ptr.logEvent(msg) catch {};
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.focus_manager.addHandler(focus_handler);

        // Global paste tracking
        const paste_handler = input_system.PasteHandler{
            .func = struct {
                fn handle(demo_ptr: *Self) *const fn ([]const u8) void {
                    return struct {
                        fn inner(content: []const u8) void {
                            if (demo_ptr.last_paste) |old_paste| {
                                demo_ptr.allocator.free(old_paste);
                            }
                            demo_ptr.last_paste = demo_ptr.allocator.dupe(u8, content) catch null;

                            const msg = std.fmt.allocPrint(demo_ptr.allocator, "Pasted: {d} chars", .{content.len}) catch return;
                            demo_ptr.logEvent(msg) catch {};
                        }
                    }.inner;
                }
            }.handle(self),
        };
        try self.paste_manager.addHandler(paste_handler);
    }

    pub fn run(self: *Self) !void {
        // Initialize terminal
        try self.setupTerminal();
        defer self.teardownTerminal() catch {};

        // Enable input features
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try input_system.FocusManager.enableFocusReporting(stdout);
        try input_system.PasteManager.enableBracketedPaste(stdout);
        try self.mouse_manager.enableMouseTracking(stdout, .sgr_pixels);

        // Initial render
        try self.render();

        // Focus first widget
        self.text_input1.focus();

        // Main event loop
        var input_buffer: [1024]u8 = undefined;
        while (!self.should_exit) {
            // Read input
            var stdin_buffer: [4096]u8 = undefined;
            var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
            const stdin = &stdin_reader.interface;
            const bytes_read = try stdin.read(&input_buffer);
            if (bytes_read == 0) continue;

            // Process input through event system
            try self.event_system.processInput(input_buffer[0..bytes_read]);

            // Handle keyboard events for widget navigation
            try self.handleGlobalKeyEvents(input_buffer[0..bytes_read]);

            // Render if needed
            try self.render();

            // Small delay to prevent busy loop
            std.time.sleep(1000000); // 1ms
        }
    }

    fn setupTerminal(self: *Self) !void {
        _ = self;
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Enter alternate screen buffer
        try stdout.writeAll("\x1b[?1049h");

        // Hide cursor initially
        try stdout.writeAll("\x1b[?25l");

        // Clear screen
        try stdout.writeAll("\x1b[2J\x1b[1;1H");

        // Set raw mode (platform-specific)
        if (std.builtin.os.tag == .windows) {
            // Windows terminal setup would go here
        } else {
            // Unix-like systems
            const c = @cImport({
                @cInclude("termios.h");
                @cInclude("unistd.h");
            });
            var termios: c.termios = undefined;
            _ = c.tcgetattr(c.STDIN_FILENO, &termios);
            termios.c_lflag &= ~(@as(c_uint, @bitCast(c.ICANON | c.ECHO)));
            _ = c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &termios);
        }
    }

    fn teardownTerminal(self: *Self) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Disable input features
        try input_system.FocusManager.disableFocusReporting(stdout);
        try input_system.PasteManager.disableBracketedPaste(stdout);
        try self.mouse_manager.disableMouseTracking(stdout);

        // Show cursor
        try stdout.writeAll("\x1b[?25h");

        // Exit alternate screen buffer
        try stdout.writeAll("\x1b[?1049l");

        // Reset terminal mode (simplified)
        if (std.builtin.os.tag != .windows) {
            const c = @cImport({
                @cInclude("termios.h");
                @cInclude("unistd.h");
            });
            var termios: c.termios = undefined;
            _ = c.tcgetattr(c.STDIN_FILENO, &termios);
            termios.c_lflag |= (@as(c_uint, @bitCast(c.ICANON | c.ECHO)));
            _ = c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &termios);
        }
    }

    fn handleGlobalKeyEvents(self: *Self, input: []const u8) !void {
        // Simple escape sequence detection for demo navigation
        if (std.mem.eql(u8, input, "\x1b")) { // ESC
            self.should_exit = true;
        } else if (std.mem.eql(u8, input, "\t")) { // Tab
            self.switchToNextWidget();
        } else if (std.mem.eql(u8, input, "\x1b[Z")) { // Shift+Tab
            self.switchToPrevWidget();
        } else {
            // Forward to current widget
            // This is a simplified approach - in practice you'd parse the input more thoroughly
        }
    }

    fn switchToNextWidget(self: *Self) void {
        // Blur current widget
        switch (self.current_widget) {
            0 => self.text_input1.blur(),
            1 => self.text_input2.blur(),
            2 => self.password_input.blur(),
            else => {},
        }

        // Move to next widget
        self.current_widget = (self.current_widget + 1) % 3;

        // Focus new widget
        switch (self.current_widget) {
            0 => self.text_input1.focus(),
            1 => self.text_input2.focus(),
            2 => self.password_input.focus(),
            else => {},
        }

        self.logEvent("Widget focus changed") catch {};
    }

    fn switchToPrevWidget(self: *Self) void {
        // Blur current widget
        switch (self.current_widget) {
            0 => self.text_input1.blur(),
            1 => self.text_input2.blur(),
            2 => self.password_input.blur(),
            else => {},
        }

        // Move to previous widget
        self.current_widget = if (self.current_widget == 0) 2 else self.current_widget - 1;

        // Focus new widget
        switch (self.current_widget) {
            0 => self.text_input1.focus(),
            1 => self.text_input2.focus(),
            2 => self.password_input.focus(),
            else => {},
        }
    }

    fn render(self: *Self) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Clear screen
        try stdout.writeAll("\x1b[1;1H\x1b[2J");

        // Title
        const title = "Enhanced Input Demo - Focus, Paste, Mouse Support";
        try self.renderer.setForegroundColor("\x1b[1;36m"); // Bright cyan
        try self.renderer.drawText(2, 1, title);

        // Instructions
        try self.renderer.setForegroundColor("\x1b[37m"); // White
        try self.renderer.drawText(2, 2, "Tab: Switch widgets | ESC: Exit | Try: typing, pasting, clicking, dragging");

        // Render widgets
        try self.text_input1.render(&self.renderer);
        try self.text_input2.render(&self.renderer);
        try self.password_input.render(&self.renderer);

        // Status panel
        try self.renderStatusPanel();

        // Event log
        try self.renderEventLog();

        try stdout.print("\x1b[0m"); // Reset colors
    }

    fn renderStatusPanel(self: *Self) !void {
        const start_y = 15;

        // Status panel border
        try self.renderer.setForegroundColor("\x1b[33m"); // Yellow
        try self.renderer.drawBorder(tui.Bounds{ .x = 2, .y = start_y, .width = 60, .height = 10 }, tui.BoxStyle.rounded);

        try self.renderer.setForegroundColor("\x1b[1;33m");
        try self.renderer.drawText(4, start_y, " Status ");

        // Display status information
        try self.renderer.setForegroundColor("\x1b[37m");
        try self.renderer.drawText(4, start_y + 2, std.fmt.allocPrint(self.allocator, "Current Widget: {d} | Focus: {s} | Mouse: ({d},{d})", .{ self.current_widget + 1, if (self.focus_manager.hasFocus()) "Yes" else "No", self.mouse_position.x, self.mouse_position.y }) catch "Status unavailable");

        try self.renderer.drawText(4, start_y + 3, std.fmt.allocPrint(self.allocator, "Paste Mode: {s} | Terminal: {d}x{d}", .{ if (self.paste_manager.isPasting()) "Active" else "Inactive", self.terminal_size.width, self.terminal_size.height }) catch "Status unavailable");

        // Widget content preview
        try self.renderer.drawText(4, start_y + 5, "Widget Contents:");
        try self.renderer.drawText(4, start_y + 6, std.fmt.allocPrint(self.allocator, "1: {s}", .{if (self.text_input1.getText().len > 0) self.text_input1.getText()[0..@min(30, self.text_input1.getText().len)] else "(empty)"}) catch "1: (error)");
        try self.renderer.drawText(4, start_y + 7, std.fmt.allocPrint(self.allocator, "2: {s}", .{if (self.text_input2.getText().len > 0) self.text_input2.getText()[0..@min(30, self.text_input2.getText().len)] else "(empty)"}) catch "2: (error)");
        try self.renderer.drawText(4, start_y + 8, std.fmt.allocPrint(self.allocator, "3: {s}", .{if (!self.password_input.isEmpty()) "***password***" else "(empty)"}) catch "3: (error)");
    }

    fn renderEventLog(self: *Self) !void {
        const start_x = 65;
        const start_y = 3;
        const log_height = 20;

        // Event log border
        try self.renderer.setForegroundColor("\x1b[32m"); // Green
        try self.renderer.drawBorder(tui.Bounds{ .x = start_x, .y = start_y, .width = 50, .height = log_height + 2 }, tui.BoxStyle.rounded);

        try self.renderer.setForegroundColor("\x1b[1;32m");
        try self.renderer.drawText(start_x + 2, start_y, " Event Log ");

        // Display recent events
        try self.renderer.setForegroundColor("\x1b[37m");
        const start_idx = if (self.event_log.items.len > log_height) self.event_log.items.len - log_height else 0;
        for (self.event_log.items[start_idx..], 0..) |event, i| {
            try self.renderer.drawText(start_x + 2, start_y + 2 + @as(i32, @intCast(i)), event[0..@min(event.len, 45)]);
        }
    }

    fn logEvent(self: *Self, message: []const u8) !void {
        const timestamp = std.time.milliTimestamp();
        const formatted = try std.fmt.allocPrint(self.allocator, "[{d}] {s}", .{ timestamp % 100000, message });

        try self.event_log.append(self.allocator, formatted);

        // Keep only recent events
        if (self.event_log.items.len > 100) {
            self.allocator.free(self.event_log.items[0]);
            _ = self.event_log.orderedRemove(0);
        }
    }

    // Widget callbacks
    fn onTextChange(content: []const u8) void {
        _ = content;
        // This would be implemented with proper context passing in a real application
    }

    fn onPasswordChange(content: []const u8) void {
        _ = content;
        // This would be implemented with proper context passing in a real application
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var demo = try DemoState.init(allocator);
    defer demo.deinit();

    try demo.run();
}

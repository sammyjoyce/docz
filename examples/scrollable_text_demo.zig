//! ScrollableTextArea Demo
//!
//! This demo showcases the comprehensive ScrollableTextArea widget with:
//! - Loading and viewing large text files
//! - Word wrapping modes (none, word, character)
//! - Search functionality with highlighting
//! - Line numbers display
//! - Syntax highlighting example
//! - Both read-only and editable modes
//! - Keyboard and mouse navigation

const std = @import("std");
const Allocator = std.mem.Allocator;

// TUI imports
const tui = @import("../src/shared/tui/mod.zig");
const renderer_mod = @import("../src/shared/tui/core/renderer.zig");
const Renderer = renderer_mod.Renderer;
const Bounds = renderer_mod.Bounds;
const InputEvent = renderer_mod.InputEvent;
const ScrollableTextArea = @import("../src/shared/tui/widgets/core/ScrollableTextArea.zig").ScrollableTextArea;
const WordWrapMode = @import("../src/shared/tui/widgets/core/ScrollableTextArea.zig").WordWrapMode;
const Style = renderer_mod.Style;

/// Demo application state
pub const DemoApp = struct {
    allocator: Allocator,
    renderer: *Renderer,
    text_area: ScrollableTextArea,
    current_mode: DemoMode = .view,
    show_help: bool = false,
    sample_texts: std.StringHashMap([]const u8),

    pub const DemoMode = enum {
        view, // Read-only text viewing
        edit, // Editable text
        search, // Search demonstration
        syntax, // Syntax highlighting demo
    };

    /// Initialize the demo application
    pub fn init(allocator: Allocator, renderer: *Renderer) !DemoApp {
        var text_area = try ScrollableTextArea.init(allocator, .{
            .show_line_numbers = true,
            .word_wrap = .none,
            .smooth_scrolling = true,
            .syntax_highlight = false,
            .read_only = true,
            .show_scrollbars = true,
            .highlight_current_line = true,
            .mouse_support = true,
            .keyboard_navigation = true,
        });

        var sample_texts = std.StringHashMap([]const u8).init(allocator);

        // Add sample texts
        try sample_texts.put("lorem", try createLoremIpsum(allocator));
        try sample_texts.put("code", try createCodeSample(allocator));
        try sample_texts.put("large", try createLargeText(allocator));

        // Start with lorem ipsum
        const lorem_text = sample_texts.get("lorem").?;
        try text_area.setText(lorem_text);

        return DemoApp{
            .allocator = allocator,
            .renderer = renderer,
            .text_area = text_area,
            .sample_texts = sample_texts,
        };
    }

    /// Deinitialize the demo application
    pub fn deinit(self: *DemoApp) void {
        self.text_area.deinit();
        var it = self.sample_texts.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.sample_texts.deinit();
    }

    /// Handle input events
    pub fn handleInput(self: *DemoApp, event: InputEvent) !bool {
        // Handle global shortcuts first
        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .char => |char| {
                        switch (char) {
                            '1' => {
                                self.switchMode(.view);
                                return true;
                            },
                            '2' => {
                                self.switchMode(.edit);
                                return true;
                            },
                            '3' => {
                                self.switchMode(.search);
                                return true;
                            },
                            '4' => {
                                self.switchMode(.syntax);
                                return true;
                            },
                            'l' => {
                                try self.loadSampleText("lorem");
                                return true;
                            },
                            'c' => {
                                try self.loadSampleText("code");
                                return true;
                            },
                            'L' => {
                                try self.loadSampleText("large");
                                return true;
                            },
                            'w' => {
                                self.toggleWordWrap();
                                return true;
                            },
                            'n' => {
                                self.toggleLineNumbers();
                                return true;
                            },
                            'h' => {
                                self.show_help = !self.show_help;
                                return true;
                            },
                            'q' => {
                                return false; // Quit
                            },
                            else => {},
                        }
                    },
                    .escape => {
                        if (self.show_help) {
                            self.show_help = false;
                            return true;
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        // Pass input to text area
        switch (event) {
            .key => |key_event| {
                try self.text_area.handleKeyboard(key_event.key);
            },
            .mouse => |mouse_event| {
                try self.text_area.handleMouse(mouse_event);
            },
            else => {},
        }

        return true;
    }

    /// Render the demo application
    pub fn render(self: *DemoApp, bounds: Bounds) !void {
        // Clear screen
        try self.renderer.clear(bounds);

        if (self.show_help) {
            try self.renderHelp(bounds);
            return;
        }

        // Calculate layout
        const status_height = 3;
        const help_height = 2;
        const text_area_height = bounds.height - status_height - help_height;

        const text_area_bounds = Bounds{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = text_area_height,
        };

        const status_bounds = Bounds{
            .x = bounds.x,
            .y = bounds.y + text_area_height,
            .width = bounds.width,
            .height = status_height,
        };

        const help_bounds = Bounds{
            .x = bounds.x,
            .y = bounds.y + text_area_height + status_height,
            .width = bounds.width,
            .height = help_height,
        };

        // Render text area
        try self.text_area.render(self.renderer, text_area_bounds);

        // Render status bar
        try self.renderStatusBar(status_bounds);

        // Render help bar
        try self.renderHelpBar(help_bounds);
    }

    /// Switch demo mode
    fn switchMode(self: *DemoApp, mode: DemoMode) void {
        self.current_mode = mode;

        switch (mode) {
            .view => {
                self.text_area.config.read_only = true;
                self.text_area.config.syntax_highlight = false;
            },
            .edit => {
                self.text_area.config.read_only = false;
                self.text_area.config.syntax_highlight = false;
            },
            .search => {
                self.text_area.config.read_only = true;
                self.text_area.config.syntax_highlight = false;
                // Load search sample
                if (self.sample_texts.get("code")) |code_text| {
                    self.text_area.setText(code_text) catch {};
                    self.text_area.search("function") catch {};
                }
            },
            .syntax => {
                self.text_area.config.read_only = true;
                self.text_area.config.syntax_highlight = true;
                self.text_area.config.syntax_highlight_fn = syntaxHighlightCallback;
                // Load code sample for syntax highlighting
                if (self.sample_texts.get("code")) |code_text| {
                    self.text_area.setText(code_text) catch {};
                }
            },
        }
    }

    /// Load sample text
    fn loadSampleText(self: *DemoApp, key: []const u8) !void {
        if (self.sample_texts.get(key)) |text| {
            try self.text_area.setText(text);
            self.text_area.clearSelection();
            self.text_area.search_query.clearRetainingCapacity();
            self.text_area.search_matches.clearRetainingCapacity();
        }
    }

    /// Toggle word wrap
    fn toggleWordWrap(self: *DemoApp) void {
        self.text_area.config.word_wrap = switch (self.text_area.config.word_wrap) {
            .none => .word,
            .word => .character,
            .character => .none,
        };
    }

    /// Toggle line numbers
    fn toggleLineNumbers(self: *DemoApp) void {
        self.text_area.config.show_line_numbers = !self.text_area.config.show_line_numbers;
    }

    /// Render status bar
    fn renderStatusBar(self: *DemoApp, bounds: Bounds) !void {
        const mode_text = switch (self.current_mode) {
            .view => "VIEW MODE (Read-only)",
            .edit => "EDIT MODE",
            .search => "SEARCH MODE",
            .syntax => "SYNTAX HIGHLIGHTING MODE",
        };

        const word_wrap_text = switch (self.text_area.config.word_wrap) {
            .none => "No Wrap",
            .word => "Word Wrap",
            .character => "Char Wrap",
        };

        const line_info = try std.fmt.allocPrint(self.allocator, "Ln {d}, Col {d} | Lines: {d} | {s} | {s}", .{
            self.text_area.cursor_line + 1,
            self.text_area.cursor_col + 1,
            self.text_area.lines.items.len,
            mode_text,
            word_wrap_text,
        });
        defer self.allocator.free(line_info);

        // Status bar background
        try self.renderer.fillRect(bounds, .{ .indexed = 236 }); // Light gray

        // Status text
        try self.renderer.drawText(bounds.x + 1, bounds.y, line_info, .{
            .fg = .{ .indexed = 0 }, // Black text
            .bold = true,
        });

        // Search info if applicable
        if (self.text_area.search_matches.items.len > 0) {
            const search_info = try std.fmt.allocPrint(self.allocator, " | Found: {d} matches", .{self.text_area.search_matches.items.len});
            defer self.allocator.free(search_info);

            try self.renderer.drawText(bounds.x + @as(i32, @intCast(line_info.len)) + 1, bounds.y, search_info, .{
                .fg = .{ .indexed = 4 }, // Blue text
                .bold = true,
            });
        }
    }

    /// Render help bar
    fn renderHelpBar(self: *DemoApp, bounds: Bounds) !void {
        const help_text = "1-4:Mode  l:Lorem  c:Code  L:Large  w:Wrap  n:Numbers  h:Help  q:Quit";

        // Help bar background
        try self.renderer.fillRect(bounds, .{ .indexed = 238 }); // Darker gray

        // Help text
        try self.renderer.drawText(bounds.x + 1, bounds.y, help_text, .{
            .fg = .{ .indexed = 0 }, // Black text
        });
    }

    /// Render help screen
    fn renderHelp(self: *DemoApp, bounds: Bounds) !void {
        const help_content =
            \\ScrollableTextArea Demo - Help
            \\
            \\MODES:
            \\  1 - View Mode (read-only text viewing)
            \\  2 - Edit Mode (editable text)
            \\  3 - Search Mode (search demonstration)
            \\  4 - Syntax Mode (syntax highlighting demo)
            \\
            \\SAMPLE TEXTS:
            \\  l - Load Lorem Ipsum
            \\  c - Load Code Sample
            \\  L - Load Large Text
            \\
            \\OPTIONS:
            \\  w - Toggle word wrap (None/Word/Character)
            \\  n - Toggle line numbers
            \\
            \\NAVIGATION:
            \\  Arrow Keys - Move cursor
            \\  Page Up/Down - Scroll by page
            \\  Home/End - Go to line start/end
            \\  Mouse Wheel - Scroll
            \\  Mouse Click - Position cursor
            \\
            \\EDITING (Edit Mode only):
            \\  Type - Insert text
            \\  Backspace - Delete character
            \\  Delete - Delete character forward
            \\
            \\SEARCH (Search Mode):
            \\  / - Start search (not implemented in demo)
            \\  n - Next match
            \\  p - Previous match
            \\
            \\OTHER:
            \\  h - Toggle this help
            \\  q - Quit demo
            \\
            \\Press ESC or h to close help
        ;

        // Create a text area for help content
        var help_area = try ScrollableTextArea.init(self.allocator, .{
            .show_line_numbers = false,
            .word_wrap = .word,
            .read_only = true,
            .show_scrollbars = true,
            .highlight_current_line = false,
        });
        defer help_area.deinit();

        try help_area.setText(help_content);
        try help_area.render(self.renderer, bounds);
    }
};

/// Create Lorem Ipsum sample text
fn createLoremIpsum(allocator: Allocator) ![]const u8 {
    const lorem = @embedFile("../README.md");
    return allocator.dupe(u8, lorem);
}

/// Create code sample text
fn createCodeSample(allocator: Allocator) ![]const u8 {
    const code =
        \\// Example Zig code with syntax highlighting
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\
        \\    // Create a HashMap
        \\    var map = std.StringHashMap([]const u8).init(allocator);
        \\    defer map.deinit();
        \\
        \\    // Add some entries
        \\    try map.put("hello", "world");
        \\    try map.put("foo", "bar");
        \\    try map.put("zig", "rocks");
        \\
        \\    // Iterate and print
        \\    var it = map.iterator();
        \\    while (it.next()) |entry| {
        \\        std.debug.print("{s} => {s}\\n", .{
        \\            entry.key_ptr.*,
        \\            entry.value_ptr.*,
        \\        });
        \\    }
        \\}
        \\
        \\// Function with complex logic
        \\fn processData(data: []const u8, config: Config) !Result {
        \\    if (data.len == 0) return error.EmptyData;
        \\
        \\    var result = Result{ .items = try allocator.alloc(Item, 0) };
        \\    errdefer allocator.free(result.items);
        \\
        \\    var lines = std.mem.split(u8, data, "\\n");
        \\    while (lines.next()) |line| {
        \\        if (std.mem.trim(u8, line, " ").len == 0) continue;
        \\
        \\        const item = try parseLine(line, config);
        \\        result.items = try allocator.realloc(result.items, result.items.len + 1);
        \\        result.items[result.items.len - 1] = item;
        \\    }
        \\
        \\    return result;
        \\}
        \\
        \\// Struct definitions
        \\const Config = struct {
        \\    max_items: usize = 1000,
        \\    trim_whitespace: bool = true,
        \\    validate_input: bool = false,
        \\};
        \\
        \\const Result = struct {
        \\    items: []Item,
        \\    processing_time_ms: u64 = 0,
        \\};
        \\
        \\const Item = struct {
        \\    name: []const u8,
        \\    value: f64,
        \\    metadata: std.StringHashMap([]const u8),
        \\};
    ;

    return allocator.dupe(u8, code);
}

/// Create large text sample
fn createLargeText(allocator: Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const words = [_][]const u8{
        "lorem",      "ipsum",   "dolor",        "sit",     "amet",    "consectetur",
        "adipiscing", "elit",    "sed",          "do",      "eiusmod", "tempor",
        "incididunt", "ut",      "labore",       "et",      "dolore",  "magna",
        "aliqua",     "ut",      "enim",         "ad",      "minim",   "veniam",
        "quis",       "nostrud", "exercitation", "ullamco", "laboris", "nisi",
        "ut",         "aliquip", "ex",           "ea",      "commodo", "consequat",
    };

    var prng = std.rand.DefaultPrng.init(12345);
    const random = prng.random();

    // Generate ~1000 lines of text
    var line_count: usize = 0;
    while (line_count < 1000) {
        const words_in_line = random.intRangeAtMost(usize, 5, 15);

        var word_idx: usize = 0;
        while (word_idx < words_in_line) {
            if (word_idx > 0) try buffer.append(' ');
            const word = words[random.intRangeAtMost(usize, 0, words.len - 1)];
            try buffer.appendSlice(word);
            word_idx += 1;
        }

        try buffer.append('\n');
        line_count += 1;
    }

    return buffer.toOwnedSlice();
}

/// Simple syntax highlighting callback for demo
fn syntaxHighlightCallback(
    line: []const u8,
    line_index: usize,
    user_data: ?*anyopaque,
) []const ScrollableTextArea.SyntaxToken {
    _ = line;
    _ = line_index;
    _ = user_data;

    // For demo purposes, return empty slice
    // In a real implementation, you would parse the line and return syntax tokens
    return &[_]ScrollableTextArea.SyntaxToken{};
}

/// Main demo function
pub fn runDemo(allocator: Allocator) !void {
    // Create renderer
    var renderer = try renderer_mod.createRenderer(allocator);
    defer renderer.deinit();

    // Create demo app
    var app = try DemoApp.init(allocator, &renderer);
    defer app.deinit();

    // Get terminal size
    const term_size = try renderer.getCapabilities().getSize();

    // Main loop
    var running = true;
    while (running) {
        // Handle input
        // Note: In a real application, you would get input from the terminal
        // For this demo, we'll simulate some input events

        // Render
        const bounds = Bounds{
            .x = 0,
            .y = 0,
            .width = @intCast(term_size.width),
            .height = @intCast(term_size.height),
        };

        try app.render(bounds);

        // In a real app, you would wait for input here
        // For demo purposes, we'll just show the initial state
        running = false;
    }
}

/// Demo entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runDemo(allocator);
}

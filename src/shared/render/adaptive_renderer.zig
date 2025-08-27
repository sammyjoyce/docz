const std = @import("std");
const unified = @import("term_shared").unified;
const caps = @import("term_shared").caps;
const graphics_manager = @import("term_shared").graphics_manager;
const Color = @import("term_shared").ansi.color.Color;

/// Adaptive renderer that optimizes visual output based on terminal capabilities
pub const AdaptiveRenderer = struct {
    allocator: std.mem.Allocator,
    capabilities: caps.TermCaps,
    render_mode: RenderMode,
    graphics_manager: ?*graphics_manager.GraphicsManager,
    cache: RenderCache,
    terminal: *unified.Terminal,

    pub const RenderMode = enum {
        /// Full graphics, true color, synchronized output, advanced features
        enhanced,
        /// 256 colors, Unicode blocks, basic mouse, good compatibility
        standard,
        /// 16 colors, ASCII art, no advanced features, wide compatibility
        compatible,
        /// Plain text only, maximum compatibility
        minimal,

        pub fn fromCapabilities(cap: caps.TermCaps) RenderMode {
            if ((cap.supportsKittyGraphics or cap.supportsSixel) and cap.supportsTruecolor) {
                return .enhanced;
            } else if (cap.supportsTruecolor) {
                return .standard;
            } else {
                return .compatible;
            }
        }

        pub fn description(self: RenderMode) []const u8 {
            return switch (self) {
                .enhanced => "Enhanced (Graphics, True Color, Animations)",
                .standard => "Standard (256 Colors, Unicode Blocks)",
                .compatible => "Compatible (16 Colors, ASCII Art)",
                .minimal => "Minimal (Plain Text Only)",
            };
        }
    };

    /// Cache for rendered content to avoid recomputation
    pub const RenderCache = struct {
        allocator: std.mem.Allocator,
        entries: std.HashMap(u64, CacheEntry, std.HashMap.DefaultContext(u64), 80),

        const CacheEntry = struct {
            content: []u8,
            timestamp: i64,
            render_mode: RenderMode,
        };

        pub fn init(allocator: std.mem.Allocator) RenderCache {
            return RenderCache{
                .allocator = allocator,
                .entries = std.HashMap(u64, CacheEntry, std.HashMap.DefaultContext(u64), 80).init(allocator),
            };
        }

        pub fn deinit(self: *RenderCache) void {
            var iterator = self.entries.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.value_ptr.content);
            }
            self.entries.deinit();
        }

        pub fn get(self: *const RenderCache, key: u64, render_mode: RenderMode) ?[]const u8 {
            const entry = self.entries.get(key) orelse return null;
            if (entry.render_mode != render_mode) return null;
            return entry.content;
        }

        pub fn put(self: *RenderCache, key: u64, content: []const u8, render_mode: RenderMode) !void {
            const now = std.time.milliTimestamp();
            const owned_content = try self.allocator.dupe(u8, content);

            const result = try self.entries.getOrPut(key);
            if (result.found_existing) {
                self.allocator.free(result.value_ptr.content);
            }

            result.value_ptr.* = CacheEntry{
                .content = owned_content,
                .timestamp = now,
                .render_mode = render_mode,
            };
        }
    };

    /// Initialize adaptive renderer with automatic capability detection
    pub fn init(allocator: std.mem.Allocator) !*AdaptiveRenderer {
        const terminal = try allocator.create(unified.Terminal);
        terminal.* = try unified.Terminal.init(allocator);
        const capabilities = terminal.getCapabilities();
        const render_mode = RenderMode.fromCapabilities(capabilities);

        const renderer = try allocator.create(AdaptiveRenderer);
        renderer.* = AdaptiveRenderer{
            .allocator = allocator,
            .capabilities = capabilities,
            .render_mode = render_mode,
            .graphics_manager = null, // Simplified - no graphics manager for now
            .cache = RenderCache.init(allocator),
            .terminal = terminal,
        };

        return renderer;
    }

    /// Initialize with explicit render mode (for testing or forced modes)
    pub fn initWithMode(allocator: std.mem.Allocator, mode: RenderMode) !*AdaptiveRenderer {
        const terminal = try allocator.create(unified.Terminal);
        terminal.* = try unified.Terminal.init(allocator);
        const capabilities = terminal.getCapabilities();

        const renderer = try allocator.create(AdaptiveRenderer);
        renderer.* = AdaptiveRenderer{
            .allocator = allocator,
            .capabilities = capabilities,
            .render_mode = mode,
            .graphics_manager = null, // Simplified - no graphics manager for now
            .cache = RenderCache.init(allocator),
            .terminal = terminal,
        };

        return renderer;
    }

    pub fn deinit(self: *AdaptiveRenderer) void {
        if (self.graphics_manager) |gm| {
            gm.deinit();
            self.allocator.destroy(gm);
        }
        self.cache.deinit();
        self.terminal.deinit();
        self.allocator.destroy(self.terminal);
        self.allocator.destroy(self);
    }

    /// Get current terminal dimensions
    pub fn getSize(self: *const AdaptiveRenderer) !struct { width: u16, height: u16 } {
        return try self.terminal.getTerminalSize();
    }

    /// Clear screen with proper handling for all render modes
    pub fn clearScreen(self: *AdaptiveRenderer) !void {
        try self.terminal.clearScreen();
    }

    /// Move cursor to position (0-based coordinates)
    pub fn moveCursor(self: *AdaptiveRenderer, x: u16, y: u16) !void {
        try self.terminal.moveCursor(x, y);
    }

    /// Write text with optional color and style
    pub fn writeText(self: *AdaptiveRenderer, text: []const u8, color: ?Color, bold: bool) !void {
        if (color) |c| {
            try self.terminal.setForegroundColor(c);
        }

        if (bold and self.render_mode != .minimal) {
            try self.terminal.setBold(true);
        }

        try self.terminal.writeText(text);

        if (bold and self.render_mode != .minimal) {
            try self.terminal.setBold(false);
        }

        if (color != null) {
            try self.terminal.resetColor();
        }
    }

    /// Start synchronized output for flicker-free updates (if supported)
    pub fn beginSynchronized(self: *AdaptiveRenderer) !void {
        if (self.render_mode == .enhanced and self.capabilities.supportsSynchronizedOutput()) {
            try self.terminal.beginSynchronizedOutput();
        }
    }

    /// End synchronized output
    pub fn endSynchronized(self: *AdaptiveRenderer) !void {
        if (self.render_mode == .enhanced and self.capabilities.supportsSynchronizedOutput()) {
            try self.terminal.endSynchronizedOutput();
        }
    }

    /// Flush output buffer
    pub fn flush(self: *AdaptiveRenderer) !void {
        try self.terminal.flush();
    }

    /// Get information about current rendering capabilities
    pub fn getRenderingInfo(self: *const AdaptiveRenderer) Rendering {
        return Rendering{
            .mode = self.render_mode,
            .supports_truecolor = self.capabilities.supportsTruecolor,
            .supports_256_color = self.capabilities.supportsTruecolor, // Use truecolor as proxy for 256 color
            .supports_unicode = true, // Assume unicode support for modern terminals
            .supports_graphics = self.capabilities.supportsKittyGraphics or self.capabilities.supportsSixel,
            .supports_mouse = self.capabilities.supportsSgrMouse,
            .supports_synchronized = false, // Not directly available in TermCaps
            .terminal_name = "detected", // Would need to be detected separately
        };
    }

    pub const Rendering = struct {
        mode: RenderMode,
        supports_truecolor: bool,
        supports_256_color: bool,
        supports_unicode: bool,
        supports_graphics: bool,
        supports_mouse: bool,
        supports_synchronized: bool,
        terminal_name: []const u8,

        pub fn print(self: Rendering, writer: anytype) !void {
            try writer.print("Rendering Mode: {s}\n", .{self.mode.description()});
            try writer.print("Terminal: {s}\n", .{self.terminal_name});
            try writer.print("Features:\n");
            try writer.print("  True Color: {any}\n", .{self.supports_truecolor});
            try writer.print("  256 Colors: {any}\n", .{self.supports_256_color});
            try writer.print("  Unicode: {any}\n", .{self.supports_unicode});
            try writer.print("  Graphics: {any}\n", .{self.supports_graphics});
            try writer.print("  Mouse: {any}\n", .{self.supports_mouse});
            try writer.print("  Synchronized: {any}\n", .{self.supports_synchronized});
        }
    };
};

/// Generate cache key for content
pub fn cacheKey(comptime fmt: []const u8, args: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0);
    const content = std.fmt.allocPrint(std.heap.page_allocator, fmt, args) catch return 0;
    defer std.heap.page_allocator.free(content);
    hasher.update(content);
    return hasher.final();
}

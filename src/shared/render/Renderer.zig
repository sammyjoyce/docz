//! Unified Adaptive Renderer System
//!
//! This module provides a single, unified interface for all rendering needs
//! in the terminal UI system. It uses a strategy pattern to adapt rendering
//! based on terminal capabilities and provides progressive enhancement.
//!
//! The renderer consolidates functionality from:
//! - AdaptiveRenderer (text rendering with capability detection)
//! - UnifiedRenderer (widget-based TUI rendering)
//! - Graphics Renderer (advanced graphics rendering)

const std = @import("std");
const term_mod = @import("../term/mod.zig");
const unified_terminal = @import("../cli/core/unified_terminal.zig");
const graphics_manager = @import("../term/graphics_manager.zig");
const canvas_engine = @import("../core/canvas_engine.zig");

const Allocator = std.mem.Allocator;
const UnifiedTerminal = unified_terminal.UnifiedTerminal;
const Color = unified_terminal.Color;
const GraphicsManager = graphics_manager.GraphicsManager;

/// Unified renderer that adapts to terminal capabilities and provides
/// progressive enhancement for all rendering needs
pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: UnifiedTerminal,
    capabilities: term_mod.caps.TermCaps,
    render_tier: RenderTier,
    graphics_manager: ?*GraphicsManager,
    cache: RenderCache,
    theme: Theme,

    /// Rendering tier based on terminal capabilities
    pub const RenderTier = enum {
        /// Full graphics, true color, animations, advanced features
        ultra,
        /// 256 colors, Unicode blocks, basic graphics
        enhanced,
        /// 16 colors, Unicode characters, standard features
        standard,
        /// Plain text only, maximum compatibility
        minimal,

        pub fn fromCapabilities(cap: term_mod.caps.TermCaps) RenderTier {
            if ((cap.supportsKittyGraphics or cap.supportsSixel) and cap.supportsTruecolor) {
                return .ultra;
            } else if (cap.supportsTruecolor) {
                return .enhanced;
            } else if (cap.supportsUnicode) {
                return .standard;
            } else {
                return .minimal;
            }
        }

        pub fn description(self: RenderTier) []const u8 {
            return switch (self) {
                .ultra => "Ultra (Graphics, True Color, Animations)",
                .enhanced => "Enhanced (256 Colors, Unicode Blocks)",
                .standard => "Standard (16 Colors, Unicode)",
                .minimal => "Minimal (Plain Text Only)",
            };
        }
    };

    /// Cache for rendered content to avoid recomputation
    pub const RenderCache = struct {
        allocator: Allocator,
        entries: std.HashMap(u64, CacheEntry, std.HashMap.DefaultContext(u64), 80),

        const CacheEntry = struct {
            content: []u8,
            timestamp: i64,
            render_tier: RenderTier,
        };

        pub fn init(allocator: Allocator) RenderCache {
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

        pub fn get(self: *const RenderCache, key: u64, render_tier: RenderTier) ?[]const u8 {
            const entry = self.entries.get(key) orelse return null;
            if (entry.render_tier != render_tier) return null;
            return entry.content;
        }

        pub fn put(self: *RenderCache, key: u64, content: []const u8, render_tier: RenderTier) !void {
            const now = std.time.milliTimestamp();
            const owned_content = try self.allocator.dupe(u8, content);

            const result = try self.entries.getOrPut(key);
            if (result.found_existing) {
                self.allocator.free(result.value_ptr.content);
            }

            result.value_ptr.* = CacheEntry{
                .content = owned_content,
                .timestamp = now,
                .render_tier = render_tier,
            };
        }
    };

    /// Theme system for consistent styling
    pub const Theme = struct {
        // Basic colors
        background: Color,
        foreground: Color,
        accent: Color,

        // State colors
        focused: Color,
        selected: Color,
        disabled: Color,

        // Status colors
        success: Color,
        warning: Color,
        danger: Color,

        pub fn defaultLight() Theme {
            return Theme{
                .background = Color.WHITE,
                .foreground = Color.BLACK,
                .accent = Color.BLUE,
                .focused = Color.CYAN,
                .selected = Color.YELLOW,
                .disabled = Color.GRAY,
                .success = Color.GREEN,
                .warning = Color.ORANGE,
                .danger = Color.RED,
            };
        }

        pub fn defaultDark() Theme {
            return Theme{
                .background = Color.BLACK,
                .foreground = Color.WHITE,
                .accent = Color.CYAN,
                .focused = Color.BLUE,
                .selected = Color.PURPLE,
                .disabled = Color.GRAY,
                .success = Color.GREEN,
                .warning = Color.ORANGE,
                .danger = Color.RED,
            };
        }
    };

    /// Initialize renderer with automatic capability detection
    pub fn init(allocator: Allocator) !*Renderer {
        const terminal = try UnifiedTerminal.init(allocator);
        const capabilities = terminal.getCapabilities();
        const render_tier = RenderTier.fromCapabilities(capabilities);

        const renderer = try allocator.create(Renderer);
        renderer.* = Renderer{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_tier = render_tier,
            .graphics_manager = null, // Initialize on demand
            .cache = RenderCache.init(allocator),
            .theme = Theme.defaultDark(),
        };

        return renderer;
    }

    /// Initialize with explicit render tier (for testing or forced modes)
    pub fn initWithTier(allocator: Allocator, tier: RenderTier) !*Renderer {
        const terminal = try UnifiedTerminal.init(allocator);
        const capabilities = terminal.getCapabilities();

        const renderer = try allocator.create(Renderer);
        renderer.* = Renderer{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_tier = tier,
            .graphics_manager = null,
            .cache = RenderCache.init(allocator),
            .theme = Theme.defaultDark(),
        };

        return renderer;
    }

    /// Initialize with custom theme
    pub fn initWithTheme(allocator: Allocator, theme: Theme) !*Renderer {
        const terminal = try UnifiedTerminal.init(allocator);
        const capabilities = terminal.getCapabilities();
        const render_tier = RenderTier.fromCapabilities(capabilities);

        const renderer = try allocator.create(Renderer);
        renderer.* = Renderer{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_tier = render_tier,
            .graphics_manager = null,
            .cache = RenderCache.init(allocator),
            .theme = theme,
        };

        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        if (self.graphics_manager) |gm| {
            gm.deinit();
            self.allocator.destroy(gm);
        }
        self.cache.deinit();
        self.terminal.deinit();
        self.allocator.destroy(self);
    }

    /// Get current terminal dimensions
    pub fn getSize(self: *const Renderer) !struct { width: u16, height: u16 } {
        return try self.terminal.getTerminalSize();
    }

    /// Clear screen with proper handling for all render tiers
    pub fn clearScreen(self: *Renderer) !void {
        try self.terminal.clearScreen();
    }

    /// Move cursor to position (0-based coordinates)
    pub fn moveCursor(self: *Renderer, x: u16, y: u16) !void {
        try self.terminal.moveCursor(x, y);
    }

    /// Write text with optional color and style
    pub fn writeText(self: *Renderer, text: []const u8, color: ?Color, bold: bool) !void {
        if (color) |c| {
            try self.terminal.setForegroundColor(c);
        }

        if (bold and self.render_tier != .minimal) {
            try self.terminal.setBold(true);
        }

        try self.terminal.writeText(text);

        if (bold and self.render_tier != .minimal) {
            try self.terminal.setBold(false);
        }

        if (color != null) {
            try self.terminal.resetColor();
        }
    }

    /// Start synchronized output for flicker-free updates (if supported)
    pub fn beginSynchronized(self: *Renderer) !void {
        if (self.render_tier == .ultra and self.capabilities.supportsSynchronizedOutput()) {
            try self.terminal.beginSynchronizedOutput();
        }
    }

    /// End synchronized output
    pub fn endSynchronized(self: *Renderer) !void {
        if (self.render_tier == .ultra and self.capabilities.supportsSynchronizedOutput()) {
            try self.terminal.endSynchronizedOutput();
        }
    }

    /// Flush output buffer
    pub fn flush(self: *Renderer) !void {
        try self.terminal.flush();
    }

    /// Get information about current rendering capabilities
    pub fn getRenderingInfo(self: *const Renderer) RenderingInfo {
        return RenderingInfo{
            .tier = self.render_tier,
            .supports_truecolor = self.capabilities.supportsTruecolor,
            .supports_256_color = self.capabilities.supportsTruecolor, // Use truecolor as proxy for 256 color
            .supports_unicode = self.capabilities.supportsUnicode,
            .supports_graphics = self.capabilities.supportsKittyGraphics or self.capabilities.supportsSixel,
            .supports_mouse = self.capabilities.supportsSgrMouse,
            .supports_synchronized = self.capabilities.supportsSynchronizedOutput(),
            .terminal_name = "detected", // Would need to be detected separately
        };
    }

    pub const RenderingInfo = struct {
        tier: RenderTier,
        supports_truecolor: bool,
        supports_256_color: bool,
        supports_unicode: bool,
        supports_graphics: bool,
        supports_mouse: bool,
        supports_synchronized: bool,
        terminal_name: []const u8,

        pub fn print(self: RenderingInfo, writer: anytype) !void {
            try writer.print("Rendering Tier: {s}\n", .{self.tier.description()});
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

    /// Get or create graphics manager for advanced rendering
    pub fn getGraphicsManager(self: *Renderer) !*GraphicsManager {
        if (self.graphics_manager) |gm| {
            return gm;
        }

        const gm = try self.allocator.create(GraphicsManager);
        gm.* = try GraphicsManager.init(self.allocator);
        self.graphics_manager = gm;
        return gm;
    }

    /// Set current theme
    pub fn setTheme(self: *Renderer, theme: Theme) void {
        self.theme = theme;
    }

    /// Get current theme
    pub fn getTheme(self: *const Renderer) Theme {
        return self.theme;
    }

    /// Get terminal for direct access (for advanced use cases)
    pub fn getTerminal(self: *Renderer) *UnifiedTerminal {
        return &self.terminal;
    }

    /// Get cache for direct access (for advanced caching)
    pub fn getCache(self: *Renderer) *RenderCache {
        return &self.cache;
    }

    /// Generate cache key for content
    pub fn cacheKey(comptime fmt: []const u8, args: anytype) u64 {
        var hasher = std.hash.Wyhash.init(0);
        const content = std.fmt.allocPrint(std.heap.page_allocator, fmt, args) catch return 0;
        defer std.heap.page_allocator.free(content);
        hasher.update(content);
        return hasher.final();
    }
};

/// Generate cache key for content (standalone function)
pub fn cacheKey(comptime fmt: []const u8, args: anytype) u64 {
    return Renderer.cacheKey(fmt, args);
}
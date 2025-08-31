//! Rendering System
//!
//! This module provides a comprehensive rendering system that automatically
//! optimizes visual output based on detected terminal capabilities. It implements
//! progressive enhancement to provide the best possible experience across all terminals.
//!
//! ## Features
//!
//! - **Automatic Capability Detection**: Detects terminal features and selects optimal rendering mode
//! - **Progressive Enhancement**: Four quality tiers from minimal to rich
//! - **Component-Based Architecture**: Modular, reusable rendering components
//! - **Caching System**: Efficient caching to avoid recomputation
//! - **Comprehensive Coverage**: Progress bars, tables, charts, and more
//!
//! ## Quick Start
//!
//! ```zig
//! const Renderer = @import("render/mod.zig").Renderer;
//! const Progress = @import("render/mod.zig").Progress;
//!
//! // Initialize with automatic capability detection
//! const renderer = try Renderer.init(allocator);
//! defer renderer.deinit();
//!
//! // Render a progress bar - automatically adapts to terminal capabilities
//! const progress = Progress{
//!     .value = 0.75,
//!     .label = "Processing",
//!     .percentage = true,
//!     .color = Color.ansi(.green),
//! };
//! try renderer.renderProgress(progress);
//! ```
//!
//! ## Render Modes
//!
//! - **Rich**: Full graphics, true color, animations, synchronized output
//! - **Standard**: 256 colors, Unicode blocks, good compatibility
//! - **Compatible**: 16 colors, ASCII art, wide compatibility
//! - **Minimal**: Plain text only, maximum compatibility
//!
//! ## Architecture
//!
//! The system is built around the `Renderer` core that:
//! 1. Detects terminal capabilities using the `caps` module
//! 2. Selects appropriate render mode based on capabilities
//! 3. Routes rendering calls to mode-specific implementations
//! 4. Provides caching for performance optimization
//! 5. Handles color adaptation and fallbacks
//!
//! ## Compile-time Options
//! Override render behavior at build root by defining:
//!
//!   pub const render_options = RenderOptions{ .quality = .high };
//!
//! Or provide render-specific toggles by adding fields (your `shared_options`
//! struct can be any type; fields are discovered with `@hasField`):
//!   - `render_enable_braille: bool`
//!   - `render_enable_canvas: bool`
//!   - `render_enable_diff: bool`
//!   - `render_default_tier: @This().RenderTier`
//! This module will read them via `@hasDecl(root, "shared_options")`.
//!

const deps = @import("internal/deps.zig");
comptime {
    deps.assertLayer(.render);
}
// Feature gating handled by build system
const std = @import("std");
const root = @import("root");

// -----------------------------------------------------------------------------
// Compile-time Options for render submodule
// -----------------------------------------------------------------------------
/// Render-level feature flags and defaults. You can override these by setting
/// fields on `root.shared_options` (preferred) or by copying this struct at
/// your own barrel and using it to gate features with `comptime` checks.
pub const Options = struct {
    enable_braille: bool = true,
    enable_canvas: bool = true,
    enable_diff: bool = true,
    default_tier: ?RenderTier = null, // if set, forces a tier for tests/demos
};

/// Resolved render options using `root.shared_options` when available.
pub const options: Options = blk: {
    const defaults = Options{};
    if (@hasDecl(root, "shared_options")) {
        const T = @TypeOf(root.shared_options);
        break :blk Options{
            .enable_braille = if (@hasField(T, "render_enable_braille")) @field(root.shared_options, "render_enable_braille") else defaults.enable_braille,
            .enable_canvas = if (@hasField(T, "render_enable_canvas")) @field(root.shared_options, "render_enable_canvas") else defaults.enable_canvas,
            .enable_diff = if (@hasField(T, "render_enable_diff")) @field(root.shared_options, "render_enable_diff") else defaults.enable_diff,
            .default_tier = if (@hasField(T, "render_default_tier")) @field(root.shared_options, "render_default_tier") else defaults.default_tier,
        };
    }
    break :blk defaults;
};
const term_mod = @import("term.zig");
pub const Painter = @import("render/painter.zig").Painter;
pub const Surface = @import("render/surface.zig").Surface;
pub const MemorySurface = @import("render/surface.zig").MemorySurface;
pub const TermSurface = @import("render/surface.zig").TermSurface;

// Core exports - Renderer System
pub const Renderer = @import("render/renderer.zig").Renderer;
pub const RenderTier = Renderer.RenderTier;
pub const RenderContext = @import("render/RenderContext.zig");
pub const Theme = Renderer.Theme;
pub const cacheKey = Renderer.cacheKey;
pub const QualityTiers = @import("render/quality_tiers.zig").QualityTiers;
pub const ProgressConfig = @import("render/quality_tiers.zig").ProgressConfig;
pub const TableConfig = @import("render/quality_tiers.zig").TableConfig;
pub const ChartConfig = @import("render/quality_tiers.zig").ChartConfig;

// Widget system exports
pub const Widget = Renderer.Widget;
pub const WidgetVTable = Renderer.WidgetVTable;
pub const WidgetBuilder = Renderer.WidgetBuilder;
pub const Container = Renderer.Container;
pub const InputEvent = Renderer.InputEvent;
pub const Style = Renderer.Style;
pub const Bounds = Renderer.Bounds;
pub const Point = Renderer.Point;
pub const Size = Renderer.Size;
pub const Rect = Renderer.Rect;
pub const Render = Renderer.Render;
pub const BoxStyle = Renderer.BoxStyle;
pub const Constraints = Renderer.Constraints;
pub const Layout = Renderer.Layout;

// Graphics system
pub const Graphics = term_mod.graphics.Graphics;

// Diff rendering module
pub const diff = @import("render/diff.zig");
pub const diffSurface = @import("render/diff_surface.zig");
pub const DiffSpan = diffSurface.Span;
pub const diffCoalesce = @import("render/diff_coalesce.zig");
pub const DiffRect = diffCoalesce.Rect;
pub const coalesceSpansToRects = diffCoalesce.coalesceSpansToRects;
pub const Memory = @import("render/memory.zig").Memory;
pub const Terminal = @import("render/terminal.zig").Terminal;

// Legacy compatibility aliases
// Legacy aliases removed per 2025-08-31 policy: use Memory/Terminal directly

// Braille graphics module
pub const braille = @import("render/braille.zig");
pub const BrailleCanvas = braille.BrailleCanvas;
pub const BraillePatterns = braille.BraillePatterns;
pub const Braille = braille.Braille;

// Multi-resolution canvas module
pub const canvas = @import("render/canvas.zig");
pub const Canvas = canvas.Canvas;
pub const ResolutionMode = canvas.ResolutionMode;
pub const CanvasPoint = canvas.Point;
pub const CanvasRect = canvas.Rect;
pub const CanvasStyle = canvas.Style;
pub const LineStyle = canvas.LineStyle;
pub const FillPattern = canvas.FillPattern;

// Progress exports (legacy adapter retained)
const shared_components = @import("components_shared");
pub const Progress = shared_components.Progress;
pub const renderProgress = shared_components.progress.renderProgress;
pub const AnimatedProgress = shared_components.AnimatedProgress;

// Widget namespace for render/widgets/* implementations
pub const widgets = struct {
    pub const Progress = @import("render/widgets/Progress.zig");
    pub const Input = @import("render/widgets/Input.zig");
    pub const Notification = @import("render/widgets/Notification.zig");
    pub const Chart = @import("render/widgets/Chart.zig");
    pub const Table = @import("render/widgets/Table.zig");
};

// Note: Markdown/syntax renderers have been moved under render/legacy
// and are only included when built with -Dlegacy.

// Demo and utilities: see `examples/cli_demo/` for runnable demos.

/// Convenience function to create a renderer with automatic capability detection
pub fn createRenderer(allocator: std.mem.Allocator) !*Renderer {
    return Renderer.init(allocator);
}

/// Convenience function to create a renderer with explicit tier (for testing)
pub fn createRendererWithTier(allocator: std.mem.Allocator, tier: RenderTier) !*Renderer {
    return Renderer.initWithTier(allocator, tier);
}

/// Convenience function to create a renderer with custom theme
pub fn createRendererWithTheme(allocator: std.mem.Allocator, theme: Theme) !*Renderer {
    return Renderer.initWithTheme(allocator, theme);
}

// Backward-compatibility helpers removed; prefer Renderer.init*/factory APIs

// Legacy convenience API moved to render/legacy (enabled via -Dlegacy).

// Legacy dashboard helpers removed. See render/legacy/ for shims.

// Tests
test "rendering system" {
    const testing = std.testing;

    // Test core renderer creation
    var renderer = try createRendererWithTier(testing.allocator, .minimal);
    defer renderer.deinit();

    const info = renderer.getCapabilities();
    try testing.expect(info.tier == .minimal);

    // Legacy RendererAPI covered in render.legacy tests when enabled.
}

// -----------------------------------------------------------------------------
// Backend Factory (Duck-typed)
// -----------------------------------------------------------------------------
/// Create a renderer backend binding using duck-typed polymorphism.
///
/// Pass any `Backend` type that exposes the following declarations. No formal
/// interface is required; compile-time checks verify presence only:
///  - `beginFrame(self: *Backend, width: u16, height: u16) !void`
///  - `endFrame(self: *Backend) !void`
///  - `drawText(self: *Backend, x: i16, y: i16, text: []const u8, style: Style) !void`
///  - `measureText(self: *Backend, text: []const u8, style: Style) !Point`
///  - `moveCursor(self: *Backend, x: u16, y: u16) !void`
///  - `fillRect(self: *Backend, ctx: Render, color: Style.Color) !void`
///  - `flush(self: *Backend) !void`
/// Optional (if present, they will be re-exported):
///  - `drawBox(self: *Backend, ctx: Render, box: BoxStyle) !void`
///  - `drawLine(self: *Backend, ctx: Render, from: Point, to: Point) !void`
///
/// Example:
///   const R = @import("render/mod.zig");
///   const My = struct {
///       pub fn beginFrame(self: *My, w: u16, h: u16) !void { _ = self; _ = w; _ = h; }
///       pub fn endFrame(self: *My) !void { _ = self; }
///       pub fn drawText(self: *My, x: i16, y: i16, t: []const u8, s: R.Style) !void { _ = self; _ = x; _ = y; _ = t; _ = s; }
///       pub fn measureText(self: *My, t: []const u8, s: R.Style) !R.Point { _ = self; _ = s; return .{ .x = @intCast(t.len), .y = 1 }; }
///       pub fn moveCursor(self: *My, x: u16, y: u16) !void { _ = self; _ = x; _ = y; }
///       pub fn fillRect(self: *My, ctx: R.Render, c: R.Style.Color) !void { _ = self; _ = ctx; _ = c; }
///       pub fn flush(self: *My) !void { _ = self; }
///   };
///   const API = R.useBackend(My);
///   var backend = My{};
///   try API.beginFrame(&backend, 80, 24);
pub fn useBackend(comptime Backend: type) type {
    comptime {
        for (.{ "beginFrame", "endFrame", "drawText", "measureText", "moveCursor", "fillRect", "flush" }) |name| {
            if (!@hasDecl(Backend, name)) @compileError("renderer backend missing required decl '" ++ name ++ "'");
        }
    }

    return struct {
        pub const Style = Renderer.Style;
        pub const Render = Renderer.Render;
        pub const BoxStyle = Renderer.BoxStyle;
        pub const Point = Renderer.Point;

        // Re-export backend fns; this preserves signatures without constraining them.
        pub const beginFrame = Backend.beginFrame;
        pub const endFrame = Backend.endFrame;
        pub const drawText = Backend.drawText;
        pub const measureText = Backend.measureText;
        pub const moveCursor = Backend.moveCursor;
        pub const fillRect = Backend.fillRect;
        pub const flush = Backend.flush;

        // Optionals
        pub const drawBox = if (@hasDecl(Backend, "drawBox")) Backend.drawBox else struct {};
        pub const drawLine = if (@hasDecl(Backend, "drawLine")) Backend.drawLine else struct {};
    };
}

//! CLI Adapter for Unified Progress Bar Component
//! 
//! This adapter wraps the unified progress bar component to provide compatibility
//! with existing CLI code while leveraging the enhanced capabilities.

const std = @import("std");
const unified_progress = @import("../../ui/components/progress_bar.zig");
const component_mod = @import("../../ui/component.zig");
const unified_term = @import("../../term/unified.zig");

// Type aliases for compatibility
pub const ProgressBarStyle = enum {
    simple,
    unicode,
    gradient,
    animated,
    rainbow,
    
    fn toUnified(self: ProgressBarStyle) unified_progress.ProgressBarStyle {
        return switch (self) {
            .simple => .ascii,
            .unicode => .unicode_blocks,
            .gradient => .gradient,
            .animated => .animated,
            .rainbow => .rainbow,
        };
    }
};

/// CLI-compatible progress bar that wraps the unified component
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    component: *component_mod.Component,
    impl: *unified_progress.ProgressBar,
    
    // CLI-specific mock render context
    mock_terminal: *MockTerminal,
    mock_context: component_mod.RenderContext,
    
    pub fn init(
        allocator: std.mem.Allocator,
        style: ProgressBarStyle,
        width: u32,
        label: []const u8,
    ) !ProgressBar {
        // Create unified progress bar config
        const config = unified_progress.ProgressBarConfig{
            .style = style.toUnified(),
            .label = if (label.len > 0) label else null,
            .progress = 0.0,
            .show_percentage = true,
            .show_eta = false,
            .animated = (style == .animated or style == .rainbow),
        };
        
        // Create the component
        const component = unified_progress.ProgressBar.create(allocator, config) catch unreachable;
        const impl: *unified_progress.ProgressBar = @ptrCast(@alignCast(component.impl));
        
        // Set up mock terminal and context for CLI rendering  
        const mock_terminal = try allocator.create(MockTerminal);
        mock_terminal.* = MockTerminal.init(allocator);
        const mock_context = component_mod.RenderContext{
            .terminal = &mock_terminal.interface,
            .theme = &defaultCliTheme(),
            .graphics = null,
            .allocator = allocator,
        };
        
        // Set component bounds
        impl.state.bounds = component_mod.Rect{
            .x = 0,
            .y = 0,
            .width = width,
            .height = 1,
        };
        
        return ProgressBar{
            .allocator = allocator,
            .component = component,
            .impl = impl,
            .mock_terminal = mock_terminal,
            .mock_context = mock_context,
        };
    }
    
    pub fn deinit(self: *ProgressBar) void {
        self.mock_terminal.output.deinit();
        self.allocator.destroy(self.mock_terminal);
        self.allocator.destroy(self.component);
    }
    
    pub fn setProgress(self: *ProgressBar, progress: f32) void {
        self.impl.setProgress(progress);
    }
    
    pub fn configure(self: *ProgressBar, show_percentage: bool, show_eta: bool) void {
        self.impl.config.show_percentage = show_percentage;
        self.impl.config.show_eta = show_eta;
        self.impl.state.markDirty();
    }
    
    /// Render to CLI writer using the new Zig 0.15.1 I/O system
    pub fn render(self: *ProgressBar, writer: anytype) !void {
        // Clear previous output buffer
        self.mock_terminal.output.clearAndFree();
        
        // Render to mock terminal buffer
        try self.component.vtable.render(self.component.impl, self.mock_context);
        
        // Write buffered output to the CLI writer
        const output = self.mock_terminal.output.items;
        if (output.len > 0) {
            try writer.writeAll(output);
        }
    }
    
    pub fn clear(self: *ProgressBar, writer: anytype) !void {
        // Calculate total width to clear
        const total_width = self.impl.state.bounds.width + 30; // Extra space for metadata
        
        try writer.writeAll("\r");
        for (0..total_width) |_| {
            try writer.writeAll(" ");
        }
        try writer.writeAll("\r");
    }
    
    // Enhanced methods leveraging unified capabilities
    pub fn updateBytes(self: *ProgressBar, bytes: u64) void {
        self.impl.updateBytes(bytes);
    }
    
    pub fn setLabel(self: *ProgressBar, label: []const u8) void {
        self.impl.setLabel(if (label.len > 0) label else null);
    }
    
    pub fn enableRateDisplay(self: *ProgressBar, enable: bool) void {
        self.impl.config.show_rate = enable;
        self.impl.state.markDirty();
    }
    
    pub fn setAnimationSpeed(self: *ProgressBar, speed: f32) void {
        self.impl.config.animation_speed = speed;
    }
};

/// Mock terminal implementation for CLI rendering
const MockTerminal = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    
    // Required interface for unified terminal
    const interface = unified_term.Terminal{
        .vtable = &vtable,
    };
    
    const vtable = unified_term.Terminal.VTable{
        .getCapabilities = getCapabilities,
        .moveTo = moveTo,
        .print = print,
        .clear = clear,
        .flush = flush,
    };
    
    pub fn init(allocator: std.mem.Allocator) MockTerminal {
        return MockTerminal{
            .allocator = allocator,
            .output = std.ArrayList(u8).init(allocator),
        };
    }
    
    fn getCapabilities(impl: *anyopaque) unified_term.TermCaps {
        _ = impl;
        // Use actual terminal capabilities detection
        const term_caps = @import("../../term/caps.zig");
        return term_caps.detectCapsFromEnv(
            &std.process.getEnvMap(std.heap.page_allocator) catch std.process.EnvMap.init(std.heap.page_allocator)
        );
    }
    
    fn moveTo(impl: *anyopaque, x: i32, y: i32) anyerror!void {
        _ = impl;
        _ = x;
        _ = y;
        // For CLI, cursor positioning is handled by the writer
    }
    
    fn print(impl: *anyopaque, text: []const u8, style: unified_term.Style) anyerror!void {
        const self: *MockTerminal = @ptrCast(@alignCast(impl));
        
        // Convert style to ANSI codes and append to output
        if (style.fg_color) |color| {
            try self.appendColorCode(color, true);
        }
        
        try self.output.appendSlice(text);
        
        // Reset color if we set one
        if (style.fg_color != null) {
            try self.output.appendSlice("\x1b[0m");
        }
    }
    
    fn clear(impl: *anyopaque) anyerror!void {
        const self: *MockTerminal = @ptrCast(@alignCast(impl));
        self.output.clearAndFree();
    }
    
    fn flush(impl: *anyopaque) anyerror!void {
        _ = impl;
        // No-op for mock terminal
    }
    
    fn appendColorCode(self: *MockTerminal, color: unified_term.Color, is_fg: bool) !void {
        switch (color) {
            .rgb => |rgb| {
                const code = if (is_fg) "38" else "48";
                try self.output.writer().print("\x1b[{s};2;{d};{d};{d}m", .{ code, rgb.r, rgb.g, rgb.b });
            },
            .indexed => |idx| {
                const code = if (is_fg) "38" else "48";
                try self.output.writer().print("\x1b[{s};5;{d}m", .{ code, idx });
            },
            .named => |named| {
                // Convert named color to ANSI code
                const code = switch (named) {
                    .black => if (is_fg) "30" else "40",
                    .red => if (is_fg) "31" else "41",
                    .green => if (is_fg) "32" else "42",
                    .yellow => if (is_fg) "33" else "43",
                    .blue => if (is_fg) "34" else "44",
                    .magenta => if (is_fg) "35" else "45",
                    .cyan => if (is_fg) "36" else "46",
                    .white => if (is_fg) "37" else "47",
                };
                try self.output.writer().print("\x1b[{s}m", .{code});
            },
        }
    }
};

/// Default CLI theme configuration
fn defaultCliTheme() component_mod.Theme {
    return component_mod.Theme{
        .colors = component_mod.Theme.Colors{
            .primary = unified_term.Color{ .named = .green },
            .secondary = unified_term.Color{ .named = .blue },
            .background = unified_term.Color{ .named = .black },
            .foreground = unified_term.Color{ .named = .white },
            .accent = unified_term.Color{ .named = .yellow },
        },
        .animation = component_mod.Theme.Animation{
            .enabled = true,
            .duration = 300, // ms
            .easing = .ease_in_out,
        },
    };
}

// Convenience functions for common CLI usage patterns
pub fn createSimple(allocator: std.mem.Allocator, label: []const u8, width: u32) !ProgressBar {
    return ProgressBar.init(allocator, .simple, width, label);
}

pub fn createAnimated(allocator: std.mem.Allocator, label: []const u8, width: u32) !ProgressBar {
    return ProgressBar.init(allocator, .animated, width, label);
}

pub fn createRainbow(allocator: std.mem.Allocator, label: []const u8, width: u32) !ProgressBar {
    return ProgressBar.init(allocator, .rainbow, width, label);
}
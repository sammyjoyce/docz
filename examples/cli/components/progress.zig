//! Progress Component with Full Terminal Feature Integration
//!
//! This component demonstrates comprehensive usage of terminal capabilities including:
//! - Kitty Graphics Protocol for real-time charts
//! - iTerm2 integration (badges, notifications, marks)
//! - System notifications with OSC 9
//! - Shell integration with OSC 133 (FinalTerm)
//! - Advanced clipboard integration with structured data
//! - Real-time data visualization with multiple fallback levels
//! - Smart terminal detection and progressive enhancement

const std = @import("std");

// Core terminal capabilities
const terminal_mod = @import("../../../src/shared/term/terminal_mod.zig");
const caps_mod = @import("../../../src/shared/term/caps.zig");

// Features that were previously unused
// const kitty_proto = @import("../../../src/shared/term/ansi/kitty.zig");
// const iterm2_proto = @import("../../../src/shared/term/ansi/iterm2.zig");
// const finalterm_proto = @import("../../../src/shared/term/ansi/finalterm.zig");
// const notifications = @import("../../../src/shared/term/ansi/notification.zig");
// const shell_integration = @import("../../../src/shared/term/ansi/shell_integration.zig");
// const clipboard = @import("../../../src/shared/term/ansi/clipboard.zig");
// const device_attrs = @import("../../../src/shared/term/ansi/device_attributes.zig");

// Graphics and rendering
const graphics_manager = @import("../../../src/shared/term/graphics_manager.zig");
const image_renderer = @import("../../../src/shared/term/unicode_image_renderer.zig");

const Allocator = std.mem.Allocator;

/// Enhanced progress visualization modes based on terminal capabilities
pub const ProgressMode = enum {
    /// Kitty graphics with real-time charts and animations
    kitty_enhanced,
    /// Sixel graphics with static charts
    sixel_graphics,
    /// iTerm2 integration with badges and notifications
    iterm2_integrated,
    /// FinalTerm with shell integration markers
    finalterm_integrated,
    /// Rich Unicode with animations and gradients
    unicode_rich,
    /// Basic ASCII with color support
    ascii_enhanced,
    /// Plain text fallback
    text_only,
};

/// Data point for progress tracking and visualization
pub const ProgressPoint = struct {
    timestamp: i64,
    progress: f32,
    rate: f32, // Items per second
    eta_seconds: ?i64,
    memory_usage: ?usize,
    custom_data: ?[]const u8,
};

/// Configuration for progress display
pub const ProgressConfig = struct {
    width: u32 = 50,
    height: u32 = 4,
    label: []const u8 = "Progress",
    show_rate: bool = true,
    show_eta: bool = true,
    show_memory: bool = false,
    show_chart: bool = true,
    enable_notifications: bool = true,
    enable_clipboard: bool = true,
    enable_shell_integration: bool = true,
    update_interval_ms: u64 = 100,
    chart_history_size: usize = 100,
    notification_threshold: f32 = 0.25, // Notify at 25%, 50%, 75%, 100%
};

/// Progress Component with Full Terminal Integration
pub const Progress = struct {
    allocator: Allocator,
    config: ProgressConfig,

    // Terminal interface
    terminal: *terminal_mod.Terminal,
    capabilities: caps_mod.TermCaps,
    mode: ProgressMode,

    // Progress tracking
    current_progress: f32,
    total_items: ?u64,
    completed_items: u64,
    start_time: i64,
    last_update: i64,

    // Data history and visualization
    history: std.ArrayList(ProgressPoint),
    chart_buffer: ?[]u8,
    chart_image_id: ?u32,

    // Advanced features state
    shell_job_id: ?[]const u8,
    last_notification_threshold: f32,
    iterm2_badge_set: bool,
    clipboard_data_formatted: ?[]u8,

    // Animation and rendering
    animation_frame: u32,
    render_buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator, terminal: *terminal_mod.Terminal, config: ProgressConfig) !Progress {
        const capabilities = terminal.getCapabilities();
        const mode = detectBestMode(capabilities);

        return Progress{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .mode = mode,
            .current_progress = 0.0,
            .total_items = null,
            .completed_items = 0,
            .start_time = std.time.timestamp(),
            .last_update = std.time.timestamp(),
            .history = std.ArrayList(ProgressPoint).init(allocator),
            .chart_buffer = null,
            .chart_image_id = null,
            .shell_job_id = null,
            .last_notification_threshold = 0.0,
            .iterm2_badge_set = false,
            .clipboard_data_formatted = null,
            .animation_frame = 0,
            .render_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Progress) void {
        // Clean up graphics resources
        if (self.chart_image_id) |image_id| {
            if (self.mode == .kitty_enhanced) {
                Kitty.deleteImage(self.render_buffer.writer(), self.capabilities, image_id) catch {};
            }
        }

        // Clean up shell integration
        if (self.config.enable_shell_integration and self.shellJobId != null) {
            Finalterm.endCommand(self.renderBuffer.writer(), self.capabilities, 0) catch {};
            self.terminal.flush() catch {};
        }

        // Clean up allocations
        if (self.chart_buffer) |buffer| {
            self.allocator.free(buffer);
        }
        if (self.clipboard_data_formatted) |data| {
            self.allocator.free(data);
        }
        if (self.shell_job_id) |job_id| {
            self.allocator.free(job_id);
        }

        self.history.deinit();
        self.renderBuffer.deinit();
    }

    /// Initialize advanced terminal features
    pub fn start(self: *Progress, totalItems: ?u64) !void {
        self.total_items = totalItems;
        self.start_time = std.time.timestamp();
        self.last_update = self.start_time;

        // Initialize shell integration
        if (self.config.enable_shell_integration and
            (self.capabilities.supportsFinalTermOsc133 or self.capabilities.supportsITerm2Osc1337))
        {
            self.render_buffer.clearRetainingCapacity();
            const writer = self.render_buffer.writer();

            // Generate unique job ID
            const jobId = try std.fmt.allocPrint(self.allocator, "progress_{d}", .{std.time.timestamp()});
            self.shell_job_id = jobId;

            // Start command marker (using placeholder implementation)
            try Finalterm.startCommand(writer, self.capabilities, jobId);
            try self.terminal.print(self.render_buffer.items, null);
            self.render_buffer.clearRetainingCapacity();
        }

        // Initialize iTerm2 integration
        if (self.mode == .iterm2_integrated and self.capabilities.supportsITerm2Osc1337) {
            const writer = self.render_buffer.writer();
            try Iterm2.setBadge(writer, self.capabilities, "🔄 0%");
            try self.terminal.print(self.render_buffer.items, null);
            self.render_buffer.clearRetainingCapacity();
            self.iterm2_badge_set = true;
        }

        // Initialize graphics if supported
        if (self.mode == .kitty_enhanced and self.config.show_chart) {
            try self.initializeChart();
        }
    }

    /// Update progress with comprehensive tracking
    pub fn update(self: *Progress, progress: f32, completedItems: ?u64, customData: ?[]const u8) !void {
        const now = std.time.timestamp();
        self.current_progress = std.math.clamp(progress, 0.0, 1.0);

        if (completedItems) |items| {
            self.completed_items = items;
        }

        // Calculate rate
        const elapsed = now - self.startTime;
        const rate = if (elapsed > 0) @as(f32, @floatFromInt(self.completedItems)) / @as(f32, @floatFromInt(elapsed)) else 0.0;

        // Calculate ETA
        const eta = if (self.current_progress > 0.01 and self.total_items != null) blk: {
            const remaining_items = self.total_items.? - self.completed_items;
            const eta_seconds = if (rate > 0.0) @as(i64, @intFromFloat(@as(f32, @floatFromInt(remaining_items)) / rate)) else null;
            break :blk eta_seconds;
        } else null;

        // Add to history for visualization
        try self.history.append(ProgressPoint{
            .timestamp = now,
            .progress = self.current_progress,
            .rate = rate,
            .eta_seconds = eta,
            .memory_usage = if (self.config.show_memory) self.getCurrentMemoryUsage() else null,
            .custom_data = customData,
        });

        // Limit history size
        if (self.history.items.len > self.config.chart_history_size) {
            _ = self.history.orderedRemove(0);
        }

        // Handle notifications
        if (self.config.enable_notifications) {
            try self.handleProgressNotifications();
        }

        // Update iTerm2 badge
        if (self.iterm2_badge_set and self.capabilities.supportsITerm2Osc1337) {
            const badgeText = try std.fmt.allocPrint(self.allocator, "🔄 {d:.0}%", .{self.current_progress * 100});
            defer self.allocator.free(badgeText);

            self.render_buffer.clearRetainingCapacity();
            try Iterm2.setBadge(self.render_buffer.writer(), self.capabilities, badgeText);
            try self.terminal.print(self.render_buffer.items, null);
        }

        // Update clipboard data
        if (self.config.enable_clipboard) {
            try self.updateClipboardData();
        }

        // Update chart graphics
        if (self.config.show_chart and (self.mode == .kitty_enhanced or self.mode == .sixel_graphics)) {
            try self.updateChart();
        }

        self.last_update = now;
    }

    /// Render the complete progress display
    pub fn render(self: *Progress, forceRedraw: bool) !void {
        if (!forceRedraw and (std.time.timestamp() - self.lastUpdate) < @as(i64, @intCast(self.config.update_interval_ms / 1000))) {
            return; // Skip render if too soon
        }

        self.animation_frame +%= 1;
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        // Synchronized output for flicker-free rendering
        if (self.capabilities.supportsSynchronizedOutput) {
            try writer.writeAll("\x1b[?2026h"); // Begin sync
        }

        // Clear line and render based on mode
        try writer.writeAll("\r\x1b[K");

        switch (self.mode) {
            .kitty_enhanced => try self.renderKittyEnhanced(writer),
            .sixel_graphics => try self.renderSixelGraphics(writer),
            .iterm2_integrated => try self.renderITerm2Integrated(writer),
            .finalterm_integrated => try self.renderFinalTermIntegrated(writer),
            .unicode_rich => try self.renderUnicodeRich(writer),
            .ascii_enhanced => try self.renderASCIIEnhanced(writer),
            .text_only => try self.renderTextOnly(writer),
        }

        // End synchronized output
        if (self.capabilities.supportsSynchronizedOutput) {
            try writer.writeAll("\x1b[?2026l"); // End sync
        }

        // Send to terminal
        try self.terminal.print(self.render_buffer.items, null);
        self.terminal.flush() catch {};
    }

    /// Complete the progress with cleanup and final notifications
    pub fn finish(self: *Progress, success: bool, finalMessage: ?[]const u8) !void {
        self.currentProgress = 1.0;

        // Final render
        try self.render(true);

        // Final notifications
        if (self.config.enable_notifications) {
            const message = finalMessage orelse if (success) "Task completed successfully!" else "Task failed";
            const level = if (success) terminal_mod.NotificationLevel.success else terminal_mod.NotificationLevel.@"error";

            // System notification
            if (self.capabilities.supportsNotifyOsc9) {
                try self.terminal.notification(level, "Progress Complete", message);
            }

            // Terminal notification
            try self.terminal.notification(level, "Progress Complete", message);
        }

        // Final iTerm2 badge
        if (self.iterm2_badge_set) {
            const badge = if (success) "✅ Done" else "❌ Failed";
            self.render_buffer.clearRetainingCapacity();
            try Iterm2.setBadge(self.render_buffer.writer(), self.capabilities, badge);
            try self.terminal.print(self.render_buffer.items, null);
        }

        // Final clipboard data
        if (self.config.enable_clipboard) {
            try self.copyFinalDataToClipboard(success, finalMessage);
        }

        // Shell integration completion
        if (self.config.enable_shell_integration and self.shell_job_id != null) {
            self.render_buffer.clearRetainingCapacity();
            const exitCode: u8 = if (success) 0 else 1;
            try Finalterm.endCommand(self.render_buffer.writer(), self.capabilities, exitCode);
            try self.terminal.print(self.render_buffer.items, null);
        }

        try self.terminal.print("\n", null);
    }

    // ========== PRIVATE IMPLEMENTATION ==========

    fn detectBestMode(capabilities: caps_mod.TermCaps) ProgressMode {
        // Priority order: Advanced graphics > Terminal integration > Fallbacks
        if (capabilities.supportsKittyGraphics and capabilities.supportsTruecolor) {
            return .kitty_enhanced;
        } else if (capabilities.supportsSixel) {
            return .sixel_graphics;
        } else if (capabilities.supportsITerm2Osc1337) {
            return .iterm2_integrated;
        } else if (capabilities.supportsFinalTermOsc133) {
            return .finalterm_integrated;
        } else if (capabilities.supportsTruecolor) {
            return .unicode_rich;
        } else if (capabilities.supports256Color) {
            return .ascii_enhanced;
        } else {
            return .text_only;
        }
    }

    fn initializeChart(self: *Progress) !void {
        if (self.mode != .kitty_enhanced) return;

        // Create chart buffer
        const chartSize = self.config.width * self.config.height * 4; // RGBA
        self.chart_buffer = try self.allocator.alloc(u8, chartSize);
        @memset(self.chart_buffer.?, 0);
    }

    fn updateChart(self: *Progress) !void {
        if (self.chart_buffer == null or self.history.items.len < 2) return;

        // Generate chart image data from history
        self.generateChartImageData();

        // Upload to terminal via graphics protocol
        switch (self.mode) {
            .kitty_enhanced => try self.uploadKittyChart(),
            .sixel_graphics => try self.uploadSixelChart(),
            else => {},
        }
    }

    fn generateChartImageData(self: *Progress) void {
        if (self.chart_buffer == null) return;

        const width = self.config.width;
        const height = self.config.height;
        const buffer = self.chart_buffer.?;

        // Clear to background color
        @memset(buffer, 0);

        if (self.history.items.len < 2) return;

        // Find min/max values for scaling
        var minProgress: f32 = 1.0;
        var maxProgress: f32 = 0.0;
        for (self.history.items) |point| {
            minProgress = @min(minProgress, point.progress);
            maxProgress = @max(maxProgress, point.progress);
        }

        const range = maxProgress - minProgress;
        if (range <= 0) return;

        // Draw progress line chart
        for (0..self.history.items.len - 1) |i| {
            if (i >= width - 1) break;

            const curr = self.history.items[i];
            const next = self.history.items[i + 1];

            const x1 = @as(u32, @intCast(i));
            const y1 = height - 1 - @as(u32, @intFromFloat(((curr.progress - minProgress) / range) * @as(f32, @floatFromInt(height - 1))));
            const x2 = @as(u32, @intCast(i + 1));
            const y2 = height - 1 - @as(u32, @intFromFloat(((next.progress - minProgress) / range) * @as(f32, @floatFromInt(height - 1))));

            // Draw line between points (simplified Bresenham)
            self.drawLine(x1, y1, x2, y2, [4]u8{ 50, 205, 50, 255 }); // Green
        }

        // Draw rate data if available
        if (self.config.show_rate) {
            var maxRate: f32 = 0;
            for (self.history.items) |point| {
                maxRate = @max(maxRate, point.rate);
            }

            if (maxRate > 0) {
                for (0..self.history.items.len - 1) |i| {
                    if (i >= width - 1) break;

                    const point = self.history.items[i];
                    const x = @as(u32, @intCast(i));
                    const y = height - 1 - @as(u32, @intFromFloat((point.rate / maxRate) * @as(f32, @floatFromInt(height - 1))));

                    self.setPixel(x, y, [4]u8{ 255, 127, 14, 255 }); // Orange for rate
                }
            }
        }
    }

    fn drawLine(self: *Progress, x1: u32, y1: u32, x2: u32, y2: u32, color: [4]u8) void {
        _ = self.chartBuffer orelse return;

        // Simple line drawing (could be improved with proper Bresenham)
        const dx = @as(i32, @intCast(x2)) - @as(i32, @intCast(x1));
        const dy = @as(i32, @intCast(y2)) - @as(i32, @intCast(y1));
        const steps = @max(@abs(dx), @abs(dy));

        if (steps == 0) {
            self.setPixel(x1, y1, color);
            return;
        }

        for (0..@as(u32, @intCast(steps))) |step| {
            const x = x1 + @as(u32, @intCast((@as(i32, @intCast(step)) * dx) / steps));
            const y = y1 + @as(u32, @intCast((@as(i32, @intCast(step)) * dy) / steps));
            self.setPixel(x, y, color);
        }
    }

    fn setPixel(self: *Progress, x: u32, y: u32, color: [4]u8) void {
        const buffer = self.chart_buffer orelse return;
        const width = self.config.width;
        const height = self.config.height;

        if (x >= width or y >= height) return;

        const offset = (y * width + x) * 4;
        if (offset + 3 < buffer.len) {
            buffer[offset] = color[0]; // R
            buffer[offset + 1] = color[1]; // G
            buffer[offset + 2] = color[2]; // B
            buffer[offset + 3] = color[3]; // A
        }
    }

    fn uploadKittyChart(self: *Progress) !void {
        const buffer = self.chartBuffer orelse return;

        // Encode image data as base64
        const encodedSize = std.base64.Encoder.calcSize(buffer.len);
        const encodedBuffer = try self.allocator.alloc(u8, encodedSize);
        defer self.allocator.free(encodedBuffer);

        _ = std.base64.standard.Encoder.encode(encodedBuffer, buffer);

        // Upload via Kitty graphics protocol
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        if (self.chartImageId == null) {
            // Create new image
            self.chartImageId = 1; // Simple ID for demo
            try Kitty.transmitImage(writer, self.capabilities, .{
                .image_id = self.chartImageId.?,
                .format = .rgba,
                .width = self.config.width,
                .height = self.config.height,
                .data = encodedBuffer,
            });
        } else {
            // Update existing image
            try Kitty.transmitImage(writer, self.capabilities, .{
                .image_id = self.chartImageId.?,
                .format = .rgba,
                .width = self.config.width,
                .height = self.config.height,
                .data = encodedBuffer,
            });
        }

        try self.terminal.print(self.renderBuffer.items, null);
    }

    fn uploadSixelChart(self: *Progress) !void {
        // Simplified Sixel implementation - would need full Sixel encoder in production
        // For now, just indicate that Sixel would be used
        _ = self;
    }

    fn handleProgressNotifications(self: *Progress) !void {
        const thresholds = [_]f32{ 0.25, 0.50, 0.75, 1.0 };

        for (thresholds) |threshold| {
            if (self.currentProgress >= threshold and self.lastNotificationThreshold < threshold) {
                const percentage = @as(u32, @intFromFloat(threshold * 100));
                const message = try std.fmt.allocPrint(self.allocator, "{s} - {d}% complete", .{ self.config.label, percentage });
                defer self.allocator.free(message);

                if (self.capabilities.supportsNotifyOsc9) {
                    try self.terminal.notification(.info, "Progress Update", message);
                }

                self.lastNotificationThreshold = threshold;
                break;
            }
        }
    }

    fn updateClipboardData(self: *Progress) !void {
        if (self.clipboard_data_formatted) |data| {
            self.allocator.free(data);
        }

        // Format comprehensive progress data
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        const writer = buffer.writer();
        try writer.print("Progress Report: {s}\n", .{self.config.label});
        try writer.print("Status: {d:.1}% complete\n", .{self.current_progress * 100});
        try writer.print("Items: {d}", .{self.completed_items});
        if (self.total_items) |total| {
            try writer.print(" / {d}", .{total});
        }
        try writer.writeAll("\n");

        if (self.history.items.len > 0) {
            const latest = self.history.items[self.history.items.len - 1];
            try writer.print("Rate: {d:.2} items/sec\n", .{latest.rate});
            if (latest.eta_seconds) |eta| {
                try writer.print("ETA: {d} seconds\n", .{eta});
            }
        }

        const elapsed = std.time.timestamp() - self.start_time;
        try writer.print("Elapsed: {d} seconds\n", .{elapsed});

        self.clipboard_data_formatted = try self.allocator.dupe(u8, buffer.items);

        // Copy to clipboard
        try self.terminal.copyToClipboard(self.clipboard_data_formatted.?);
    }

    fn copyFinalDataToClipboard(self: *Progress, success: bool, message: ?[]const u8) !void {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        const writer = buffer.writer();
        try writer.print("=== Final Progress Report: {s} ===\n", .{self.config.label});
        try writer.print("Status: {s}\n", .{if (success) "SUCCESS" else "FAILED"});
        if (message) |msg| {
            try writer.print("Message: {s}\n", .{msg});
        }

        try writer.print("Final Progress: {d:.1}%\n", .{self.currentProgress * 100});
        try writer.print("Total Items: {d}\n", .{self.completedItems});

        const totalTime = std.time.timestamp() - self.startTime;
        try writer.print("Total Time: {d} seconds\n", .{totalTime});

        const avgRate = if (totalTime > 0) @as(f32, @floatFromInt(self.completedItems)) / @as(f32, @floatFromInt(totalTime)) else 0.0;
        try writer.print("Average Rate: {d:.2} items/sec\n", .{avgRate});

        try self.terminal.copyToClipboard(buffer.items);
    }

    fn getCurrentMemoryUsage(self: *Progress) ?usize {
        _ = self;
        // Platform-specific memory usage detection would go here
        // For now, return null to indicate unavailable
        return null;
    }

    // ========== RENDERING MODES ==========

    fn renderKittyEnhanced(self: *Progress, writer: anytype) !void {
        // Enhanced label with emoji
        try writer.print("🚀 {s}: ", .{self.config.label});

        // Display inline chart if available
        if (self.chart_image_id != null and self.config.show_chart) {
            // Chart is already uploaded, just position it
            try Kitty.displayImage(writer, self.capabilities, self.chart_image_id.?, 0, 0);
            try writer.writeAll(" ");
        }

        // Enhanced progress bar
        try self.renderProgressBar(writer, .unicode_blocks);

        // Metadata
        try self.renderMetadata(writer);
    }

    fn renderSixelGraphics(self: *Progress, writer: anytype) !void {
        try writer.print("📊 {s}: ", .{self.config.label});

        // Sixel chart would be rendered here
        if (self.config.show_chart) {
            try writer.writeAll("[SIXEL CHART] ");
        }

        try self.renderProgressBar(writer, .unicode_blocks);
        try self.renderMetadata(writer);
    }

    fn renderITerm2Integrated(self: *Progress, writer: anytype) !void {
        // iTerm2 mark for this progress update
        if (self.capabilities.supportsITerm2Osc1337) {
            try Iterm2.setMark(writer, self.capabilities);
        }

        try writer.print("🍎 {s}: ", .{self.config.label});
        try self.renderProgressBar(writer, .unicode_blocks);
        try self.renderMetadata(writer);

        // Additional iTerm2 integration could include:
        // - Current directory reporting
        // - Application name setting
        // - Progress indicator in dock
    }

    fn renderFinalTermIntegrated(self: *Progress, writer: anytype) !void {
        // FinalTerm semantic markup
        if (self.shellJobId) |jobId| {
            try Finalterm.commandOutput(writer, self.capabilities, jobId);
        }

        try writer.print("🖥️  {s}: ", .{self.config.label});
        try self.renderProgressBar(writer, .unicode_blocks);
        try self.renderMetadata(writer);
    }

    fn renderUnicodeRich(self: *Progress, writer: anytype) !void {
        try writer.print("✨ {s}: ", .{self.config.label});
        try self.renderProgressBar(writer, .gradient_blocks);
        try self.renderMetadata(writer);

        // Add sparkline if history available
        if (self.history.items.len > 1) {
            try writer.writeAll(" ");
            try self.renderInlineSparkline(writer);
        }
    }

    fn renderASCIIEnhanced(self: *Progress, writer: anytype) !void {
        try writer.print(">> {s}: ", .{self.config.label});
        try self.renderProgressBar(writer, .ascii_art);
        try self.renderMetadata(writer);
    }

    fn renderTextOnly(self: *Progress, writer: anytype) !void {
        try writer.print("{s}: {d:.1}%", .{ self.config.label, self.current_progress * 100 });

        if (self.config.show_eta and self.history.items.len > 0) {
            const latest = self.history.items[self.history.items.len - 1];
            if (latest.eta_seconds) |eta| {
                try writer.print(" ETA: {d}s", .{eta});
            }
        }
    }

    // ========== HELPER RENDERING FUNCTIONS ==========

    const ProgressBarType = enum {
        ascii_art,
        unicode_blocks,
        gradient_blocks,
    };

    fn renderProgressBar(self: *Progress, writer: anytype, barType: ProgressBarType) !void {
        const filledChars = @as(u32, @intFromFloat(self.currentProgress * @as(f32, @floatFromInt(self.config.width))));

        switch (barType) {
            .ascii_art => {
                try writer.writeAll("[");
                for (0..filledChars) |_| try writer.writeAll("=");
                for (filledChars..self.config.width) |_| try writer.writeAll("-");
                try writer.writeAll("]");
            },
            .unicode_blocks => {
                try writer.writeAll("▕");
                for (0..filledChars) |_| try writer.writeAll("█");
                for (filledChars..self.config.width) |_| try writer.writeAll("░");
                try writer.writeAll("▏");
            },
            .gradient_blocks => {
                try writer.writeAll("▕");
                for (0..self.config.width) |i| {
                    const isFilled = i < filledChars;
                    if (isFilled) {
                        // Color gradient based on position
                        const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.config.width));
                        const hue = pos * 120.0; // Green to red
                        const rgb = hsvToRgb(120.0 - hue, 0.8, 1.0);
                        // Color would be applied in full implementation: rgb[0], rgb[1], rgb[2]
                        _ = rgb;
                        try writer.writeAll("█");
                    } else {
                        try writer.writeAll("░");
                    }
                }
                try writer.writeAll("▏");
            },
        }
    }

    fn renderMetadata(self: *Progress, writer: anytype) !void {
        try writer.print(" {d:.1}%", .{self.current_progress * 100});

        if (self.config.show_rate and self.history.items.len > 0) {
            const latest = self.history.items[self.history.items.len - 1];
            try writer.print(" ({d:.2}/s)", .{latest.rate});
        }

        if (self.config.show_eta and self.history.items.len > 0) {
            const latest = self.history.items[self.history.items.len - 1];
            if (latest.eta_seconds) |eta| {
                try writer.print(" ETA: {d}s", .{eta});
            }
        }
    }

    fn renderInlineSparkline(self: *Progress, writer: anytype) !void {
        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const data_points = @min(20, self.history.items.len);
        const start_idx = if (self.history.items.len > 20) self.history.items.len - 20 else 0;

        try writer.writeAll("[");
        for (0..data_points) |i| {
            const data_idx = start_idx + i;
            const value = self.history.items[data_idx].progress;
            const spark_idx = @as(usize, @intFromFloat(value * 7.0));
            try writer.writeAll(sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)]);
        }
        try writer.writeAll("]");
    }
};

/// HSV to RGB conversion for color gradients
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const c = v * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h >= 0.0 and h < 60.0) {
        r = c;
        g = x;
    } else if (h >= 60.0 and h < 120.0) {
        r = x;
        g = c;
    } else if (h >= 120.0 and h < 180.0) {
        g = c;
        b = x;
    } else if (h >= 180.0 and h < 240.0) {
        g = x;
        b = c;
    } else if (h >= 240.0 and h < 300.0) {
        r = x;
        b = c;
    } else {
        r = c;
        b = x;
    }

    return [3]u8{
        @intFromFloat((r + m) * 255.0),
        @intFromFloat((g + m) * 255.0),
        @intFromFloat((b + m) * 255.0),
    };
}

/// Kitty graphics helper structures
const KittyImageTransmission = struct {
    image_id: u32,
    format: enum { rgba, rgb, png },
    width: u32,
    height: u32,
    data: []const u8,
};

// Placeholder implementations for terminal protocols
// These would be fully implemented in the actual terminal modules

const Kitty = struct {
    fn transmitImage(writer: anytype, caps: caps_mod.TermCaps, transmission: KittyImageTransmission) !void {
        _ = caps;
        const format_code = switch (transmission.format) {
            .rgba => "f=32",
            .rgb => "f=24",
            .png => "f=100",
        };

        try writer.print("\x1b_G{s},i={d},s={d},v={d};{s}\x1b\\", .{
            format_code,
            transmission.image_id,
            transmission.width,
            transmission.height,
            transmission.data,
        });
    }

    fn displayImage(writer: anytype, caps: caps_mod.TermCaps, image_id: u32, x: u32, y: u32) !void {
        _ = caps;
        try writer.print("\x1b_Gi={d},c={d},r={d}\x1b\\", .{ image_id, x, y });
    }

    fn deleteImage(writer: anytype, caps: caps_mod.TermCaps, image_id: u32) !void {
        _ = caps;
        try writer.print("\x1b_Gd=i,i={d}\x1b\\", .{image_id});
    }
};

const Iterm2 = struct {
    fn setBadge(writer: anytype, caps: caps_mod.TermCaps, text: []const u8) !void {
        _ = caps;
        const encoded = try std.base64.standard.Encoder.calcSize(text.len);
        var buffer: [256]u8 = undefined;
        if (encoded <= buffer.len) {
            _ = std.base64.standard.Encoder.encode(buffer[0..encoded], text);
            try writer.print("\x1b]1337;SetBadgeFormat={s}\x07", .{buffer[0..encoded]});
        }
    }

    fn setMark(writer: anytype, caps: caps_mod.TermCaps) !void {
        _ = caps;
        try writer.writeAll("\x1b]1337;SetMark\x07");
    }
};

const Finalterm = struct {
    fn startCommand(writer: anytype, caps: caps_mod.TermCaps, command_id: []const u8) !void {
        _ = caps;
        try writer.print("\x1b]133;C;{s}\x07", .{command_id});
    }

    fn endCommand(writer: anytype, caps: caps_mod.TermCaps, exit_code: u8) !void {
        _ = caps;
        try writer.print("\x1b]133;D;{d}\x07", .{exit_code});
    }

    fn commandOutput(writer: anytype, caps: caps_mod.TermCaps, command_id: []const u8) !void {
        _ = caps;
        try writer.print("\x1b]133;A;{s}\x07", .{command_id});
    }
};

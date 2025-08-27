//! Runner for executing complex multi-step CLI operations
//! Provides progress tracking, error handling, and user interaction

const std = @import("std");
const termShared = @import("term_shared");
const termAnsi = termShared.ansi.color;
const termCaps = termShared.caps;
const notifications = @import("../notifications.zig");
const ProgressBar = @import("../components/mod.zig").ProgressBar;
const Step = @import("Step.zig");
const Allocator = std.mem.Allocator;

pub const Status = enum {
    pending,
    running,
    completed,
    failed,
    cancelled,
};

pub const Result = struct {
    status: Status,
    completedSteps: u32,
    totalSteps: u32,
    errorMessage: ?[]const u8 = null,
    elapsedTime: i64,
};

pub const Runner = struct {
    allocator: Allocator,
    caps: termCaps.TermCaps,
    notifications: *notifications.Handler,
    steps: std.ArrayList(Step.Step),
    currentStep: u32,
    status: Status,
    startTime: ?i64,
    progressBar: ?ProgressBar,
    showProgress: bool,
    interactive: bool,
    writer: ?*std.Io.Writer,

    pub fn init(
        allocator: Allocator,
        notificationHandler: *notifications.Handler,
    ) Runner {
        return .{
            .allocator = allocator,
            .caps = termCaps.getTermCaps(),
            .notifications = notificationHandler,
            .steps = std.ArrayList(Step.Step).init(allocator),
            .current_step = 0,
            .status = .pending,
            .start_time = null,
            .progress_bar = null,
            .show_progress = true,
            .interactive = false,
            .writer = null,
        };
    }

    pub fn deinit(self: *Runner) void {
        self.steps.deinit();
        if (self.progress_bar) |*bar| {
            bar.clear(self.writer.?) catch {};
        }
    }

    pub fn setWriter(self: *Runner, writer: *std.Io.Writer) void {
        self.writer = writer;
        self.notifications.setWriter(writer);
    }

    pub fn configure(
        self: *Runner,
        options: struct {
            show_progress: bool = true,
            interactive: bool = false,
        },
    ) void {
        self.show_progress = options.show_progress;
        self.interactive = options.interactive;
    }

    /// Add a step to the workflow
    pub fn addStep(self: *Runner, step: Step.Step) !void {
        try self.steps.append(step);
    }

    /// Add multiple steps to the workflow
    pub fn addSteps(self: *Runner, steps: []const Step.Step) !void {
        for (steps) |step| {
            try self.addStep(step);
        }
    }

    /// Execute the workflow
    pub fn execute(self: *Runner, workflow_name: []const u8) !Result {
        if (self.writer == null) {
            return error.NoWriter;
        }

        self.status = .running;
        self.start_time = std.time.timestamp();
        self.current_step = 0;

        // Initialize progress bar if enabled
        if (self.show_progress) {
            self.progress_bar = try ProgressBar.init(
                self.allocator,
                .unicode,
                40,
                workflow_name,
            );
        }

        // Send initial notification
        _ = try self.notifications.notify(
            .info,
            "Workflow Started",
            workflow_name,
        );

        try self.renderWorkflowHeader(workflow_name);

        // Execute each step
        for (self.steps.items, 0..) |step, i| {
            self.current_step = @intCast(i);

            // Update progress
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.steps.items.len));

            if (self.show_progress and self.progress_bar != null) {
                self.progress_bar.?.setProgress(progress);
                try self.progress_bar.?.render(self.writer.?);
            }

            // Execute step
            try self.renderStepStart(step);

            const stepResult = step.executeFn(self.allocator, step.context) catch |err| {
                self.status = .failed;

                const errorMsg = try std.fmt.allocPrint(
                    self.allocator,
                    "Step '{s}' failed: {any}",
                    .{ step.name, err },
                );

                try self.renderStepError(step, errorMsg);

                _ = try self.notifications.notify(
                    .err,
                    "Workflow Failed",
                    errorMsg,
                );

                return Result{
                    .status = .failed,
                    .completed_steps = @intCast(i),
                    .total_steps = @intCast(self.steps.items.len),
                    .error_message = errorMsg,
                    .elapsed_time = std.time.timestamp() - self.start_time.?,
                };
            };

            if (!stepResult.success) {
                self.status = .failed;

                try self.renderStepError(step, stepResult.errorMessage);

                _ = try self.notifications.notify(
                    .err,
                    "Workflow Failed",
                    stepResult.errorMessage orelse "Unknown error",
                );

                return Result{
                    .status = .failed,
                    .completed_steps = @intCast(i),
                    .total_steps = @intCast(self.steps.items.len),
                    .error_message = stepResult.error_message,
                    .elapsed_time = std.time.timestamp() - self.start_time.?,
                };
            }

            try self.renderStepSuccess(step);

            // Interactive pause if enabled
            if (self.interactive) {
                try self.waitForUserConfirmation();
            }
        }

        // Complete workflow
        self.status = .completed;

        if (self.show_progress and self.progress_bar != null) {
            self.progress_bar.?.setProgress(1.0);
            try self.progress_bar.?.render(self.writer.?);
        }

        try self.renderWorkflowComplete();

        _ = try self.notifications.notify(
            .success,
            "Workflow Completed",
            workflow_name,
        );

        return Result{
            .status = .completed,
            .completed_steps = @intCast(self.steps.items.len),
            .total_steps = @intCast(self.steps.items.len),
            .error_message = null,
            .elapsed_time = std.time.timestamp() - self.start_time.?,
        };
    }

    fn renderWorkflowHeader(self: *Runner, name: []const u8) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer.*, self.caps, 100, 149, 237);
        } else {
            try termAnsi.setForeground256(writer.*, self.caps, 12);
        }

        try writer.writeAll("\n┌─────────────────────────────────────────┐\n");
        try writer.print("│  🔧 Workflow: {s:<30} │\n", .{name});
        try writer.print("│  Steps: {d:<34} │\n", .{self.steps.items.len});
        try writer.writeAll("└─────────────────────────────────────────┘\n\n");

        try termAnsi.resetStyle(writer.*, self.caps);
    }

    fn renderStepStart(self: *Runner, step: Step.Step) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
        } else {
            try termAnsi.setForeground256(writer.*, self.caps, 11);
        }

        try writer.print("⧖ Step {d}/{d}: {s}", .{ self.current_step + 1, self.steps.items.len, step.name });

        if (step.description) |desc| {
            if (self.caps.supportsTrueColor()) {
                try termAnsi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
            } else {
                try termAnsi.setForeground256(writer.*, self.caps, 7);
            }
            try writer.print(" - {s}", .{desc});
        }

        try writer.writeAll("\n");
        try termAnsi.resetStyle(writer.*, self.caps);
    }

    fn renderStepSuccess(self: *Runner, step: Step.Step) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try termAnsi.setForeground256(writer.*, self.caps, 10);
        }

        try writer.print("✓ Completed: {s}\n", .{step.name});
        try termAnsi.resetStyle(writer.*, self.caps);
    }

    fn renderStepError(self: *Runner, step: Step.Step, errorMsg: ?[]const u8) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer.*, self.caps, 255, 69, 0);
        } else {
            try termAnsi.setForeground256(writer.*, self.caps, 9);
        }

        try writer.print("✗ Failed: {s}", .{step.name});

        if (errorMsg) |msg| {
            try writer.print(" - {s}", .{msg});
        }

        try writer.writeAll("\n");
        try termAnsi.resetStyle(writer.*, self.caps);
    }

    fn renderWorkflowComplete(self: *Runner) !void {
        const writer = self.writer.?;
        const elapsed = std.time.timestamp() - self.start_time.?;

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try termAnsi.setForeground256(writer.*, self.caps, 10);
        }

        try writer.writeAll("\n┌─────────────────────────────────────────┐\n");
        try writer.writeAll("│  ✅ Workflow Completed Successfully!   │\n");
        try writer.print("│  Time: {d}s                             │\n", .{elapsed});
        try writer.writeAll("└─────────────────────────────────────────┘\n\n");

        try termAnsi.resetStyle(writer.*, self.caps);
    }

    fn waitForUserConfirmation(self: *Runner) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try termAnsi.setForeground256(writer.*, self.caps, 7);
        }

        try writer.writeAll("Press Enter to continue to next step...");
        try termAnsi.resetStyle(writer.*, self.caps);

        // In a real implementation, this would read from stdin
        // For now, just a brief pause
        std.time.sleep(500 * std.time.ns_per_ms);
        try writer.writeAll(" ✓\n");
    }

    /// Cancel the workflow
    pub fn cancel(self: *Runner) !void {
        self.status = .cancelled;

        _ = try self.notifications.notify(
            .warning,
            "Workflow Cancelled",
            "Workflow execution was cancelled by user",
        );

        if (self.show_progress and self.progress_bar != null) {
            try self.progress_bar.?.clear(self.writer.?);
        }
    }

    /// Get current progress
    pub fn getProgress(self: Runner) f32 {
        if (self.steps.items.len == 0) return 0.0;
        return @as(f32, @floatFromInt(self.current_step)) / @as(f32, @floatFromInt(self.steps.items.len));
    }

    /// Get estimated time remaining
    pub fn getEstimatedTimeRemaining(self: Runner) ?i64 {
        if (self.start_time == null or self.current_step == 0) return null;

        const elapsed = std.time.timestamp() - self.start_time.?;
        const progress = self.getProgress();

        if (progress <= 0.0) return null;

        const total_estimated = @as(f32, @floatFromInt(elapsed)) / progress;
        return @as(i64, @intFromFloat(total_estimated)) - elapsed;
    }
};

//! Workflow runner for executing complex multi-step CLI operations
//! Provides progress tracking, error handling, and user interaction

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_caps = term_shared.caps;
const notifications = @import("../notifications.zig");
const ProgressBar = @import("../components/mod.zig").ProgressBar;
const WorkflowStepMod = @import("workflow_step.zig");
const Allocator = std.mem.Allocator;

pub const WorkflowStatus = enum {
    pending,
    running,
    completed,
    failed,
    cancelled,
};

pub const WorkflowResult = struct {
    const Self = @This();
    status: WorkflowStatus,
    completedSteps: u32,
    totalSteps: u32,
    errorMessage: ?[]const u8 = null,
    elapsedTime: i64,
};

pub const WorkflowRunner = struct {
    const Self = @This();
    allocator: Allocator,
    caps: term_caps.TermCaps,
    notificationManager: *notifications.NotificationHandler,
    steps: std.ArrayList(WorkflowStepMod.WorkflowStep),
    currentStep: u32,
    status: WorkflowStatus,
    startTime: ?i64,
    progressBar: ?ProgressBar,
    showProgress: bool,
    interactive: bool,
    writer: ?*std.Io.Writer,

    pub fn init(
        allocator: Allocator,
        notificationMgr: *notifications.NotificationHandler,
    ) Self {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .notificationManager = notificationMgr,
            .steps = std.ArrayList(WorkflowStepMod.WorkflowStep).init(allocator),
            .currentStep = 0,
            .status = .pending,
            .startTime = null,
            .progressBar = null,
            .showProgress = true,
            .interactive = false,
            .writer = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Deinit step contexts if present
        for (self.steps.items) |*s| {
            s.deinit();
        }
        self.steps.deinit();
        if (self.progressBar) |*bar| {
            bar.clear(self.writer.?) catch {};
        }
    }

    pub fn setWriter(self: *Self, writer: *std.Io.Writer) void {
        self.writer = writer;
        self.notificationManager.setWriter(writer);
    }

    pub fn configure(
        self: *Self,
        options: struct {
            showProgress: bool = true,
            interactive: bool = false,
        },
    ) void {
        self.showProgress = options.showProgress;
        self.interactive = options.interactive;
    }

    /// Add a step to the workflow
    pub fn addStep(self: *Self, step: WorkflowStepMod.WorkflowStep) !void {
        try self.steps.append(step);
    }

    /// Add multiple steps to the workflow
    pub fn addSteps(self: *Self, steps: []const WorkflowStepMod.WorkflowStep) !void {
        for (steps) |step| {
            try self.addStep(step);
        }
    }

    /// Execute the workflow
    pub fn execute(self: *Self, workflowName: []const u8) !WorkflowResult {
        if (self.writer == null) {
            return error.NoWriter;
        }

        self.status = .running;
        self.startTime = std.time.timestamp();
        self.currentStep = 0;

        // Initialize progress bar if enabled
        if (self.showProgress) {
            self.progressBar = try ProgressBar.init(
                self.allocator,
                .unicode,
                40,
                workflowName,
            );
        }

        // Send initial notification
        _ = try self.notificationManager.notify(
            .info,
            "Workflow Started",
            workflowName,
        );

        try self.renderWorkflowHeader(workflowName);

        // Execute each step
        for (self.steps.items, 0..) |step, i| {
            self.currentStep = @intCast(i);

            // Update progress
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.steps.items.len));

            if (self.showProgress and self.progressBar != null) {
                self.progressBar.?.setProgress(progress);
                try self.progressBar.?.render(self.writer.?);
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

                _ = try self.notificationManager.notify(
                    .err,
                    "Workflow Failed",
                    errorMsg,
                );

                return WorkflowResult{
                    .status = .failed,
                    .completedSteps = @intCast(i),
                    .totalSteps = @intCast(self.steps.items.len),
                    .errorMessage = errorMsg,
                    .elapsedTime = std.time.timestamp() - self.startTime.?,
                };
            };

            if (!stepResult.success) {
                self.status = .failed;

                try self.renderStepError(step, stepResult.errorMessage);

                _ = try self.notificationManager.notify(
                    .err,
                    "Workflow Failed",
                    stepResult.errorMessage orelse "Unknown error",
                );

                return WorkflowResult{
                    .status = .failed,
                    .completedSteps = @intCast(i),
                    .totalSteps = @intCast(self.steps.items.len),
                    .errorMessage = stepResult.errorMessage,
                    .elapsedTime = std.time.timestamp() - self.startTime.?,
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

        if (self.showProgress and self.progressBar != null) {
            self.progressBar.?.setProgress(1.0);
            try self.progressBar.?.render(self.writer.?);
        }

        try self.renderWorkflowComplete();

        _ = try self.notificationManager.notify(
            .success,
            "Workflow Completed",
            workflowName,
        );

        return WorkflowResult{
            .status = .completed,
            .completedSteps = @intCast(self.steps.items.len),
            .totalSteps = @intCast(self.steps.items.len),
            .errorMessage = null,
            .elapsedTime = std.time.timestamp() - self.startTime.?,
        };
    }

    fn renderWorkflowHeader(self: *Self, name: []const u8) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 12);
        }

        try writer.writeAll("\n┌─────────────────────────────────────────┐\n");
        try writer.print("│  🔧 Workflow: {s:<30} │\n", .{name});
        try writer.print("│  Steps: {d:<34} │\n", .{self.steps.items.len});
        try writer.writeAll("└─────────────────────────────────────────┘\n\n");

        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderStepStart(self: *Self, step: WorkflowStepMod.WorkflowStep) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 11);
        }

        try writer.print("⧖ Step {d}/{d}: {s}", .{ self.currentStep + 1, self.steps.items.len, step.name });

        if (step.description) |desc| {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
            } else {
                try term_ansi.setForeground256(writer.*, self.caps, 7);
            }
            try writer.print(" - {s}", .{desc});
        }

        try writer.writeAll("\n");
        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderStepSuccess(self: *Self, step: WorkflowStepMod.WorkflowStep) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 10);
        }

        try writer.print("✓ Completed: {s}\n", .{step.name});
        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderStepError(self: *Self, step: WorkflowStepMod.WorkflowStep, errorMsg: ?[]const u8) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 69, 0);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 9);
        }

        try writer.print("✗ Failed: {s}", .{step.name});

        if (errorMsg) |msg| {
            try writer.print(" - {s}", .{msg});
        }

        try writer.writeAll("\n");
        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn renderWorkflowComplete(self: *Self) !void {
        const writer = self.writer.?;
        const elapsed = std.time.timestamp() - self.startTime.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 10);
        }

        try writer.writeAll("\n┌─────────────────────────────────────────┐\n");
        try writer.writeAll("│  ✅ Workflow Completed Successfully!   │\n");
        try writer.print("│  Time: {d}s                             │\n", .{elapsed});
        try writer.writeAll("└─────────────────────────────────────────┘\n\n");

        try term_ansi.resetStyle(writer.*, self.caps);
    }

    fn waitForUserConfirmation(self: *Self) !void {
        const writer = self.writer.?;

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 7);
        }

        try writer.writeAll("Press Enter to continue to next step...");
        try term_ansi.resetStyle(writer.*, self.caps);

        // In a real implementation, this would read from stdin
        // For now, just a brief pause
        std.time.sleep(500 * std.time.ns_per_ms);
        try writer.writeAll(" ✓\n");
    }

    /// Cancel the workflow
    pub fn cancel(self: *Self) !void {
        self.status = .cancelled;

        _ = try self.notificationManager.notify(
            .warning,
            "Workflow Cancelled",
            "Workflow execution was cancelled by user",
        );

        if (self.showProgress and self.progressBar != null) {
            try self.progressBar.?.clear(self.writer.?);
        }
    }

    /// Get current progress
    pub fn getProgress(self: Self) f32 {
        if (self.steps.items.len == 0) return 0.0;
        return @as(f32, @floatFromInt(self.currentStep)) / @as(f32, @floatFromInt(self.steps.items.len));
    }

    /// Get estimated time remaining
    pub fn getEstimatedTimeRemaining(self: Self) ?i64 {
        if (self.startTime == null or self.currentStep == 0) return null;

        const elapsed = std.time.timestamp() - self.startTime.?;
        const progress = self.getProgress();

        if (progress <= 0.0) return null;

        const total_estimated = @as(f32, @floatFromInt(elapsed)) / progress;
        return @as(i64, @intFromFloat(total_estimated)) - elapsed;
    }
};

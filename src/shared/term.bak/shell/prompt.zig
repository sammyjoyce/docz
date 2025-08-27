const std = @import("std");

/// Prompt and command tracking functionality
/// Provides high-level utilities for managing shell integration lifecycle
pub fn PromptTracker(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?ShellContextType(WriterType) = null,

        pub fn ShellContextType(comptime InnerWriterType: type) type {
            return struct {
                writer: InnerWriterType,
                allocator: std.mem.Allocator,
                caps: @import("integration.zig").Shell.TermCaps,
                iface: @import("integration.zig").Shell.Interface,

                const Self = @This();

                pub fn init(writer: InnerWriterType, allocator: std.mem.Allocator, caps: @import("integration.zig").Shell.TermCaps, iface: @import("integration.zig").Shell.Interface) Self {
                    return .{
                        .writer = writer,
                        .allocator = allocator,
                        .caps = caps,
                        .iface = iface,
                    };
                }

                /// Create a shell integration context
                pub fn createShellContext(self: Self) @import("integration.zig").Shell.Context(InnerWriterType) {
                    return @import("integration.zig").Shell.createContext(InnerWriterType, self.writer, self.allocator, self.caps);
                }
            };
        }

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: ShellContextType(WriterType)) void {
            self.context = context;
        }

        /// Mark the start of a shell prompt
        pub fn markPromptStart(self: Self) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptStart(shellCtx);
            }
        }

        /// Mark the end of a shell prompt (start of user input)
        pub fn markPromptEnd(self: Self) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptEnd(shellCtx);
            }
        }

        /// Mark prompt start with additional parameters
        pub fn markPromptStartWithParams(self: Self, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptStartWithParams(shellCtx, params);
            }
        }

        /// Mark prompt end with additional parameters
        pub fn markPromptEndWithParams(self: Self, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptEndWithParams(shellCtx, params);
            }
        }
    };
}

/// Command execution tracker
pub fn CommandTracker(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Mark the start of command execution
        pub fn markCommandStart(self: Self, command: []const u8, cwd: ?[]const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandStart(shellCtx, command, cwd);
            }
        }

        /// Mark the end of command execution
        pub fn markCommandEnd(self: Self, command: []const u8, exit_code: i32, duration_ms: ?u64) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandEnd(shellCtx, command, exit_code, duration_ms);
            }
        }

        /// Mark command start with additional parameters
        pub fn markCommandStartWithParams(self: Self, command: []const u8, cwd: ?[]const u8, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandStartWithParams(shellCtx, command, cwd, params);
            }
        }

        /// Mark command end with additional parameters
        pub fn markCommandEndWithParams(self: Self, command: []const u8, exit_code: i32, duration_ms: ?u64, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandEndWithParams(shellCtx, command, exit_code, duration_ms, params);
            }
        }

        /// Execute a command with proper shell integration markers
        pub fn executeCommand(
            self: Self,
            command: []const u8,
            cwd: ?[]const u8,
            command_fn: anytype,
            args: anytype,
        ) !i32 {
            // Mark command start
            try self.markCommandStart(command, cwd);

            // Record start time
            const start_time = std.time.milliTimestamp();

            // Execute command
            const exit_code = @call(.auto, command_fn, args);

            // Calculate duration
            const end_time = std.time.milliTimestamp();
            const duration_ms = if (end_time > start_time) @as(u64, @intCast(end_time - start_time)) else null;

            // Mark command end
            try self.markCommandEnd(command, exit_code, duration_ms);

            return exit_code;
        }
    };
}

/// Directory tracker for working directory changes
pub fn DirectoryTracker(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,
        current_dir: ?[]u8 = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.current_dir) |dir| {
                self.allocator.free(dir);
            }
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Set the current working directory
        pub fn setWorkingDirectory(self: *Self, path: []const u8) !void {
            // Free previous directory
            if (self.current_dir) |dir| {
                self.allocator.free(dir);
            }

            // Store new directory
            self.current_dir = try self.allocator.dupe(u8, path);

            // Notify terminal if context is available
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.directory_ops.setWorkingDirectory(shellCtx, path);
            }
        }

        /// Set remote host information
        pub fn setRemoteHost(self: *Self, hostname: []const u8, username: ?[]const u8, port: ?u16) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.directory_ops.setRemoteHost(shellCtx, hostname, username, port);
            }
        }

        /// Clear remote host information (back to local)
        pub fn clearRemoteHost(self: *Self) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.directory_ops.clearRemoteHost(shellCtx);
            }
        }

        /// Get the current working directory
        pub fn getCurrentDirectory(self: Self) ?[]const u8 {
            return self.current_dir;
        }
    };
}

/// Notification manager for terminal notifications
pub fn Notification(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Request terminal attention/notification
        pub fn requestAttention(self: Self, message: ?[]const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.notification_ops.requestAttention(shellCtx, message);
            }
        }

        /// Set the terminal badge
        pub fn setBadge(self: Self, text: []const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.notification_ops.setBadge(shellCtx, text);
            }
        }

        /// Clear the terminal badge
        pub fn clearBadge(self: Self) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.notification_ops.clearBadge(shellCtx);
            }
        }

        /// Set alert on command completion
        pub fn setAlertOnCompletion(self: Self, config: shell_integration.Shell.AlertConfig) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.notification_ops.setAlertOnCompletion(shellCtx, config);
            }
        }

        /// Trigger a file download
        pub fn triggerDownload(self: Self, config: shell_integration.Shell.DownloadConfig) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.notification_ops.triggerDownload(shellCtx, config);
            }
        }
    };
}

/// Semantic zone manager for marking regions of output
pub fn SemanticZone(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Mark a semantic zone start
        pub fn markZoneStart(self: Self, zone_type: []const u8, name: ?[]const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.semantic_ops.markZoneStart(shellCtx, zone_type, name);
            }
        }

        /// Mark a semantic zone end
        pub fn markZoneEnd(self: Self, zone_type: []const u8) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.semantic_ops.markZoneEnd(shellCtx, zone_type);
            }
        }

        /// Add an annotation to terminal output
        pub fn addAnnotation(self: Self, config: shell_integration.Shell.AnnotationConfig) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.semantic_ops.addAnnotation(shellCtx, config);
            }
        }

        /// Clear all annotations
        pub fn clearAnnotations(self: Self) !void {
            if (self.context) |ctx| {
                const shellCtx = ctx.createShellContext();
                try ctx.iface.semantic_ops.clearAnnotations(shellCtx);
            }
        }
    };
}

const std = @import("std");
const os = std.os;
const posix = std.posix;
const linux = std.os.linux;
const termios = @import("termios.zig");

// Cross-platform PTY (Pseudo-Terminal) interface
// Based on charmbracelet/x xpty package design
//
// Provides a unified interface for creating and managing pseudo-terminals
// across Unix-like systems and Windows (ConPTY support planned).

/// PTY error types
pub const PtyError = error{
    /// Failed to create master/slave pair
    CreateFailed,
    /// Failed to fork process
    ForkFailed,
    /// Failed to execute command
    ExecFailed,
    /// Permission denied
    PermissionDenied,
    /// Invalid arguments
    InvalidArgument,
    /// Feature not supported on this platform
    NotSupported,
    /// System error
    SystemError,
    /// Out of memory
    OutOfMemory,
};

/// PTY configuration options
pub const PtyOptions = struct {
    /// Initial window size
    rows: u16 = 24,
    cols: u16 = 80,
    /// Working directory for spawned process
    cwd: ?[]const u8 = null,
    /// Environment variables (null means inherit)
    env: ?std.process.EnvMap = null,
    /// Terminal type (TERM environment variable)
    term: []const u8 = "xterm-256color",
    /// Whether to create a controlling terminal
    controlling_terminal: bool = true,
    /// Additional flags for PTY creation
    flags: PtyFlags = .{},

    pub const PtyFlags = packed struct {
        /// Enable UTF-8 support
        utf8: bool = true,
        /// Enable window size reporting
        winsize_reporting: bool = true,
        /// Echo input (usually disabled for applications)
        echo: bool = false,
        /// Use raw mode (disable line buffering and special character processing)
        raw_mode: bool = true,

        _padding: u4 = 0,
    };
};

/// Represents a PTY master/slave pair
pub const Pty = struct {
    /// Master file descriptor (for I/O)
    master_fd: posix.fd_t,
    /// Slave file descriptor (for process)
    slave_fd: posix.fd_t,
    /// Slave device path (e.g., "/dev/pts/0")
    slave_path: []u8,
    /// Process spawned in PTY (if any)
    process: ?std.process.Child = null,
    /// Original terminal settings (for restoration)
    original_termios: ?termios.TermiosConfig = null,
    /// Allocator used for memory management
    allocator: std.mem.Allocator,
    /// Current window size
    window_size: termios.Winsize,

    /// Create a new PTY pair
    pub fn init(allocator: std.mem.Allocator, options: PtyOptions) PtyError!Pty {
        const result = createPtyPair(allocator, options) catch |err| switch (err) {
            error.OutOfMemory => return PtyError.OutOfMemory,
            error.AccessDenied => return PtyError.PermissionDenied,
            error.InvalidArgument => return PtyError.InvalidArgument,
            else => return PtyError.CreateFailed,
        };

        var pty = Pty{
            .master_fd = result.master_fd,
            .slave_fd = result.slave_fd,
            .slave_path = result.slave_path,
            .allocator = allocator,
            .window_size = termios.Winsize.init(options.rows, options.cols),
        };

        // Configure terminal settings
        if (options.flags.raw_mode) {
            pty.original_termios = termios.setRawMode(pty.slave_fd) catch null;
        }

        // Set initial window size
        try pty.resize(options.rows, options.cols);

        return pty;
    }

    /// Clean up PTY resources
    pub fn deinit(self: *Pty) void {
        // Restore original terminal settings if saved
        if (self.original_termios) |config| {
            termios.restoreMode(self.slave_fd, config) catch {};
        }

        // Terminate process if running
        if (self.process) |*proc| {
            _ = proc.kill() catch {};
            _ = proc.wait() catch {};
        }

        // Close file descriptors
        os.close(self.master_fd);
        if (self.slave_fd != self.master_fd) {
            os.close(self.slave_fd);
        }

        // Free slave path
        self.allocator.free(self.slave_path);
    }

    /// Spawn a command in the PTY
    pub fn spawn(self: *Pty, argv: []const []const u8, options: PtyOptions) PtyError!void {
        if (self.process != null) {
            return PtyError.InvalidArgument; // Process already spawned
        }

        var child = std.process.Child.init(argv, self.allocator);

        // Set up process environment
        if (options.env) |*env_map| {
            child.env_map = env_map;
        }

        if (options.cwd) |cwd| {
            child.cwd = cwd;
        }

        // Configure stdio to use PTY
        child.stdin_behavior = .{ .fd = self.slave_fd };
        child.stdout_behavior = .{ .fd = self.slave_fd };
        child.stderr_behavior = .{ .fd = self.slave_fd };

        // Start the process
        child.spawn() catch |err| switch (err) {
            error.FileNotFound => return PtyError.ExecFailed,
            error.OutOfMemory => return PtyError.OutOfMemory,
            error.AccessDenied => return PtyError.PermissionDenied,
            else => return PtyError.SystemError,
        };

        self.process = child;
    }

    /// Read data from PTY master
    pub fn read(self: *Pty, buffer: []u8) PtyError!usize {
        const bytes_read = os.read(self.master_fd, buffer) catch |err| switch (err) {
            error.WouldBlock => return 0,
            error.AccessDenied => return PtyError.PermissionDenied,
            error.BrokenPipe, error.ConnectionResetByPeer => return 0,
            else => return PtyError.SystemError,
        };

        return bytes_read;
    }

    /// Write data to PTY master
    pub fn write(self: *Pty, data: []const u8) PtyError!usize {
        const bytes_written = os.write(self.master_fd, data) catch |err| switch (err) {
            error.WouldBlock => return 0,
            error.AccessDenied => return PtyError.PermissionDenied,
            error.BrokenPipe, error.ConnectionResetByPeer => return 0,
            else => return PtyError.SystemError,
        };

        return bytes_written;
    }

    /// Resize the PTY window
    pub fn resize(self: *Pty, rows: u16, cols: u16) PtyError!void {
        self.window_size.rows = rows;
        self.window_size.cols = cols;

        termios.setWinsize(self.master_fd, self.window_size) catch |err| switch (err) {
            termios.TermiosError.InvalidFd => return PtyError.InvalidArgument,
            termios.TermiosError.NotSupported => return PtyError.NotSupported,
            else => return PtyError.SystemError,
        };

        // Send SIGWINCH to process if running
        if (self.process) |proc| {
            if (proc.id) |pid| {
                _ = os.linux.kill(@intCast(pid), os.linux.SIG.WINCH);
            }
        }
    }

    /// Get current window size
    pub fn getSize(self: *Pty) PtyError!termios.Winsize {
        const winsize = termios.getWinsize(self.master_fd) catch |err| switch (err) {
            termios.TermiosError.InvalidFd => return PtyError.InvalidArgument,
            termios.TermiosError.NotSupported => return PtyError.NotSupported,
            else => return PtyError.SystemError,
        };

        return winsize;
    }

    /// Get the slave device path
    pub fn getSlavePath(self: *Pty) []const u8 {
        return self.slave_path;
    }

    /// Check if the spawned process is still running
    pub fn isRunning(self: *Pty) bool {
        if (self.process) |*proc| {
            if (proc.poll()) {
                return false;
            } else |_| {
                return true;
            }
        }
        return false;
    }

    /// Wait for the spawned process to exit
    pub fn wait(self: *Pty) PtyError!std.process.Child.Term {
        if (self.process) |*proc| {
            const term = proc.wait() catch |err| switch (err) {
                error.ChildAlreadyReaped => return std.process.Child.Term{ .Exited = 0 },
                else => return PtyError.SystemError,
            };
            return term;
        }
        return PtyError.InvalidArgument;
    }

    /// Set PTY to non-blocking mode
    pub fn setNonBlocking(self: *Pty, non_blocking: bool) PtyError!void {
        const flags = os.fcntl(self.master_fd, os.F.GETFL, 0) catch return PtyError.SystemError;
        const new_flags = if (non_blocking) flags | os.O.NONBLOCK else flags & ~@as(u32, os.O.NONBLOCK);
        _ = os.fcntl(self.master_fd, os.F.SETFL, new_flags) catch return PtyError.SystemError;
    }
};

/// Create a PTY master/slave pair
fn createPtyPair(allocator: std.mem.Allocator, options: PtyOptions) !struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    slave_path: []u8,
} {
    _ = options; // TODO: Use options for configuration

    // Open /dev/ptmx (master PTY multiplexer)
    const master_fd = os.open("/dev/ptmx", os.O.RDWR | os.O.NOCTTY, 0) catch |err| switch (err) {
        error.AccessDenied => return PtyError.PermissionDenied,
        error.FileNotFound => return PtyError.NotSupported, // No PTY support
        else => return PtyError.CreateFailed,
    };

    errdefer os.close(master_fd);

    // Grant access to the slave PTY
    if (grantpt(master_fd) != 0) {
        return PtyError.CreateFailed;
    }

    // Unlock the slave PTY
    if (unlockpt(master_fd) != 0) {
        return PtyError.CreateFailed;
    }

    // Get the slave PTY name
    const slave_path = try getPtyName(allocator, master_fd);
    errdefer allocator.free(slave_path);

    // Open the slave PTY
    const slave_fd = os.open(slave_path, os.O.RDWR | os.O.NOCTTY, 0) catch |err| switch (err) {
        error.AccessDenied => return PtyError.PermissionDenied,
        else => return PtyError.CreateFailed,
    };

    errdefer os.close(slave_fd);

    return .{
        .master_fd = master_fd,
        .slave_fd = slave_fd,
        .slave_path = slave_path,
    };
}

/// Grant access to the slave PTY (Unix-specific)
fn grantpt(master_fd: posix.fd_t) c_int {
    return os.linux.ioctl(master_fd, linux.TIOCSPTLCK, @intFromPtr(&@as(c_int, 0)));
}

/// Unlock the slave PTY (Unix-specific)
fn unlockpt(master_fd: posix.fd_t) c_int {
    return os.linux.ioctl(master_fd, linux.TIOCSPTLCK, @intFromPtr(&@as(c_int, 0)));
}

/// Get the slave PTY device name
fn getPtyName(allocator: std.mem.Allocator, master_fd: posix.fd_t) ![]u8 {
    // Get the PTY number
    var pty_num: c_int = undefined;
    const result = os.linux.ioctl(master_fd, linux.TIOCGPTN, @intFromPtr(&pty_num));
    if (os.linux.getErrno(result) != .SUCCESS) {
        return PtyError.CreateFailed;
    }

    // Format the slave device path
    return try std.fmt.allocPrint(allocator, "/dev/pts/{d}", .{pty_num});
}

/// Convenience function to spawn a shell in a PTY
pub fn spawnShell(allocator: std.mem.Allocator, options: PtyOptions) PtyError!Pty {
    var pty = try Pty.init(allocator, options);
    errdefer pty.deinit();

    // Determine shell to use
    const shell = std.process.getEnvVarOwned(allocator, "SHELL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allocator.dupe(u8, "/bin/sh"),
        else => return PtyError.SystemError,
    };
    defer allocator.free(shell);

    const argv = [_][]const u8{shell};
    try pty.spawn(&argv, options);

    return pty;
}

/// High-level PTY manager for common use cases
pub const PtyManager = struct {
    allocator: std.mem.Allocator,
    ptys: std.ArrayList(Pty),

    pub fn init(allocator: std.mem.Allocator) PtyManager {
        return PtyManager{
            .allocator = allocator,
            .ptys = std.ArrayList(Pty).init(allocator),
        };
    }

    pub fn deinit(self: *PtyManager) void {
        for (self.ptys.items) |*pty| {
            pty.deinit();
        }
        self.ptys.deinit();
    }

    /// Create and register a new PTY
    pub fn createPty(self: *PtyManager, options: PtyOptions) PtyError!*Pty {
        const pty = try Pty.init(self.allocator, options);
        try self.ptys.append(pty);
        return &self.ptys.items[self.ptys.items.len - 1];
    }

    /// Create and spawn shell in new PTY
    pub fn createShell(self: *PtyManager, options: PtyOptions) PtyError!*Pty {
        const pty = try spawnShell(self.allocator, options);
        try self.ptys.append(pty);
        return &self.ptys.items[self.ptys.items.len - 1];
    }

    /// Remove and cleanup a PTY
    pub fn removePty(self: *PtyManager, target_pty: *Pty) void {
        for (self.ptys.items, 0..) |*pty, i| {
            if (pty == target_pty) {
                pty.deinit();
                _ = self.ptys.swapRemove(i);
                break;
            }
        }
    }

    /// Get number of active PTYs
    pub fn count(self: *PtyManager) usize {
        return self.ptys.items.len;
    }
};

// Tests
test "PTY creation" {
    var pty = try Pty.init(std.testing.allocator, .{});
    defer pty.deinit();

    try std.testing.expect(pty.master_fd >= 0);
    try std.testing.expect(pty.slave_fd >= 0);
    try std.testing.expect(pty.slave_path.len > 0);
}

test "PTY window sizing" {
    var pty = try Pty.init(std.testing.allocator, .{ .rows = 30, .cols = 100 });
    defer pty.deinit();

    const size = try pty.getSize();
    try std.testing.expectEqual(@as(u16, 30), size.rows);
    try std.testing.expectEqual(@as(u16, 100), size.cols);

    // Test resize
    try pty.resize(40, 120);
    const new_size = try pty.getSize();
    try std.testing.expectEqual(@as(u16, 40), new_size.rows);
    try std.testing.expectEqual(@as(u16, 120), new_size.cols);
}

test "PTY manager" {
    var manager = PtyManager.init(std.testing.allocator);
    defer manager.deinit();

    const pty1 = try manager.createPty(.{});
    const pty2 = try manager.createPty(.{ .rows = 25, .cols = 90 });

    try std.testing.expectEqual(@as(usize, 2), manager.count());

    manager.removePty(pty1);
    try std.testing.expectEqual(@as(usize, 1), manager.count());

    const size = try pty2.getSize();
    try std.testing.expectEqual(@as(u16, 25), size.rows);
    try std.testing.expectEqual(@as(u16, 90), size.cols);
}

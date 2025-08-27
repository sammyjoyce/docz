const std = @import("std");
const os = std.os;
const posix = std.posix;
const linux = std.os.linux;
const builtin = @import("builtin");
const termios = @import("termios.zig");

// Windows ConPTY API declarations
const windows = std.os.windows;
const kernel32 = windows.kernel32;
const HRESULT = windows.HRESULT;
const HANDLE = windows.HANDLE;
const DWORD = windows.DWORD;
const BOOL = windows.BOOL;

// ConPTY specific types
const HPCON = *opaque {}; // Pseudo console handle
const COORD = extern struct {
    X: i16,
    Y: i16,
};

// Windows API function declarations for ConPTY
extern "kernel32" fn CreatePipe(
    hReadPipe: *HANDLE,
    hWritePipe: *HANDLE,
    lpPipeAttributes: ?*const anyopaque,
    nSize: DWORD,
) callconv(windows.WINAPI) BOOL;

extern "kernel32" fn CreatePseudoConsole(
    size: COORD,
    hInput: HANDLE,
    hOutput: HANDLE,
    dwFlags: DWORD,
    phPC: *HPCON,
) callconv(windows.WINAPI) HRESULT;

extern "kernel32" fn ResizePseudoConsole(
    hPC: HPCON,
    size: COORD,
) callconv(windows.WINAPI) HRESULT;

extern "kernel32" fn ClosePseudoConsole(
    hPC: HPCON,
) callconv(windows.WINAPI) void;

extern "kernel32" fn CreateProcessW(
    lpApplicationName: ?[*:0]const u16,
    lpCommandLine: ?[*:0]u16,
    lpProcessAttributes: ?*const anyopaque,
    lpThreadAttributes: ?*const anyopaque,
    bInheritHandles: BOOL,
    dwCreationFlags: DWORD,
    lpEnvironment: ?*const anyopaque,
    lpCurrentDirectory: ?[*:0]const u16,
    lpStartupInfo: *windows.STARTUPINFOW,
    lpProcessInformation: *windows.PROCESS_INFORMATION,
) callconv(windows.WINAPI) BOOL;

// Cross-platform PTY (Pseudo-Terminal) interface
// Advanced PTY implementation with modern terminal features
//
// Provides a unified interface for creating and managing pseudo-terminals
// across Unix-like systems and Windows (ConPTY support planned).

/// PTY error types
pub const PtyInstanceError = error{
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
    /// Access denied
    AccessDenied,
    /// File not found
    FileNotFound,
    /// Broken pipe
    BrokenPipe,
};

/// PTY configuration options
pub const PtyInstanceOptions = struct {
    /// Initial window size
    rows: u16 = 24,
    cols: u16 = 80,
    /// Initial pixel dimensions
    xpixel: u16 = 0,
    ypixel: u16 = 0,
    /// Working directory for spawned process
    cwd: ?[]const u8 = null,
    /// Environment variables (null means inherit)
    env: ?std.process.EnvMap = null,
    /// Terminal type (TERM environment variable)
    term: []const u8 = "xterm-256color",
    /// Whether to create a controlling terminal
    controlling_terminal: bool = true,
    /// Additional flags for PTY creation
    flags: PtyInstanceFlags = .{},

    pub const PtyInstanceFlags = packed struct {
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

/// Functional option type for configuring PTY options
pub const PtyInstanceOption = union(enum) {
    rows: u16,
    cols: u16,
    cwd: []const u8,
    env: std.process.EnvMap,
    term: []const u8,
    controlling_terminal: bool,
    pixels: struct { xpixel: u16, ypixel: u16 },
    utf8: bool,
    winsize_reporting: bool,
    echo: bool,
    raw_mode: bool,
};

/// Create default PTY options
pub fn defaultPtyInstanceOptions() PtyInstanceOptions {
    return PtyInstanceOptions{};
}

/// Set the number of rows for the PTY
pub fn withRows(rows: u16) PtyInstanceOption {
    return .{ .rows = rows };
}

/// Set the number of columns for the PTY
pub fn withCols(cols: u16) PtyInstanceOption {
    return .{ .cols = cols };
}

/// Set the working directory for the PTY
pub fn withCwd(cwd: []const u8) PtyInstanceOption {
    return .{ .cwd = cwd };
}

/// Set the environment variables for the PTY
pub fn withEnv(env: std.process.EnvMap) PtyInstanceOption {
    return .{ .env = env };
}

/// Set the terminal type for the PTY
pub fn withTerm(term: []const u8) PtyInstanceOption {
    return .{ .term = term };
}

/// Set whether to create a controlling terminal
pub fn withControllingTerminal(controlling_terminal: bool) PtyInstanceOption {
    return .{ .controlling_terminal = controlling_terminal };
}

/// Set the pixel dimensions for the PTY
pub fn withPixels(xpixel: u16, ypixel: u16) PtyInstanceOption {
    return .{ .pixels = .{ .xpixel = xpixel, .ypixel = ypixel } };
}

/// Set UTF-8 support flag
pub fn withUtf8(utf8: bool) PtyInstanceOption {
    return .{ .utf8 = utf8 };
}

/// Set window size reporting flag
pub fn withWinsizeReporting(winsize_reporting: bool) PtyInstanceOption {
    return .{ .winsize_reporting = winsize_reporting };
}

/// Set echo flag
pub fn withEcho(echo: bool) PtyInstanceOption {
    return .{ .echo = echo };
}

/// Set raw mode flag
pub fn withRawMode(raw_mode: bool) PtyInstanceOption {
    return .{ .raw_mode = raw_mode };
}

/// Apply functional options to PTY options
fn applyOptions(base_options: PtyInstanceOptions, options: []PtyInstanceOption) PtyInstanceOptions {
    var result = base_options;
    for (options) |option| {
        switch (option) {
            .rows => |rows| result.rows = rows,
            .cols => |cols| result.cols = cols,
            .cwd => |cwd| result.cwd = cwd,
            .env => |env| result.env = env,
            .term => |term| result.term = term,
            .controlling_terminal => |controlling_terminal| result.controlling_terminal = controlling_terminal,
            .pixels => |pixels| {
                result.xpixel = pixels.xpixel;
                result.ypixel = pixels.ypixel;
            },
            .utf8 => |utf8| result.flags.utf8 = utf8,
            .winsize_reporting => |winsize_reporting| result.flags.winsize_reporting = winsize_reporting,
            .echo => |echo| result.flags.echo = echo,
            .raw_mode => |raw_mode| result.flags.raw_mode = raw_mode,
        }
    }
    return result;
}

/// Represents a PTY master/slave pair
pub const PtyInstance = struct {
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

    /// Create a new PTY pair with functional options
    pub fn init(allocator: std.mem.Allocator, options: []PtyInstanceOption) PtyInstanceError!PtyInstance {
        const pty_options = applyOptions(defaultPtyInstanceOptions(), options);
        return initWithOptions(allocator, pty_options);
    }

    /// Create a new PTY pair with explicit options (legacy compatibility)
    pub fn initWithOptions(allocator: std.mem.Allocator, options: PtyInstanceOptions) PtyInstanceError!PtyInstance {
        const result = createPtyInstancePair(allocator, options) catch |err| switch (err) {
            error.OutOfMemory => return PtyInstanceError.OutOfMemory,
            error.AccessDenied => return PtyInstanceError.AccessDenied,
            error.FileNotFound => return PtyInstanceError.FileNotFound,
            error.InvalidArgument => return PtyInstanceError.InvalidArgument,
            else => return PtyInstanceError.CreateFailed,
        };

        var pty = PtyInstance{
            .master_fd = result.master_fd,
            .slave_fd = result.slave_fd,
            .slave_path = result.slave_path,
            .allocator = allocator,
            .window_size = .{
                .rows = options.rows,
                .cols = options.cols,
                .xpixel = options.xpixel,
                .ypixel = options.ypixel,
            },
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
    pub fn deinit(self: *PtyInstance) void {
        // Restore original terminal settings if saved
        if (self.original_termios) |config| {
            termios.restoreMode(self.slave_fd, config) catch {};
        }

        // Terminate process if running
        if (self.process) |*proc| {
            _ = proc.kill() catch {};
            _ = proc.wait() catch {};

            // Close ConPTY handle on Windows
            if (builtin.target.os.tag == .windows) {
                const conpty_handle = @as(HPCON, @ptrCast(proc.thread_handle));
                ClosePseudoConsole(conpty_handle);
            }
        }

        // Close file descriptors
        switch (builtin.target.os.tag) {
            .windows => {
                // On Windows, close the handles directly
                if (self.master_fd != 0) {
                    kernel32.CloseHandle(@as(HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, self.master_fd))))));
                }
                if (self.slave_fd != 0 and self.slave_fd != self.master_fd) {
                    kernel32.CloseHandle(@as(HANDLE, @ptrFromInt(@as(usize, @bitCast(@as(isize, self.slave_fd))))));
                }
            },
            else => {
                posix.close(self.master_fd);
                if (self.slave_fd != self.master_fd) {
                    posix.close(self.slave_fd);
                }
            },
        }

        // Free slave path
        self.allocator.free(self.slave_path);
    }

    /// Spawn a command in the PTY
    pub fn spawn(self: *PtyInstance, argv: []const []const u8, options: PtyInstanceOptions) PtyInstanceError!void {
        if (self.process != null) {
            return PtyInstanceError.InvalidArgument; // Process already spawned
        }

        switch (builtin.target.os.tag) {
            .windows => {
                return self.spawnWindows(argv, options);
            },
            else => {
                return self.spawnUnix(argv, options);
            },
        }
    }

    /// Spawn a command in a Unix PTY
    fn spawnUnix(self: *PtyInstance, argv: []const []const u8, options: PtyInstanceOptions) PtyInstanceError!void {
        // Fork the process manually to properly set up PTY file descriptors
        const pid = posix.fork() catch return PtyInstanceError.ForkFailed;

        if (pid == 0) {
            // Child process
            // Set up the slave PTY as stdin, stdout, stderr
            posix.dup2(self.slave_fd, posix.STDIN_FILENO) catch posix.exit(1);
            posix.dup2(self.slave_fd, posix.STDOUT_FILENO) catch posix.exit(1);
            posix.dup2(self.slave_fd, posix.STDERR_FILENO) catch posix.exit(1);

            // Close the master FD in child
            posix.close(self.master_fd);

            // Set working directory if specified
            if (options.cwd) |cwd| {
                posix.chdir(cwd) catch posix.exit(1);
            }

            // TODO: Implement environment variable setting
            // For now, environment variables are inherited from parent process
            _ = options.env;

            // Execute the command
            const argv_z = self.allocator.allocSentinel(?[*:0]const u8, argv.len, null) catch posix.exit(1);
            defer self.allocator.free(argv_z);

            for (argv, 0..) |arg, i| {
                const arg_z = std.fmt.allocPrint(self.allocator, "{s}\x00", .{arg}) catch posix.exit(1);
                argv_z[i] = @ptrCast(arg_z.ptr);
            }
            argv_z[argv.len] = null;

            // Use inherited environment
            posix.execvpeZ(argv_z[0].?, argv_z, std.c.environ) catch posix.exit(1);
        } else {
            // Parent process
            self.process = std.process.Child{
                .id = pid,
                .allocator = self.allocator,
                .argv = argv,
                .stdin_behavior = .Ignore,
                .stdout_behavior = .Ignore,
                .stderr_behavior = .Ignore,
                .stdin = null,
                .stdout = null,
                .stderr = null,
                .thread_handle = undefined,
                .err_pipe = null,
                .term = null,
                .cwd_dir = null,
                .env_map = if (options.env) |*env| env else null,
                .progress_node = .{ .index = .none },
                .uid = null,
                .gid = null,
                .pgid = null,
                .cwd = if (options.cwd) |cwd| cwd else null,
                .expand_arg0 = .no_expand,
            };
        }
    }

    /// Spawn a command in a Windows ConPTY
    fn spawnWindows(self: *PtyInstance, argv: []const []const u8, options: PtyInstanceOptions) PtyInstanceError!void {
        if (argv.len == 0) {
            return PtyInstanceError.InvalidArgument;
        }

        // Get the ConPTY handle from the stored process
        const conpty_handle = @as(HPCON, @ptrCast(self.process.?.thread_handle));

        // Build command line
        var cmd_line = std.ArrayList(u16).init(self.allocator);
        defer cmd_line.deinit();

        for (argv, 0..) |arg, i| {
            if (i > 0) {
                try cmd_line.append(' ');
            }
            // Simple quoting - in a real implementation you'd want proper shell quoting
            if (std.mem.indexOfAny(u8, arg, " \t\"") != null) {
                try cmd_line.append('"');
                for (arg) |c| {
                    if (c == '"') {
                        try cmd_line.appendSlice(&[_]u16{ '"', '"' });
                    } else {
                        try cmd_line.append(c);
                    }
                }
                try cmd_line.append('"');
            } else {
                for (arg) |c| {
                    try cmd_line.append(c);
                }
            }
        }
        try cmd_line.append(0); // Null terminator

        // Prepare startup info
        var startup_info: windows.STARTUPINFOW = undefined;
        std.mem.set(u8, std.mem.asBytes(&startup_info), 0);
        startup_info.cb = @sizeOf(windows.STARTUPINFOW);
        startup_info.dwFlags |= windows.STARTF_USESTDHANDLES;
        startup_info.hStdInput = self.slave_fd; // This should be the input pipe
        startup_info.hStdOutput = self.master_fd; // This should be the output pipe
        startup_info.hStdError = self.master_fd; // Same as stdout for now
        startup_info.dwFlags |= windows.STARTF_USESHOWWINDOW;
        startup_info.wShowWindow = windows.SW_HIDE;

        // Set up ConPTY in startup info
        startup_info.lpAttributeList = @ptrCast(conpty_handle);

        var process_info: windows.PROCESS_INFORMATION = undefined;

        // Create the process
        const cwd_utf16 = if (options.cwd) |cwd| blk: {
            const utf16 = try std.unicode.utf8ToUtf16LeAlloc(self.allocator, cwd);
            break :blk @as(?[*:0]const u16, @ptrCast(utf16.ptr));
        } else null;
        defer if (cwd_utf16) |cwd| self.allocator.free(std.mem.span(@as([*:0]const u16, @ptrCast(cwd))));

        const success = CreateProcessW(
            null, // lpApplicationName
            cmd_line.items.ptr, // lpCommandLine
            null, // lpProcessAttributes
            null, // lpThreadAttributes
            windows.TRUE, // bInheritHandles
            windows.CREATE_UNICODE_ENVIRONMENT | windows.EXTENDED_STARTUPINFO_PRESENT, // dwCreationFlags
            null, // lpEnvironment
            cwd_utf16, // lpCurrentDirectory
            &startup_info, // lpStartupInfo
            &process_info, // lpProcessInformation
        );

        if (success == 0) {
            return PtyInstanceError.ExecFailed;
        }

        // Update process information
        self.process = std.process.Child{
            .id = @intCast(process_info.dwProcessId),
            .allocator = self.allocator,
            .argv = argv,
            .stdin_behavior = .Ignore,
            .stdout_behavior = .Ignore,
            .stderr_behavior = .Ignore,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .thread_handle = process_info.hThread,
            .err_pipe = null,
            .term = null,
            .cwd_dir = null,
            .env_map = if (options.env) |*env| env else null,
            .progress_node = .{ .index = .none },
            .uid = null,
            .gid = null,
            .pgid = null,
            .cwd = if (options.cwd) |cwd| cwd else null,
            .expand_arg0 = .no_expand,
        };

        // Close the process handle we don't need
        kernel32.CloseHandle(process_info.hProcess);
    }

    /// Read data from PTY master
    pub fn read(self: *PtyInstance, buffer: []u8) PtyInstanceError!usize {
        const bytes_read = os.read(self.master_fd, buffer) catch |err| switch (err) {
            error.WouldBlock => return 0,
            error.AccessDenied => return PtyInstanceError.PermissionDenied,
            error.BrokenPipe, error.ConnectionResetByPeer => return 0,
            else => return PtyInstanceError.SystemError,
        };

        return bytes_read;
    }

    /// Write data to PTY master
    pub fn write(self: *PtyInstance, data: []const u8) PtyInstanceError!usize {
        const bytes_written = os.write(self.master_fd, data) catch |err| switch (err) {
            error.WouldBlock => return 0,
            error.AccessDenied => return PtyInstanceError.PermissionDenied,
            error.BrokenPipe, error.ConnectionResetByPeer => return 0,
            else => return PtyInstanceError.SystemError,
        };

        return bytes_written;
    }

    /// Resize the PTY window
    pub fn resize(self: *PtyInstance, rows: u16, cols: u16) PtyInstanceError!void {
        self.window_size.rows = rows;
        self.window_size.cols = cols;
        // Keep existing pixel dimensions

        switch (builtin.target.os.tag) {
            .windows => {
                return self.resizeWindows(rows, cols);
            },
            else => {
                return self.resizeUnix(rows, cols);
            },
        }
    }

    /// Resize Unix PTY window
    fn resizeUnix(self: *PtyInstance, rows: u16, cols: u16) PtyInstanceError!void {
        self.window_size.rows = rows;
        self.window_size.cols = cols;
        termios.setWinsize(self.master_fd, self.window_size) catch |err| switch (err) {
            termios.TermiosError.InvalidFd => return PtyInstanceError.InvalidArgument,
            termios.TermiosError.NotSupported => return PtyInstanceError.NotSupported,
            else => return PtyInstanceError.SystemError,
        };

        // Send SIGWINCH to process if running
        if (self.process) |proc| {
            posix.kill(proc.id, posix.SIG.WINCH) catch {};
        }
    }

    /// Resize Windows ConPTY window
    fn resizeWindows(self: *PtyInstance, rows: u16, cols: u16) PtyInstanceError!void {
        if (self.process) |proc| {
            const conpty_handle = @as(HPCON, @ptrCast(proc.thread_handle));
            var size: COORD = undefined;
            size.X = @as(i16, @intCast(cols));
            size.Y = @as(i16, @intCast(rows));
            const hr = ResizePseudoConsole(conpty_handle, size);
            if (hr < 0) {
                return PtyInstanceError.SystemError;
            }
        }
    }

    /// Resize the PTY window with pixel dimensions
    pub fn resizeWithPixels(self: *PtyInstance, rows: u16, cols: u16, xpixel: u16, ypixel: u16) PtyInstanceError!void {
        self.window_size.rows = rows;
        self.window_size.cols = cols;
        self.window_size.xpixel = xpixel;
        self.window_size.ypixel = ypixel;

        switch (builtin.target.os.tag) {
            .windows => {
                return self.resizeWindows(rows, cols);
            },
            else => {
                return self.resizeUnixWithPixels(rows, cols, xpixel, ypixel);
            },
        }
    }

    /// Resize Unix PTY window with pixel dimensions
    fn resizeUnixWithPixels(self: *PtyInstance, rows: u16, cols: u16, xpixel: u16, ypixel: u16) PtyInstanceError!void {
        // Note: Unix PTYs don't use pixel dimensions in the same way
        // We store them for compatibility but don't use them in the actual resize
        self.window_size.rows = rows;
        self.window_size.cols = cols;
        // Pixel dimensions are stored but not used in Unix PTY resize
        _ = xpixel;
        _ = ypixel;

        termios.setWinsize(self.master_fd, self.window_size) catch |err| switch (err) {
            termios.TermiosError.InvalidFd => return PtyInstanceError.InvalidArgument,
            termios.TermiosError.NotSupported => return PtyInstanceError.NotSupported,
            else => return PtyInstanceError.SystemError,
        };

        // Send SIGWINCH to process if running
        if (self.process) |proc| {
            posix.kill(proc.id, posix.SIG.WINCH) catch {};
        }
    }

    /// Get current window size
    pub fn getSize(self: *PtyInstance) PtyInstanceError!termios.Winsize {
        const winsize = termios.getWinsize(self.master_fd) catch |err| switch (err) {
            termios.TermiosError.InvalidFd => return PtyInstanceError.InvalidArgument,
            termios.TermiosError.NotSupported => return PtyInstanceError.NotSupported,
            else => return PtyInstanceError.SystemError,
        };

        return winsize;
    }

    /// Get the slave device path
    pub fn getSlavePath(self: *PtyInstance) []const u8 {
        return self.slave_path;
    }

    /// Get the slave device name (alias for getSlavePath)
    pub fn slaveName(self: *PtyInstance) []const u8 {
        return self.slave_path;
    }

    /// Get the master file descriptor (alias for Control)
    pub fn master(self: *PtyInstance) posix.fd_t {
        return self.master_fd;
    }

    /// Get the master file descriptor (alias for Master)
    pub fn control(self: *PtyInstance) posix.fd_t {
        return self.master_fd;
    }

    /// Get the master file descriptor (primary file descriptor)
    pub fn fd(self: *PtyInstance) posix.fd_t {
        return self.master_fd;
    }

    /// Get the slave file descriptor
    pub fn slave(self: *PtyInstance) posix.fd_t {
        return self.slave_fd;
    }

    /// Check if the spawned process is still running
    pub fn isRunning(self: *PtyInstance) bool {
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
    pub fn wait(self: *PtyInstance) PtyInstanceError!std.process.Child.Term {
        if (self.process) |*proc| {
            const term = proc.wait() catch |err| switch (err) {
                error.ChildAlreadyReaped => return std.process.Child.Term{ .Exited = 0 },
                else => return PtyInstanceError.SystemError,
            };
            return term;
        }
        return PtyInstanceError.InvalidArgument;
    }

    /// Set PTY to non-blocking mode
    pub fn setNonBlocking(self: *PtyInstance, non_blocking: bool) PtyInstanceError!void {
        const flags = posix.fcntl(self.master_fd, posix.F.GETFL, 0) catch return PtyInstanceError.SystemError;
        const new_flags = if (non_blocking) flags | @as(u32, posix.O.NONBLOCK) else flags & ~@as(u32, posix.O.NONBLOCK);
        _ = posix.fcntl(self.master_fd, posix.F.SETFL, new_flags) catch return PtyInstanceError.SystemError;
    }
};

/// Cross-platform PTY constructor
/// Detects the platform and returns the appropriate PTY implementation
pub fn newPtyInstance(allocator: std.mem.Allocator, options: []PtyInstanceOption) PtyInstanceError!PtyInstance {
    switch (builtin.target.os.tag) {
        .linux, .macos, .freebsd, .openbsd, .netbsd, .dragonfly => {
            return UnixPtyInstance.init(allocator, options);
        },
        .windows => {
            return WindowsPtyInstance.init(allocator, options);
        },
        else => {
            return PtyInstanceError.NotSupported;
        },
    }
}

/// Unix-specific PTY implementation
pub const UnixPtyInstance = struct {
    /// Create a new Unix PTY pair with functional options
    pub fn init(allocator: std.mem.Allocator, options: []PtyInstanceOption) PtyInstanceError!PtyInstance {
        return PtyInstance.init(allocator, options);
    }

    /// Create a new Unix PTY pair with explicit options
    pub fn initWithOptions(allocator: std.mem.Allocator, options: PtyInstanceOptions) PtyInstanceError!PtyInstance {
        return PtyInstance.initWithOptions(allocator, options);
    }
};

/// Windows ConPTY implementation using Windows Console Host APIs
pub const WindowsPtyInstance = struct {
    /// Create a new Windows ConPTY with functional options
    pub fn init(allocator: std.mem.Allocator, options: []PtyInstanceOption) PtyInstanceError!PtyInstance {
        const pty_options = applyOptions(defaultPtyInstanceOptions(), options);
        return initWithOptions(allocator, pty_options);
    }

    /// Create a new Windows ConPTY with explicit options
    pub fn initWithOptions(allocator: std.mem.Allocator, options: PtyInstanceOptions) PtyInstanceError!PtyInstance {
        const result = createConPtyInstancePair(allocator, options) catch |err| switch (err) {
            error.OutOfMemory => return PtyInstanceError.OutOfMemory,
            error.AccessDenied => return PtyInstanceError.AccessDenied,
            error.InvalidArgument => return PtyInstanceError.InvalidArgument,
            else => return PtyInstanceError.CreateFailed,
        };

        var pty = PtyInstance{
            .master_fd = result.master_fd,
            .slave_fd = result.slave_fd,
            .slave_path = result.slave_path,
            .allocator = allocator,
            .window_size = .{
                .rows = options.rows,
                .cols = options.cols,
                .xpixel = options.xpixel,
                .ypixel = options.ypixel,
            },
        };

        // Store ConPTY handle for later use
        pty.process = std.process.Child{
            .id = 0, // Will be set when process is spawned
            .allocator = allocator,
            .argv = &[_][]const u8{}, // Will be set when process is spawned
            .stdin_behavior = .Ignore,
            .stdout_behavior = .Ignore,
            .stderr_behavior = .Ignore,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .thread_handle = result.conpty_handle,
            .err_pipe = null,
            .term = null,
            .cwd_dir = null,
            .env_map = null,
            .progress_node = .{ .index = .none },
            .uid = null,
            .gid = null,
            .pgid = null,
            .cwd = if (options.cwd) |cwd| cwd else null,
            .expand_arg0 = .no_expand,
        };

        return pty;
    }
};

/// Create a PTY master/slave pair
fn createPtyInstancePair(allocator: std.mem.Allocator, options: PtyInstanceOptions) !struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    slave_path: []u8,
} {
    _ = options; // TODO: Use options for configuration

    // Open /dev/ptmx (master PTY multiplexer)
    const master_fd = posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR }, 0) catch |err| switch (err) {
        error.AccessDenied => return PtyInstanceError.PermissionDenied,
        error.FileNotFound => return PtyInstanceError.NotSupported, // No PTY support
        else => return PtyInstanceError.CreateFailed,
    };

    errdefer posix.close(master_fd);

    // Grant access to the slave PTY
    if (grantpt(master_fd) != 0) {
        return PtyInstanceError.CreateFailed;
    }

    // Unlock the slave PTY
    if (unlockpt(master_fd) != 0) {
        return PtyInstanceError.CreateFailed;
    }

    // Get the slave PTY name
    const slave_path = try getPtyInstanceName(allocator, master_fd);
    errdefer allocator.free(slave_path);

    // Open the slave PTY
    const slave_fd = posix.open(slave_path, .{ .ACCMODE = .RDWR }, 0) catch |err| switch (err) {
        error.AccessDenied => return PtyInstanceError.PermissionDenied,
        else => return PtyInstanceError.CreateFailed,
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
    // Placeholder implementation - in a real implementation this would use proper ioctl
    _ = master_fd;
    return 0;
}

/// Unlock the slave PTY (Unix-specific)
fn unlockpt(master_fd: posix.fd_t) c_int {
    // Placeholder implementation - in a real implementation this would use proper ioctl
    _ = master_fd;
    return 0;
}

/// Get the slave PTY device name
fn getPtyInstanceName(allocator: std.mem.Allocator, master_fd: posix.fd_t) ![]u8 {
    // Placeholder implementation - in a real implementation this would get the actual PTY number
    _ = master_fd;
    return try std.fmt.allocPrint(allocator, "/dev/pts/{d}", .{0});
}

/// Create a Windows ConPTY pair
fn createConPtyInstancePair(allocator: std.mem.Allocator, options: PtyInstanceOptions) !struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    slave_path: []u8,
    conpty_handle: HANDLE,
} {
    // Create pipes for stdin, stdout, stderr
    var input_read: HANDLE = undefined;
    var input_write: HANDLE = undefined;
    var output_read: HANDLE = undefined;
    var output_write: HANDLE = undefined;

    // Create input pipe (stdin for child process)
    if (CreatePipe(&input_read, &input_write, null, 0) == 0) {
        return error.AccessDenied;
    }
    errdefer kernel32.CloseHandle(input_read);
    errdefer kernel32.CloseHandle(input_write);

    // Create output pipe (stdout for child process)
    if (CreatePipe(&output_read, &output_write, null, 0) == 0) {
        return error.AccessDenied;
    }
    errdefer kernel32.CloseHandle(output_read);
    errdefer kernel32.CloseHandle(output_write);

    // Create ConPTY
    const size = COORD{
        .X = @intCast(options.cols),
        .Y = @intCast(options.rows),
    };

    var conpty_handle: HPCON = undefined;
    const hr = CreatePseudoConsole(size, input_read, output_write, 0, &conpty_handle);
    if (hr < 0) {
        return error.CreateFailed;
    }
    errdefer ClosePseudoConsole(conpty_handle);

    // Convert Windows handles to file descriptors for compatibility
    // Note: This is a simplified approach. In a real implementation,
    // you might want to use different strategies for handle management
    const master_fd = @as(posix.fd_t, @bitCast(@as(isize, @intFromPtr(output_read))));
    const slave_fd = @as(posix.fd_t, @bitCast(@as(isize, @intFromPtr(input_write))));

    // Create a virtual slave path for compatibility
    const slave_path = try std.fmt.allocPrint(allocator, "\\\\.\\pipe\\conpty-{d}", .{std.crypto.random.int(u64)});

    return .{
        .master_fd = master_fd,
        .slave_fd = slave_fd,
        .slave_path = slave_path,
        .conpty_handle = @as(HANDLE, @ptrCast(conpty_handle)),
    };
}

/// Convenience function to spawn a shell in a PTY with functional options
pub fn spawnShell(allocator: std.mem.Allocator, options: []PtyInstanceOption) PtyInstanceError!PtyInstance {
    const pty_options = applyOptions(defaultPtyInstanceOptions(), options);
    return spawnShellWithOptions(allocator, pty_options);
}

/// Convenience function to spawn a shell in a PTY with explicit options (legacy compatibility)
pub fn spawnShellWithOptions(allocator: std.mem.Allocator, options: PtyInstanceOptions) PtyInstanceError!PtyInstance {
    var pty = try PtyInstance.initWithOptions(allocator, options);
    errdefer pty.deinit();

    // Determine shell to use
    const shell = std.process.getEnvVarOwned(allocator, "SHELL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allocator.dupe(u8, "/bin/sh"),
        else => return PtyInstanceError.SystemError,
    };
    defer allocator.free(shell);

    const argv = [_][]const u8{shell};
    try pty.spawn(&argv, options);

    return pty;
}

/// High-level PTY manager for common use cases
pub const Pty = struct {
    allocator: std.mem.Allocator,
    ptys: std.ArrayList(PtyInstance),

    pub fn init(allocator: std.mem.Allocator) Pty {
        return Pty{
            .allocator = allocator,
            .ptys = std.ArrayList(PtyInstance).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Pty) void {
        for (self.ptys.items) |*pty| {
            pty.deinit();
        }
        self.ptys.deinit(self.allocator);
    }

    /// Create and register a new PTY with functional options
    pub fn createPtyInstance(self: *Pty, options: []PtyInstanceOption) PtyInstanceError!*PtyInstance {
        const pty = try PtyInstance.init(self.allocator, options);
        try self.ptys.append(self.allocator, pty);
        return &self.ptys.items[self.ptys.items.len - 1];
    }

    /// Create and register a new PTY with explicit options (legacy compatibility)
    pub fn createPtyInstanceWithOptions(self: *Pty, options: PtyInstanceOptions) PtyInstanceError!*PtyInstance {
        const pty = try PtyInstance.initWithOptions(self.allocator, options);
        try self.ptys.append(self.allocator, pty);
        return &self.ptys.items[self.ptys.items.len - 1];
    }

    /// Create and spawn shell in new PTY with functional options
    pub fn createShell(self: *Pty, options: []const PtyInstanceOption) PtyInstanceError!*PtyInstance {
        const pty = try spawnShell(self.allocator, options);
        try self.ptys.append(self.allocator, pty);
        return &self.ptys.items[self.ptys.items.len - 1];
    }

    /// Create and spawn shell in new PTY with explicit options (legacy compatibility)
    pub fn createShellWithOptions(self: *Pty, options: PtyInstanceOptions) PtyInstanceError!*PtyInstance {
        const pty = try spawnShellWithOptions(self.allocator, options);
        try self.ptys.append(self.allocator, pty);
        return &self.ptys.items[self.ptys.items.len - 1];
    }

    /// Remove and cleanup a PTY
    pub fn removePtyInstance(self: *Pty, target_pty: *PtyInstance) void {
        for (self.ptys.items, 0..) |*pty, i| {
            if (pty == target_pty) {
                pty.deinit();
                _ = self.ptys.swapRemove(i);
                break;
            }
        }
    }

    /// Get number of active PTYs
    pub fn count(self: *Pty) usize {
        return self.ptys.items.len;
    }
};

// Tests
test "PTY creation with functional options" {
    var pty = try PtyInstance.init(std.testing.allocator, &[_]PtyInstanceOption{});
    defer pty.deinit();

    try std.testing.expect(pty.master_fd >= 0);
    try std.testing.expect(pty.slave_fd >= 0);
    try std.testing.expect(pty.slave_path.len > 0);

    // Test file descriptor access methods
    try std.testing.expectEqual(pty.master_fd, pty.master());
    try std.testing.expectEqual(pty.master_fd, pty.control());
    try std.testing.expectEqual(pty.master_fd, pty.fd());
    try std.testing.expectEqual(pty.slave_fd, pty.slave());
    try std.testing.expectEqual(pty.slave_path, pty.slaveName());
}

test "PTY creation with explicit options (legacy)" {
    var pty = try PtyInstance.initWithOptions(std.testing.allocator, .{});
    defer pty.deinit();

    try std.testing.expect(pty.master_fd >= 0);
    try std.testing.expect(pty.slave_fd >= 0);
    try std.testing.expect(pty.slave_path.len > 0);
}

test "PTY functional options" {
    var options = [_]PtyInstanceOption{
        withRows(30),
        withCols(100),
        withPixels(800, 600),
        withCwd("/tmp"),
        withTerm("screen-256color"),
        withUtf8(true),
        withRawMode(true),
    };

    var pty = try PtyInstance.init(std.testing.allocator, options[0..]);
    defer pty.deinit();

    const size = try pty.getSize();
    try std.testing.expectEqual(@as(u16, 30), size.rows);
    try std.testing.expectEqual(@as(u16, 100), size.cols);
    try std.testing.expectEqual(@as(u16, 800), size.xpixel);
    try std.testing.expectEqual(@as(u16, 600), size.ypixel);
}

test "PTY window sizing" {
    var options = [_]PtyInstanceOption{
        withRows(30),
        withCols(100),
        withPixels(800, 600),
    };

    var pty = try PtyInstance.init(std.testing.allocator, options[0..]);
    defer pty.deinit();

    const size = try pty.getSize();
    try std.testing.expectEqual(@as(u16, 30), size.rows);
    try std.testing.expectEqual(@as(u16, 100), size.cols);
    try std.testing.expectEqual(@as(u16, 800), size.xpixel);
    try std.testing.expectEqual(@as(u16, 600), size.ypixel);

    // Test resize
    try pty.resize(40, 120);
    const new_size = try pty.getSize();
    try std.testing.expectEqual(@as(u16, 40), new_size.rows);
    try std.testing.expectEqual(@as(u16, 120), new_size.cols);

    // Test resize with pixels
    try pty.resizeWithPixels(50, 150, 1024, 768);
    const pixel_size = try pty.getSize();
    try std.testing.expectEqual(@as(u16, 50), pixel_size.rows);
    try std.testing.expectEqual(@as(u16, 150), pixel_size.cols);
    try std.testing.expectEqual(@as(u16, 1024), pixel_size.xpixel);
    try std.testing.expectEqual(@as(u16, 768), pixel_size.ypixel);
}

test "PTY manager with functional options" {
    var manager = Pty.init(std.testing.allocator);
    defer manager.deinit();

    const pty1 = try manager.createPtyInstance(&[_]PtyInstanceOption{});
    var pty2_options = [_]PtyInstanceOption{
        withRows(25),
        withCols(90),
        withPixels(640, 480),
    };
    const pty2 = try manager.createPtyInstance(pty2_options[0..]);

    try std.testing.expectEqual(@as(usize, 2), manager.count());

    manager.removePtyInstance(pty1);
    try std.testing.expectEqual(@as(usize, 1), manager.count());

    const size = try pty2.getSize();
    try std.testing.expectEqual(@as(u16, 25), size.rows);
    try std.testing.expectEqual(@as(u16, 90), size.cols);
    try std.testing.expectEqual(@as(u16, 640), size.xpixel);
    try std.testing.expectEqual(@as(u16, 480), size.ypixel);
}

test "PTY manager with explicit options (legacy)" {
    var manager = Pty.init(std.testing.allocator);
    defer manager.deinit();

    const pty1 = try manager.createPtyInstanceWithOptions(.{});
    const pty2 = try manager.createPtyInstanceWithOptions(.{ .rows = 25, .cols = 90, .xpixel = 640, .ypixel = 480 });

    try std.testing.expectEqual(@as(usize, 2), manager.count());

    manager.removePtyInstance(pty1);
    try std.testing.expectEqual(@as(usize, 1), manager.count());

    const size = try pty2.getSize();
    try std.testing.expectEqual(@as(u16, 25), size.rows);
    try std.testing.expectEqual(@as(u16, 90), size.cols);
    try std.testing.expectEqual(@as(u16, 640), size.xpixel);
    try std.testing.expectEqual(@as(u16, 480), size.ypixel);
}

test "spawnShell with functional options" {
    var options = [_]PtyInstanceOption{
        withRows(24),
        withCols(80),
        withTerm("xterm-256color"),
    };

    var pty = try spawnShell(std.testing.allocator, options[0..]);
    defer pty.deinit();

    try std.testing.expect(pty.master_fd >= 0);
    try std.testing.expect(pty.slave_fd >= 0);
    try std.testing.expect(pty.process != null);
}

test "spawnShell with explicit options (legacy)" {
    var pty = try spawnShellWithOptions(std.testing.allocator, .{ .rows = 24, .cols = 80 });
    defer pty.deinit();

    try std.testing.expect(pty.master_fd >= 0);
    try std.testing.expect(pty.slave_fd >= 0);
    try std.testing.expect(pty.process != null);
}

test "cross-platform constructor" {
    var options = [_]PtyInstanceOption{
        withRows(24),
        withCols(80),
    };

    var pty = try newPtyInstance(std.testing.allocator, options[0..]);
    defer pty.deinit();

    try std.testing.expect(pty.master_fd >= 0);
    try std.testing.expect(pty.slave_fd >= 0);
    try std.testing.expect(pty.slave_path.len > 0);
}

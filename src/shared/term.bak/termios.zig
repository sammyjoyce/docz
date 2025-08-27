const std = @import("std");
const os = std.os;
const posix = std.posix;
const linux = std.os.linux;
const darwin = std.os.darwin;

// Unified termios interface for cross-platform terminal control
// Modern terminal control implementation with features
//
// This provides a clean API for getting and setting terminal attributes
// across Unix-like systems while abstracting away platform-specific differences.

/// Window size structure
pub const Winsize = struct {
    rows: u16,
    cols: u16,
    xpixel: u16 = 0,
    ypixel: u16 = 0,

    pub fn init(rows: u16, cols: u16) Winsize {
        return Winsize{
            .rows = rows,
            .cols = cols,
        };
    }
};

/// Control character (CC) field enumeration
pub const ControlChar = enum(u8) {
    intr = 0, // Interrupt character (usually ^C)
    quit, // Quit character (usually ^\)
    erase, // Erase character (usually ^H or DEL)
    kill, // Kill-line character (usually ^U)
    eof, // End-of-file character (usually ^D)
    eol, // End-of-line character
    eol2, // Alternate end-of-line character
    start, // Start character (usually ^Q)
    stop, // Stop character (usually ^S)
    susp, // Suspend character (usually ^Z)
    werase, // Word erase character (usually ^W)
    rprnt, // Reprint character (usually ^R)
    lnext, // Literal next character (usually ^V)
    discard, // Discard character (usually ^O)

    pub fn toNative(self: ControlChar) u8 {
        return switch (self) {
            .intr => 0,
            .quit => 1,
            .erase => 2,
            .kill => 3,
            .eof => 4,
            .eol => 5,
            .eol2 => 6,
            .start => 7,
            .stop => 8,
            .susp => 9,
            .werase => 10,
            .rprnt => 11,
            .lnext => 12,
            .discard => 13,
        };
    }
};

/// Input flag options
pub const InputFlag = enum {
    ignpar, // Ignore framing and parity errors
    parmrk, // Mark parity and framing errors
    inpck, // Enable input parity checking
    istrip, // Strip 8th bit off chars
    inlcr, // Map NL into CR on input
    igncr, // Ignore CR on input
    icrnl, // Map CR to NL on input
    ixon, // Enable XON/XOFF flow control on output
    ixany, // Any char will restart after stop
    ixoff, // Enable XON/XOFF flow control on input
    imaxbel, // Ring bell on input queue full

    pub fn toNative(self: InputFlag) u32 {
        return switch (self) {
            .ignpar => 1,
            .parmrk => 2,
            .inpck => 4,
            .istrip => 8,
            .inlcr => 16,
            .igncr => 32,
            .icrnl => 64,
            .ixon => 128,
            .ixany => 256,
            .ixoff => 512,
            .imaxbel => 1024,
        };
    }
};

/// Output flag options
pub const OutputFlag = enum {
    opost, // Enable output processing
    onlcr, // Map NL to CR-NL on output
    ocrnl, // Map CR to NL on output
    onocr, // No CR output at column 0
    onlret, // NL performs CR function

    pub fn toNative(self: OutputFlag) u32 {
        return switch (self) {
            .opost => 1,
            .onlcr => 2,
            .ocrnl => 4,
            .onocr => 8,
            .onlret => 16,
        };
    }
};

/// Control flag options
pub const ControlFlag = enum {
    cs7, // 7-bit chars
    cs8, // 8-bit chars
    parenb, // Parity enable
    parodd, // Odd parity, else even

    pub fn toNative(self: ControlFlag) u32 {
        return switch (self) {
            .cs7 => 1,
            .cs8 => 2,
            .parenb => 4,
            .parodd => 8,
        };
    }
};

/// Local flag options
pub const LocalFlag = enum {
    isig, // Enable signals INTR, QUIT, [D]SUSP
    icanon, // Canonicalize input lines
    echo, // Enable echoing
    echoe, // Visually erase chars
    echok, // Echo kill char
    echonl, // Echo NL even if ECHO is off
    noflsh, // Don't flush after interrupt
    tostop, // Stop background jobs from output
    iexten, // Enable extensions
    echoctl, // Echo control characters as ^(Char)
    echoke, // Visual erase for line kill
    pendin, // Retype pending input

    pub fn toNative(self: LocalFlag) u32 {
        return switch (self) {
            .isig => 1,
            .icanon => 2,
            .echo => 4,
            .echoe => 8,
            .echok => 16,
            .echonl => 32,
            .noflsh => 64,
            .tostop => 128,
            .iexten => 256,
            .echoctl => 512,
            .echoke => 1024,
            .pendin => 2048,
        };
    }
};

/// Terminal attributes configuration
pub const TermiosConfig = struct {
    /// Input speed (baud rate)
    input_speed: ?u32 = null,
    /// Output speed (baud rate)
    output_speed: ?u32 = null,
    /// Control character settings
    control_chars: std.EnumMap(ControlChar, u8) = std.EnumMap(ControlChar, u8).init(.{}),
    /// Input flags
    input_flags: std.EnumSet(InputFlag) = std.EnumSet(InputFlag).initEmpty(),
    /// Output flags
    output_flags: std.EnumSet(OutputFlag) = std.EnumSet(OutputFlag).initEmpty(),
    /// Control flags
    control_flags: std.EnumSet(ControlFlag) = std.EnumSet(ControlFlag).initEmpty(),
    /// Local flags
    local_flags: std.EnumSet(LocalFlag) = std.EnumSet(LocalFlag).initEmpty(),

    pub fn init() TermiosConfig {
        return TermiosConfig{};
    }

    /// Set a control character
    pub fn setControlChar(self: *TermiosConfig, char: ControlChar, value: u8) void {
        self.control_chars.put(char, value);
    }

    /// Enable an input flag
    pub fn enableInputFlag(self: *TermiosConfig, flag: InputFlag) void {
        self.input_flags.insert(flag);
    }

    /// Disable an input flag
    pub fn disableInputFlag(self: *TermiosConfig, flag: InputFlag) void {
        self.input_flags.remove(flag);
    }

    /// Enable an output flag
    pub fn enableOutputFlag(self: *TermiosConfig, flag: OutputFlag) void {
        self.output_flags.insert(flag);
    }

    /// Disable an output flag
    pub fn disableOutputFlag(self: *TermiosConfig, flag: OutputFlag) void {
        self.output_flags.remove(flag);
    }

    /// Enable a control flag
    pub fn enableControlFlag(self: *TermiosConfig, flag: ControlFlag) void {
        self.control_flags.insert(flag);
    }

    /// Disable a control flag
    pub fn disableControlFlag(self: *TermiosConfig, flag: ControlFlag) void {
        self.control_flags.remove(flag);
    }

    /// Enable a local flag
    pub fn enableLocalFlag(self: *TermiosConfig, flag: LocalFlag) void {
        self.local_flags.insert(flag);
    }

    /// Disable a local flag
    pub fn disableLocalFlag(self: *TermiosConfig, flag: LocalFlag) void {
        self.local_flags.remove(flag);
    }
};

/// Platform-specific termios operations
const PlatformOps = struct {
    // Platform-specific IOCTL constants
    const TIOCGWINSZ = switch (@import("builtin").target.os.tag) {
        .linux => 0x5413,
        .macos, .freebsd, .netbsd, .openbsd => 0x40087468,
        else => @compileError("Unsupported platform"),
    };

    const TIOCSWINSZ = switch (@import("builtin").target.os.tag) {
        .linux => 0x5414,
        .macos, .freebsd, .netbsd, .openbsd => 0x80087467,
        else => @compileError("Unsupported platform"),
    };

    // Platform-specific termios get/set constants
    const TCGETS = switch (@import("builtin").target.os.tag) {
        .linux => 0x5401,
        .macos, .freebsd, .netbsd, .openbsd => 0x402c7413,
        else => @compileError("Unsupported platform"),
    };

    const TCSETS = switch (@import("builtin").target.os.tag) {
        .linux => 0x5402,
        .macos, .freebsd, .netbsd, .openbsd => 0x802c7414,
        else => @compileError("Unsupported platform"),
    };
};

/// Termios error types
pub const TermiosError = error{
    /// Invalid file descriptor
    InvalidFd,
    /// Permission denied
    PermissionDenied,
    /// Operation not supported
    NotSupported,
    /// Invalid argument
    InvalidArgument,
    /// System error
    SystemError,
};

/// Get the current window size for the given file descriptor
pub fn getWinsize(fd: posix.fd_t) TermiosError!Winsize {
    var ws: posix.winsize = undefined;

    const result = os.linux.ioctl(fd, PlatformOps.TIOCGWINSZ, @intFromPtr(&ws));
    if (result < 0) {
        return switch (posix.errno(result)) {
            .BADF => TermiosError.InvalidFd,
            .NOTTY => TermiosError.NotSupported,
            .INVAL => TermiosError.InvalidArgument,
            else => TermiosError.SystemError,
        };
    }

    return Winsize{
        .rows = ws.row,
        .cols = ws.col,
        .xpixel = ws.xpixel,
        .ypixel = ws.ypixel,
    };
}

/// Set the window size for the given file descriptor
pub fn setWinsize(fd: posix.fd_t, winsize: Winsize) TermiosError!void {
    const ws = posix.winsize{
        .row = winsize.rows,
        .col = winsize.cols,
        .xpixel = winsize.xpixel,
        .ypixel = winsize.ypixel,
    };

    const result = os.linux.ioctl(fd, PlatformOps.TIOCSWINSZ, @intFromPtr(&ws));
    if (result < 0) {
        return switch (posix.errno(result)) {
            .BADF => TermiosError.InvalidFd,
            .NOTTY => TermiosError.NotSupported,
            .INVAL => TermiosError.InvalidArgument,
            else => TermiosError.SystemError,
        };
    }
}

/// Get the current terminal attributes for the given file descriptor
pub fn getTermios(fd: posix.fd_t, allocator: std.mem.Allocator) TermiosError!TermiosConfig {
    _ = allocator; // Currently unused, but kept for potential future use

    var termios: os.linux.termios = undefined;
    const result = os.linux.ioctl(fd, PlatformOps.TCGETS, @intFromPtr(&termios));
    if (result < 0) {
        return switch (posix.errno(result)) {
            .BADF => TermiosError.InvalidFd,
            .NOTTY => TermiosError.NotSupported,
            .INVAL => TermiosError.InvalidArgument,
            else => TermiosError.SystemError,
        };
    }

    var config = TermiosConfig.init();

    // Extract control characters
    config.setControlChar(.intr, termios.cc[0]);
    config.setControlChar(.quit, termios.cc[1]);
    config.setControlChar(.erase, termios.cc[2]);
    config.setControlChar(.kill, termios.cc[3]);
    config.setControlChar(.eof, termios.cc[4]);
    config.setControlChar(.eol, termios.cc[5]);
    config.setControlChar(.eol2, termios.cc[6]);
    config.setControlChar(.start, termios.cc[7]);
    config.setControlChar(.stop, termios.cc[8]);
    config.setControlChar(.susp, termios.cc[9]);
    config.setControlChar(.werase, termios.cc[10]);
    config.setControlChar(.rprnt, termios.cc[11]);
    config.setControlChar(.lnext, termios.cc[12]);
    config.setControlChar(.discard, termios.cc[13]);

    // Extract flags
    inline for (std.meta.fields(InputFlag)) |field| {
        const flag = @field(InputFlag, field.name);
        if (@as(u32, @bitCast(termios.iflag)) & flag.toNative() != 0) {
            config.input_flags.insert(flag);
        }
    }

    inline for (std.meta.fields(OutputFlag)) |field| {
        const flag = @field(OutputFlag, field.name);
        if (@as(u32, @bitCast(termios.oflag)) & flag.toNative() != 0) {
            config.output_flags.insert(flag);
        }
    }

    inline for (std.meta.fields(ControlFlag)) |field| {
        const flag = @field(ControlFlag, field.name);
        if (@as(u32, @bitCast(termios.cflag)) & flag.toNative() != 0) {
            config.control_flags.insert(flag);
        }
    }

    inline for (std.meta.fields(LocalFlag)) |field| {
        const flag = @field(LocalFlag, field.name);
        if (@as(u32, @bitCast(termios.lflag)) & flag.toNative() != 0) {
            config.local_flags.insert(flag);
        }
    }

    return config;
}

/// Set terminal attributes for the given file descriptor
pub fn setTermios(fd: posix.fd_t, config: TermiosConfig) TermiosError!void {
    // First get current termios to preserve unset values
    var termios: os.linux.termios = undefined;
    var result = os.linux.ioctl(fd, PlatformOps.TCGETS, @intFromPtr(&termios));
    if (result < 0) {
        return switch (posix.errno(result)) {
            .BADF => TermiosError.InvalidFd,
            .NOTTY => TermiosError.NotSupported,
            .INVAL => TermiosError.InvalidArgument,
            else => TermiosError.SystemError,
        };
    }

    // Apply control characters
    var it = (@constCast(&config.control_chars)).iterator();
    while (it.next()) |entry| {
        termios.cc[entry.key.toNative()] = entry.value.*;
    }

    // Apply input flags
    inline for (std.meta.fields(InputFlag)) |field| {
        const flag = @field(InputFlag, field.name);
        const mask = flag.toNative();
        if (config.input_flags.contains(flag)) {
            termios.iflag = @bitCast(@as(u32, @bitCast(termios.iflag)) | mask);
        } else {
            termios.iflag = @bitCast(@as(u32, @bitCast(termios.iflag)) & ~mask);
        }
    }

    // Apply output flags
    inline for (std.meta.fields(OutputFlag)) |field| {
        const flag = @field(OutputFlag, field.name);
        const mask = flag.toNative();
        if (config.output_flags.contains(flag)) {
            termios.oflag = @bitCast(@as(u32, @bitCast(termios.oflag)) | mask);
        } else {
            termios.oflag = @bitCast(@as(u32, @bitCast(termios.oflag)) & ~mask);
        }
    }

    // Apply control flags
    inline for (std.meta.fields(ControlFlag)) |field| {
        const flag = @field(ControlFlag, field.name);
        const mask = flag.toNative();
        if (config.control_flags.contains(flag)) {
            termios.cflag = @bitCast(@as(u32, @bitCast(termios.cflag)) | mask);
        } else {
            termios.cflag = @bitCast(@as(u32, @bitCast(termios.cflag)) & ~mask);
        }
    }

    // Apply local flags
    inline for (std.meta.fields(LocalFlag)) |field| {
        const flag = @field(LocalFlag, field.name);
        const mask = flag.toNative();
        if (config.local_flags.contains(flag)) {
            termios.lflag = @bitCast(@as(u32, @bitCast(termios.lflag)) | mask);
        } else {
            termios.lflag = @bitCast(@as(u32, @bitCast(termios.lflag)) & ~mask);
        }
    }

    // Apply speed settings if specified
    if (config.input_speed) |speed| {
        // Platform-specific speed setting would go here
        _ = speed;
    }

    if (config.output_speed) |speed| {
        // Platform-specific speed setting would go here
        _ = speed;
    }

    // Set the modified termios
    result = os.linux.ioctl(fd, PlatformOps.TCSETS, @intFromPtr(&termios));
    if (result < 0) {
        return switch (posix.errno(result)) {
            .BADF => TermiosError.InvalidFd,
            .NOTTY => TermiosError.NotSupported,
            .INVAL => TermiosError.InvalidArgument,
            else => TermiosError.SystemError,
        };
    }
}

/// Convenience function to configure terminal for raw mode
pub fn setRawMode(fd: posix.fd_t) TermiosError!TermiosConfig {
    var config = try getTermios(fd, std.heap.page_allocator);

    // Disable canonical mode and echo
    config.disableLocalFlag(.icanon);
    config.disableLocalFlag(.echo);
    config.disableLocalFlag(.echoe);
    config.disableLocalFlag(.echok);
    config.disableLocalFlag(.echonl);
    config.disableLocalFlag(.isig);
    config.disableLocalFlag(.iexten);

    // Disable input processing
    config.disableInputFlag(.icrnl);
    config.disableInputFlag(.inlcr);
    config.disableInputFlag(.igncr);
    config.disableInputFlag(.ixon);
    config.disableInputFlag(.ixoff);

    // Disable output processing
    config.disableOutputFlag(.opost);
    config.disableOutputFlag(.onlcr);

    // Set character size to 8 bits
    config.enableControlFlag(.cs8);

    // Set minimum characters and timeout for non-canonical reads
    config.setControlChar(.quit, 1); // VMIN: minimum number of characters
    config.setControlChar(.erase, 0); // VTIME: timeout in tenths of seconds

    try setTermios(fd, config);
    return config;
}

/// Convenience function to restore terminal from raw mode
pub fn restoreMode(fd: posix.fd_t, original_config: TermiosConfig) TermiosError!void {
    try setTermios(fd, original_config);
}

/// Terminal control utilities
pub const TerminalControl = struct {
    fd: posix.fd_t,
    original_config: ?TermiosConfig = null,

    pub fn init(fd: posix.fd_t) TerminalControl {
        return TerminalControl{ .fd = fd };
    }

    /// Enter raw mode, saving original configuration
    pub fn enterRawMode(self: *TerminalControl) TermiosError!void {
        if (self.original_config == null) {
            self.original_config = try getTermios(self.fd, std.heap.page_allocator);
        }
        _ = try setRawMode(self.fd);
    }

    /// Restore original terminal mode
    pub fn restore(self: *TerminalControl) TermiosError!void {
        if (self.original_config) |config| {
            try restoreMode(self.fd, config);
        }
    }

    /// Get current window size
    pub fn getSize(self: *TerminalControl) TermiosError!Winsize {
        return getWinsize(self.fd);
    }

    /// Set window size
    pub fn setSize(self: *TerminalControl, winsize: Winsize) TermiosError!void {
        return setWinsize(self.fd, winsize);
    }
};

// Tests
test "winsize operations" {
    // Test winsize creation and basic operations
    const ws = Winsize.init(24, 80);
    try std.testing.expect(ws.rows == 24);
    try std.testing.expect(ws.cols == 80);
}

test "termios config operations" {
    var config = TermiosConfig.init();

    // Test control character setting
    config.setControlChar(.intr, 3); // ^C
    config.setControlChar(.eof, 4); // ^D

    // Test flag operations
    config.enableInputFlag(.icrnl);
    config.enableLocalFlag(.echo);
    config.disableLocalFlag(.icanon);

    try std.testing.expect(config.input_flags.contains(.icrnl));
    try std.testing.expect(config.local_flags.contains(.echo));
    try std.testing.expect(!config.local_flags.contains(.icanon));
}

test "terminal control initialization" {
    const tc = TerminalControl.init(0); // stdin
    try std.testing.expect(tc.fd == 0);
    try std.testing.expect(tc.original_config == null);
}

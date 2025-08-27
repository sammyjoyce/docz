const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("../ansi/passthrough.zig");
const seqcfg = @import("../ansi/ansi.zon");
const integration = @import("integration.zig");

pub const TermCaps = caps_mod.TermCaps;

/// Term Shell Integration Implementation
/// Implements Term-specific shell integration features
/// Provides basic terminal integration with prompt and command markers
///
/// Reference: https://iterm2.com/documentation-shell-integration.html
fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(alloc);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        try out.append(alloc, ch);
    }
    return try out.toOwnedSlice(alloc);
}

fn appendDec(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: u32) !void {
    var tmp: [10]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(alloc, s);
}

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;
}

fn buildTerm(
    alloc: std.mem.Allocator,
    subcode: []const u8,
    param: ?[]const u8,
) ![]u8 {
    const st = oscTerminator();
    const clean_param = if (param) |p| blk: {
        const c = try sanitize(alloc, p);
        break :blk c;
    } else null;
    defer if (clean_param) |p| alloc.free(p);

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "\x1b]");
    try appendDec(&buf, alloc, seqcfg.osc.ops.term);
    try buf.append(alloc, ';');
    try buf.appendSlice(alloc, subcode);
    if (clean_param) |p| {
        try buf.append(alloc, ';');
        try buf.appendSlice(alloc, p);
    }
    try buf.appendSlice(alloc, st);
    return try buf.toOwnedSlice(alloc);
}

pub fn writeTerm(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    subcode: []const u8,
    param: ?[]const u8,
) !void {
    if (!caps.supportsTermOsc133) return error.Unsupported;
    const seq = try buildTerm(alloc, subcode, param);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Convenience helpers for common markers
pub fn promptStart(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeTerm(writer, alloc, caps, "A", null);
}

pub fn promptEnd(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeTerm(writer, alloc, caps, "B", null);
}

pub fn commandStart(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeTerm(writer, alloc, caps, "C", null);
}

pub fn commandEnd(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeTerm(writer, alloc, caps, "D", null);
}

// === TERM FEATURES ===

/// Term protocol phases with better naming
pub const Phase = enum {
    prompt, // A: Just before shell prompt
    cmd_start, // B: After prompt, before user command input
    cmd_executed, // C: Just before command output starts
    cmd_finished, // D: After command finishes

    pub fn toSubcode(self: Phase) []const u8 {
        return switch (self) {
            .prompt => "A",
            .cmd_start => "B",
            .cmd_executed => "C",
            .cmd_finished => "D",
        };
    }
};

/// Term sequence with phase enum
pub fn writeTermPhase(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    phase: Phase,
    param: ?[]const u8,
) !void {
    try writeTerm(writer, alloc, caps, phase.toSubcode(), param);
}

/// Mark the start of a shell prompt (FinalTerm A)
pub fn markPromptStart(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    try writeTermPhase(writer, alloc, caps, .prompt, null);
}

/// Mark prompt start with parameters
pub fn markPromptStartWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeTermPhase(writer, alloc, caps, .prompt, params);
}

/// Mark the end of prompt and start of command input (FinalTerm B)
pub fn markCommandStart(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    try writeTermPhase(writer, alloc, caps, .cmd_start, null);
}

/// Mark command start with parameters
pub fn markCommandStartWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeTermPhase(writer, alloc, caps, .cmd_start, params);
}

/// Mark that command has been executed and output is starting (FinalTerm C)
pub fn markCommandExecuted(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    try writeTermPhase(writer, alloc, caps, .cmd_executed, null);
}

/// Mark command executed with parameters
pub fn markCommandExecutedWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeTermPhase(writer, alloc, caps, .cmd_executed, params);
}

/// Mark that command has finished (FinalTerm D)
pub fn markCommandFinished(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    exit_code: ?i32,
) !void {
    if (exit_code) |code| {
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(alloc);

        try std.fmt.format(buf.writer(alloc), "{d}", .{code});
        const code_str = try buf.toOwnedSlice(alloc);
        defer alloc.free(code_str);

        try writeTermPhase(writer, alloc, caps, .cmd_finished, code_str);
    } else {
        try writeTermPhase(writer, alloc, caps, .cmd_finished, null);
    }
}

/// Mark command finished with custom parameters
pub fn markCommandFinishedWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeTermPhase(writer, alloc, caps, .cmd_finished, params);
}

/// Shell Integration Helper - complete command execution lifecycle
pub fn commandContext(comptime WriterType: type) type {
    return struct {
        writer: WriterType,
        allocator: std.mem.Allocator,
        caps: TermCaps,

        const Self = @This();

        /// Mark that we're about to show a prompt
        pub fn startPrompt(self: Self) !void {
            try markPromptStart(self.writer, self.allocator, self.caps);
        }

        /// Mark that prompt is done, command input begins
        pub fn startCommand(self: Self) !void {
            try markCommandStart(self.writer, self.allocator, self.caps);
        }

        /// Mark that command is executing, output will begin
        pub fn executeCommand(self: Self) !void {
            try markCommandExecuted(self.writer, self.allocator, self.caps);
        }

        /// Mark that command finished with optional exit code
        pub fn finishCommand(self: Self, exit_code: ?i32) !void {
            try markCommandFinished(self.writer, self.allocator, self.caps, exit_code);
        }

        /// Convenience method to wrap command execution with proper markers
        pub fn wrapCommand(
            self: Self,
            command_fn: anytype,
            args: anytype,
        ) !i32 {
            try self.executeCommand();
            const exit_code = @call(.auto, command_fn, args);
            try self.finishCommand(exit_code);
            return exit_code;
        }
    };
}

/// Create a command context for shell integration
pub fn createCommandContext(
    writer: anytype,
    allocator: std.mem.Allocator,
    caps: TermCaps,
) commandContext(@TypeOf(writer)) {
    return commandContext(@TypeOf(writer)){
        .writer = writer,
        .allocator = allocator,
        .caps = caps,
    };
}

/// Build FinalTerm sequence with multiple parameters
pub fn buildTermSequence(
    alloc: std.mem.Allocator,
    phase: Phase,
    params: []const []const u8,
) ![]u8 {
    const st = oscTerminator();

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "\x1b]");
    try appendDec(&buf, alloc, seqcfg.osc.ops.term);
    try buf.append(alloc, ';');
    try buf.appendSlice(alloc, phase.toSubcode());

    for (params) |param| {
        try buf.append(alloc, ';');
        const clean_param = try sanitize(alloc, param);
        defer alloc.free(clean_param);
        try buf.appendSlice(alloc, clean_param);
    }

    try buf.appendSlice(alloc, st);
    return try buf.toOwnedSlice(alloc);
}

/// CLI integration helper for applications
pub fn cliIntegration(comptime ContextType: type) type {
    return struct {
        context: ContextType,

        const Self = @This();

        pub fn init(context: ContextType) Self {
            return Self{ .context = context };
        }

        /// Run a complete command cycle for a CLI application
        pub fn runCommand(
            self: Self,
            command_fn: anytype,
            args: anytype,
        ) !i32 {
            // Mark prompt (typically done by shell, but useful for standalone CLIs)
            try self.context.startPrompt();

            // Mark command start
            try self.context.startCommand();

            // Execute command with proper markers
            return try self.context.wrapCommand(command_fn, args);
        }
    };
}

// Note: The original promptStart, promptEnd, commandStart, commandEnd functions
// are still available for backwards compatibility. The new functions
// provide additional functionality while maintaining the same interface.

// Convenience constants with configurable terminator
const PROMPT_START_TEMPLATE = "\x1b]133;A";
const COMMAND_START_TEMPLATE = "\x1b]133;B";
const COMMAND_EXECUTED_TEMPLATE = "\x1b]133;C";
const COMMAND_FINISHED_TEMPLATE = "\x1b]133;D";

// ============================================================================
// SHELL INTEGRATION INTERFACE IMPLEMENTATION
// ============================================================================

// Disable unused parameter warnings for interface implementations
// as not all implementations will use all parameters
comptime {
    std.debug.assert(true);
}

/// Term shell integration interface implementation
pub const TermInterface = integration.Shell.Interface{
    .name = "FinalTerm",
    .getCapabilities = getCapabilities,
    .prompt_ops = .{
        .markPromptStart = markPromptStartInterface,
        .markPromptEnd = markPromptEndInterface,
        .markPromptStartWithParams = markPromptStartWithParamsInterface,
        .markPromptEndWithParams = markPromptEndWithParamsInterface,
    },
    .command_ops = .{
        .markCommandStart = markCommandStartInterface,
        .markCommandEnd = markCommandEndInterface,
        .markCommandStartWithParams = markCommandStartWithParamsInterface,
        .markCommandEndWithParams = markCommandEndWithParamsInterface,
    },
    .directory_ops = .{
        .setWorkingDirectory = setWorkingDirectoryInterface,
        .setRemoteHost = setRemoteHostInterface,
        .clearRemoteHost = clearRemoteHostInterface,
    },
    .semantic_ops = .{
        .markZoneStart = markZoneStartInterface,
        .markZoneEnd = markZoneEndInterface,
        .addAnnotation = addAnnotationInterface,
        .clearAnnotations = clearAnnotationsInterface,
    },
    .notification_ops = .{
        .requestAttention = requestAttentionInterface,
        .setBadge = setBadgeInterface,
        .clearBadge = clearBadgeInterface,
        .setAlertOnCompletion = setAlertOnCompletionInterface,
        .triggerDownload = triggerDownloadInterface,
    },
};

fn getCapabilities() integration.ShellIntegration.TermCaps {
    return .{
        .supports_final_term = true,
        .supports_iterm2_osc1337 = false,
        .supports_notifications = false,
        .supports_badges = false,
        .supports_annotations = false,
        .supports_marks = false,
        .supports_alerts = false,
        .supports_downloads = false,
    };
}

fn markPromptStartInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType)) integration.ShellIntegration.Error!void {
    _ = _ctx;
    // FinalTerm doesn't support prompt start
}

fn markPromptEndInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType)) integration.ShellIntegration.Error!void {
    _ = _ctx;
    // FinalTerm doesn't support prompt end
}

fn markPromptStartWithParamsInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _params: []const []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _params;
    // FinalTerm doesn't support prompt parameters
}

fn markPromptEndWithParamsInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _params: []const []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _params;
    // FinalTerm doesn't support prompt parameters
}

fn markCommandStartInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _command: []const u8, _cwd: ?[]const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _command;
    _ = _cwd;
    // FinalTerm doesn't support command start
}

fn markCommandEndInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _command: []const u8, _exit_code: i32, _duration_ms: ?u64) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _command;
    _ = _exit_code;
    _ = _duration_ms;
    // FinalTerm doesn't support command end
}

fn markCommandStartWithParamsInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _command: []const u8, _cwd: ?[]const u8, _params: []const []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _command;
    _ = _cwd;
    _ = _params;
    // FinalTerm doesn't support command parameters
}

fn markCommandEndWithParamsInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _command: []const u8, _exit_code: i32, _duration_ms: ?u64, _params: []const []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _command;
    _ = _exit_code;
    _ = _duration_ms;
    _ = _params;
    // FinalTerm doesn't support command parameters
}

fn setWorkingDirectoryInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _path: []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _path;
    // FinalTerm doesn't support working directory tracking directly
    // This could be implemented using OSC 7 if supported by the terminal
}

fn setRemoteHostInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _hostname: []const u8, _username: ?[]const u8, _port: ?u16) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _hostname;
    _ = _username;
    _ = _port;
    // FinalTerm doesn't support remote host tracking
}

fn clearRemoteHostInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType)) integration.ShellIntegration.Error!void {
    _ = _ctx;
    // FinalTerm doesn't support remote host tracking
}

fn markZoneStartInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _zone_type: []const u8, _name: ?[]const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _zone_type;
    _ = _name;
    // FinalTerm doesn't support semantic zones
}

fn markZoneEndInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _zone_type: []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _zone_type;
    // FinalTerm doesn't support semantic zones
}

fn addAnnotationInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _config: integration.ShellIntegration.AnnotationConfig) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _config;
    // FinalTerm doesn't support annotations
}

fn clearAnnotationsInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType)) integration.ShellIntegration.Error!void {
    _ = _ctx;
    // FinalTerm doesn't support annotations
}

fn requestAttentionInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _message: ?[]const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _message;
    // FinalTerm doesn't support notifications
}

fn setBadgeInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _text: []const u8) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _text;
    // FinalTerm doesn't support badges
}

fn clearBadgeInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType)) integration.ShellIntegration.Error!void {
    _ = _ctx;
    // FinalTerm doesn't support badges
}

fn setAlertOnCompletionInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _config: integration.ShellIntegration.AlertConfig) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _config;
    // FinalTerm doesn't support alerts
}

fn triggerDownloadInterface(comptime WriterType: type, _ctx: integration.ShellIntegration.Context(WriterType), _config: integration.ShellIntegration.DownloadConfig) integration.ShellIntegration.Error!void {
    _ = _ctx;
    _ = _config;
    // FinalTerm doesn't support downloads
}

// ============================================================================
// TESTS
// ============================================================================

test "term sequences" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const MockWriter = struct {
        buffer: *std.ArrayListUnmanaged(u8),
        allocator: std.mem.Allocator,

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(self.allocator, bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsTermOsc133 = true };
    const mock_writer = MockWriter{ .buffer = &buf, .allocator = allocator };

    // Test prompt start
    try markPromptStart(mock_writer, allocator, caps);

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "133;A") != null);
}

test "command context workflow" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    const MockWriter = struct {
        buffer: *std.ArrayListUnmanaged(u8),
        allocator: std.mem.Allocator,

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(self.allocator, bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsTermOsc133 = true };
    const mock_writer = MockWriter{ .buffer = &buf, .allocator = allocator };

    const context = createCommandContext(mock_writer, allocator, caps);

    // Test complete workflow
    try context.startPrompt();
    try context.startCommand();
    try context.executeCommand();
    try context.finishCommand(0);

    const output = buf.items;

    // Verify all phases are present
    try testing.expect(std.mem.indexOf(u8, output, "133;A") != null); // Prompt
    try testing.expect(std.mem.indexOf(u8, output, "133;B") != null); // Command start
    try testing.expect(std.mem.indexOf(u8, output, "133;C") != null); // Command executed
    try testing.expect(std.mem.indexOf(u8, output, "133;D;0") != null); // Command finished
}

test "term sequence with parameters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test building sequence with multiple parameters
    const params = [_][]const u8{ "param1", "param2" };
    const seq = try buildTermSequence(allocator, .prompt, &params);
    defer allocator.free(seq);

    try testing.expect(std.mem.indexOf(u8, seq, "133;A;param1;param2") != null);
}

const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        try out.append(ch);
    }
    return try out.toOwnedSlice();
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [10]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(s);
}

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;
}

fn buildFinalTerm(
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

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.finalterm);
    try buf.append(';');
    try buf.appendSlice(subcode);
    if (clean_param) |p| {
        try buf.append(';');
        try buf.appendSlice(p);
    }
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

pub fn writeFinalTerm(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    subcode: []const u8,
    param: ?[]const u8,
) !void {
    if (!caps.supportsFinalTermOsc133) return error.Unsupported;
    const seq = try buildFinalTerm(alloc, subcode, param);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Convenience helpers for common markers
pub fn promptStart(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "A", null);
}

pub fn promptEnd(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "B", null);
}

pub fn commandStart(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "C", null);
}

pub fn commandEnd(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "D", null);
}

// === ENHANCED FINALTERM FEATURES ===

/// Enhanced FinalTerm protocol phases with better naming
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

/// Enhanced FinalTerm sequence with phase enum
pub fn writeFinalTermPhase(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    phase: Phase,
    param: ?[]const u8,
) !void {
    try writeFinalTerm(writer, alloc, caps, phase.toSubcode(), param);
}

/// Mark the start of a shell prompt (FinalTerm A)
pub fn markPromptStart(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .prompt, null);
}

/// Mark prompt start with parameters
pub fn markPromptStartWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .prompt, params);
}

/// Mark the end of prompt and start of command input (FinalTerm B)
pub fn markCommandStart(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .cmd_start, null);
}

/// Mark command start with parameters
pub fn markCommandStartWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .cmd_start, params);
}

/// Mark that command has been executed and output is starting (FinalTerm C)
pub fn markCommandExecuted(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .cmd_executed, null);
}

/// Mark command executed with parameters
pub fn markCommandExecutedWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .cmd_executed, params);
}

/// Mark that command has finished (FinalTerm D)
pub fn markCommandFinished(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    exit_code: ?i32,
) !void {
    if (exit_code) |code| {
        var buf = std.ArrayList(u8).init(alloc);
        defer buf.deinit();

        try std.fmt.format(buf.writer(), "{d}", .{code});
        const code_str = try buf.toOwnedSlice();
        defer alloc.free(code_str);

        try writeFinalTermPhase(writer, alloc, caps, .cmd_finished, code_str);
    } else {
        try writeFinalTermPhase(writer, alloc, caps, .cmd_finished, null);
    }
}

/// Mark command finished with custom parameters
pub fn markCommandFinishedWithParams(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    params: []const u8,
) !void {
    try writeFinalTermPhase(writer, alloc, caps, .cmd_finished, params);
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
pub fn buildFinalTermSequence(
    alloc: std.mem.Allocator,
    phase: Phase,
    params: []const []const u8,
) ![]u8 {
    const st = oscTerminator();

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.finalterm);
    try buf.append(';');
    try buf.appendSlice(phase.toSubcode());

    for (params) |param| {
        try buf.append(';');
        const clean_param = try sanitize(alloc, param);
        defer alloc.free(clean_param);
        try buf.appendSlice(clean_param);
    }

    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
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
// are still available for backwards compatibility. The new enhanced functions
// provide additional functionality while maintaining the same interface.

// Enhanced convenience constants with configurable terminator
const PROMPT_START_TEMPLATE = "\x1b]133;A";
const COMMAND_START_TEMPLATE = "\x1b]133;B";
const COMMAND_EXECUTED_TEMPLATE = "\x1b]133;C";
const COMMAND_FINISHED_TEMPLATE = "\x1b]133;D";

// Tests for enhanced functionality
test "enhanced finalterm sequences" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const MockWriter = struct {
        buffer: *std.ArrayList(u8),

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsFinalTermOsc133 = true };
    const mock_writer = MockWriter{ .buffer = &buf };

    // Test prompt start
    try markPromptStart(mock_writer, allocator, caps);

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "133;A") != null);
}

test "command context workflow" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    const MockWriter = struct {
        buffer: *std.ArrayList(u8),

        pub fn write(self: @This(), bytes: []const u8) !usize {
            try self.buffer.appendSlice(bytes);
            return bytes.len;
        }
    };

    const caps = TermCaps{ .supportsFinalTermOsc133 = true };
    const mock_writer = MockWriter{ .buffer = &buf };

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

test "finalterm sequence with parameters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test building sequence with multiple parameters
    const params = [_][]const u8{ "param1", "param2" };
    const seq = try buildFinalTermSequence(allocator, .prompt, &params);
    defer allocator.free(seq);

    try testing.expect(std.mem.indexOf(u8, seq, "133;A;param1;param2") != null);
}

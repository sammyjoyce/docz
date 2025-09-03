//! Simple Task/Subagent tool for AMP agent.
//!
//! This is a simplified version focused on actual subprocess spawning
//! with proper timeout and error handling.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Task execution request structure
const TaskRequest = struct {
    /// Task description with full context and detailed plan
    description: []const u8,
    /// Optional subagent type to use (defaults to 'default')
    subagent_type: ?[]const u8 = null,
    /// Detailed prompt for the subagent including context and expected output
    prompt: []const u8,
    /// Timeout in seconds (defaults to 30)
    timeout_seconds: ?u32 = null,
};

/// Task execution response structure
const TaskResponse = struct {
    success: bool,
    tool: []const u8 = "task",
    task_id: ?[]const u8 = null,
    subagent_type: ?[]const u8 = null,
    result: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    execution_time_ms: ?i64 = null,
    exit_code: ?i32 = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,
};

/// Execute task by spawning a subagent
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(TaskResponse);
        const response = TaskResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    const start_time = std.time.milliTimestamp();

    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(TaskRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const req = request.value;

    // Validate required fields
    if (req.description.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }
    if (req.prompt.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }

    // Default to 'default' agent
    const subagent_type = req.subagent_type orelse "default";
    const timeout_seconds = req.timeout_seconds orelse 30;

    // Generate unique task ID
    const task_id = try std.fmt.allocPrint(allocator, "task_{d}", .{std.time.timestamp()});
    defer allocator.free(task_id);

    // Execute task by spawning subagent
    const result = try spawnSubagent(allocator, req.description, req.prompt, subagent_type, timeout_seconds);
    defer {
        if (result.stdout) |s| allocator.free(s);
        if (result.stderr) |s| allocator.free(s);
        if (result.result) |s| allocator.free(s);
        if (result.error_message) |s| allocator.free(s);
    }

    const execution_time = std.time.milliTimestamp() - start_time;

    // Build response
    const response = TaskResponse{
        .success = result.success,
        .task_id = task_id,
        .subagent_type = subagent_type,
        .result = result.result,
        .error_message = result.error_message,
        .execution_time_ms = execution_time,
        .exit_code = result.exit_code,
        .stdout = result.stdout,
        .stderr = result.stderr,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(TaskResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

const SubagentResult = struct {
    success: bool,
    result: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    exit_code: ?i32 = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,
};

/// Spawn a subagent to execute the given task
fn spawnSubagent(allocator: std.mem.Allocator, description: []const u8, prompt: []const u8, subagent_type: []const u8, timeout_seconds: u32) !SubagentResult {
    // Get current working directory
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.process.getCwd(&cwd_buf) catch ".";

    // Create the command to execute the subagent
    const agent_flag = try std.fmt.allocPrint(allocator, "-Dagent={s}", .{subagent_type});
    defer allocator.free(agent_flag);

    // Build command arguments
    const argv = [_][]const u8{ "zig", "build", agent_flag, "run", "--", "run", prompt };

    // Create child process
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = cwd;

    // Set environment variables
    var env_map = std.process.getEnvMap(allocator) catch {
        return SubagentResult{
            .success = false,
            .error_message = try allocator.dupe(u8, "Failed to get environment variables"),
        };
    };
    defer env_map.deinit();

    // Ensure AGENT_NAME is set for the subagent
    env_map.put("AGENT_NAME", subagent_type) catch {};
    child.env_map = &env_map;

    // Spawn the process
    child.spawn() catch |err| {
        return SubagentResult{
            .success = false,
            .error_message = try std.fmt.allocPrint(allocator, "Failed to spawn subagent: {}", .{err}),
        };
    };

    // Set up timeout
    const timeout_ns = @as(u64, timeout_seconds) * std.time.ns_per_s;
    const start_time = std.time.nanoTimestamp();

    // Read output with timeout
    const stdout_bytes = readWithTimeout(allocator, child.stdout.?, timeout_ns, start_time) catch |err| blk: {
        // Kill the child process if timeout or read error
        _ = child.kill() catch {};
        _ = child.wait() catch {};
        break :blk switch (err) {
            error.Timeout => try allocator.dupe(u8, "[ERROR] Subagent execution timed out"),
            else => try std.fmt.allocPrint(allocator, "[ERROR] Failed to read subagent output: {}", .{err}),
        };
    };

    const stderr_bytes = readWithTimeout(allocator, child.stderr.?, timeout_ns, start_time) catch |err| blk: {
        break :blk switch (err) {
            error.Timeout => try allocator.dupe(u8, ""),
            else => try allocator.dupe(u8, ""),
        };
    };

    // Wait for process completion with timeout check
    const term_result = waitWithTimeout(&child, timeout_ns, start_time) catch |err| blk: {
        _ = child.kill() catch {};
        _ = child.wait() catch {};
        break :blk switch (err) {
            error.Timeout => std.process.Child.Term{ .Signal = 9 }, // SIGKILL
            else => std.process.Child.Term{ .Signal = 1 },
        };
    };

    const exit_code = switch (term_result) {
        .Exited => |code| @as(i32, @intCast(code)),
        .Signal => -1,
        .Stopped => -2,
        .Unknown => -3,
    };

    // Format result based on success/failure
    if (exit_code == 0) {
        // Success case
        const result_template =
            \\## Task Execution Summary
            \\
            \\**Task:** {s}
            \\**Subagent:** {s}
            \\**Status:** ✅ Completed successfully
            \\
            \\**Results:**
            \\{s}
        ;
        const result = try std.fmt.allocPrint(allocator, result_template, .{ description, subagent_type, stdout_bytes });

        return SubagentResult{
            .success = true,
            .result = result,
            .exit_code = exit_code,
            .stdout = stdout_bytes,
            .stderr = stderr_bytes,
        };
    } else {
        // Error case
        const error_template =
            \\## Task Execution Summary
            \\
            \\**Task:** {s}
            \\**Subagent:** {s}  
            \\**Status:** ❌ Failed (exit code: {d})
            \\
            \\**Error Output:**
            \\{s}
            \\
            \\**Standard Output:**
            \\{s}
        ;
        const error_msg = try std.fmt.allocPrint(allocator, error_template, .{ description, subagent_type, exit_code, stderr_bytes, stdout_bytes });

        return SubagentResult{
            .success = false,
            .error_message = error_msg,
            .exit_code = exit_code,
            .stdout = stdout_bytes,
            .stderr = stderr_bytes,
        };
    }
}

/// Read from file handle with timeout (simplified version)
fn readWithTimeout(allocator: std.mem.Allocator, file: std.fs.File, timeout_ns: u64, start_time: i128) ![]u8 {
    // For simplicity, we'll read all at once and check timeout
    // A more robust implementation would use non-blocking I/O or threads

    const current_time = std.time.nanoTimestamp();
    if (current_time - start_time > timeout_ns) {
        return error.Timeout;
    }

    // Read with a reasonable buffer limit
    const max_size = 1024 * 1024; // 1MB
    return file.readToEndAlloc(allocator, max_size) catch |err| switch (err) {
        error.FileTooBig => try allocator.dupe(u8, "[ERROR] Output too large (>1MB)"),
        else => return err,
    };
}

/// Wait for child process with timeout (simplified version)
fn waitWithTimeout(child: *std.process.Child, timeout_ns: u64, start_time: i128) !std.process.Child.Term {
    // Check timeout first
    const current_time = std.time.nanoTimestamp();
    if (current_time - start_time > timeout_ns) {
        return error.Timeout;
    }

    // For simplicity, just wait normally
    // A more robust implementation would use non-blocking wait or threads
    return child.wait();
}

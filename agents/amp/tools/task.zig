//! Task/Subagent tool for AMP agent.
//!
//! Enables spawning subagents for complex multi-step tasks and parallel work delegation.
//! Based on amp-task.md specification from specs/amp/prompts/.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Task execution request structure
const TaskRequest = struct {
    /// Task description with full context and detailed plan
    description: []const u8,
    /// Optional subagent type to use (defaults to 'general')
    subagent_type: ?[]const u8 = null,
    /// Detailed prompt for the subagent including context and expected output
    prompt: []const u8,
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

    // Default to general subagent type
    const subagent_type = req.subagent_type orelse "general";

    // Generate unique task ID
    const task_id = try std.fmt.allocPrint(allocator, "task_{d}", .{std.time.timestamp()});
    defer allocator.free(task_id);

    // Execute task by spawning subagent
    const result = try spawnSubagent(allocator, req.description, req.prompt, subagent_type);
    defer allocator.free(result);

    const execution_time = std.time.milliTimestamp() - start_time;

    // Build response
    const response = TaskResponse{
        .success = true,
        .task_id = task_id,
        .subagent_type = subagent_type,
        .result = result,
        .execution_time_ms = execution_time,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(TaskResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

/// Spawn a subagent to execute the given task
fn spawnSubagent(allocator: std.mem.Allocator, description: []const u8, prompt: []const u8, subagent_type: []const u8) ![]const u8 {
    // Determine which agent to use
    const agent_name = if (std.mem.eql(u8, subagent_type, "general")) "default" else subagent_type;

    // Get the current working directory to execute from
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buf);

    // Create the command to execute the subagent
    // Using "zig build -Dagent=<agent> run -- run <prompt>" to spawn the subagent
    const agent_flag = try std.fmt.allocPrint(allocator, "-Dagent={s}", .{agent_name});
    defer allocator.free(agent_flag);

    const command = [_][]const u8{ "zig", "build", agent_flag, "run", "--", "run", prompt };

    // Create child process
    var child = std.process.Child.init(&command, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = cwd;

    // Set environment variables
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // Ensure AGENT_NAME is set for the subagent
    try env_map.put("AGENT_NAME", agent_name);
    child.env_map = &env_map;

    // Spawn the process
    try child.spawn();

    // Set up timeout (30 seconds)
    const timeout_ns = 30 * std.time.ns_per_s;
    const start_time = std.time.nanoTimestamp();

    // Read output with timeout
    const stdout_bytes = readWithTimeout(allocator, child.stdout.?, timeout_ns, start_time) catch |err| blk: {
        // Kill the child process if timeout or read error
        _ = child.kill() catch {};
        _ = child.wait() catch {};
        break :blk switch (err) {
            error.Timeout => try allocator.dupe(u8, "[ERROR] Subagent execution timed out after 30 seconds"),
            else => try std.fmt.allocPrint(allocator, "[ERROR] Failed to read subagent output: {}", .{err}),
        };
    };
    defer allocator.free(stdout_bytes);

    const stderr_bytes = readWithTimeout(allocator, child.stderr.?, timeout_ns, start_time) catch |err| blk: {
        break :blk switch (err) {
            error.Timeout => try allocator.dupe(u8, ""),
            else => try allocator.dupe(u8, ""),
        };
    };
    defer allocator.free(stderr_bytes);

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
    if (exit_code == 0 and stdout_bytes.len > 0) {
        // Success case - return the agent's output
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
        return std.fmt.allocPrint(allocator, result_template, .{ description, agent_name, stdout_bytes });
    } else {
        // Error case - return error information
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
        return std.fmt.allocPrint(allocator, error_template, .{ description, agent_name, exit_code, stderr_bytes, stdout_bytes });
    }
}

/// Read from file handle with timeout
fn readWithTimeout(allocator: std.mem.Allocator, file: std.fs.File, timeout_ns: u64, start_time: i128) ![]u8 {
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    var read_buffer: [4096]u8 = undefined;

    while (true) {
        // Check timeout
        const current_time = std.time.nanoTimestamp();
        if (current_time - start_time > timeout_ns) {
            return error.Timeout;
        }

        // Try to read (non-blocking would be ideal, but we'll use the simpler blocking approach)
        const bytes_read = file.read(&read_buffer) catch |err| switch (err) {
            error.WouldBlock => {
                // Small delay to prevent busy waiting
                std.Thread.sleep(10 * std.time.ns_per_ms);
                continue;
            },
            else => return err,
        };

        if (bytes_read == 0) break; // EOF

        try buffer.appendSlice(allocator, read_buffer[0..bytes_read]);

        // Limit output size to prevent memory issues
        if (buffer.items.len > 1024 * 1024) { // 1MB limit
            break;
        }
    }

    return buffer.toOwnedSlice(allocator);
}

/// Wait for child process with timeout
fn waitWithTimeout(child: *std.process.Child, timeout_ns: u64, start_time: i128) !std.process.Child.Term {
    while (true) {
        // Check timeout
        const current_time = std.time.nanoTimestamp();
        if (current_time - start_time > timeout_ns) {
            return error.Timeout;
        }

        // Check if process is still running by using a shorter sleep first
        std.Thread.sleep(10 * std.time.ns_per_ms);

        // Try to wait for completion
        const term = child.wait() catch |err| {
            return err;
        };
        return term;
    }
}

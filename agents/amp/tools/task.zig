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

    // Create the command to execute the subagent
    // Using "zig build -Dagent=<agent> run -- run <prompt>" to spawn the subagent
    const agent_flag = try std.fmt.allocPrint(allocator, "-Dagent={s}", .{agent_name});
    defer allocator.free(agent_flag);

    const command = [_][]const u8{ "zig", "build", agent_flag, "run", "--", "run", prompt };

    // Use the foundation pattern: Child.run() for simple execution with output capture
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &command,
        .max_output_bytes = 1024 * 1024, // 1MB output limit
    }) catch |err| {
        return try std.fmt.allocPrint(allocator,
            \\## Task Execution Summary
            \\
            \\**Task:** {s}
            \\**Subagent:** {s}
            \\**Status:** ❌ Failed to spawn
            \\
            \\**Error:** {s}
        , .{ description, agent_name, @errorName(err) });
    };

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const exit_code = switch (result.term) {
        .Exited => |code| @as(i32, @intCast(code)),
        .Signal => -1,
        .Stopped => -2,
        .Unknown => -3,
    };

    // Format result based on success/failure
    if (exit_code == 0 and result.stdout.len > 0) {
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
        return std.fmt.allocPrint(allocator, result_template, .{ description, agent_name, result.stdout });
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
        return std.fmt.allocPrint(allocator, error_template, .{ description, agent_name, exit_code, result.stderr, result.stdout });
    }
}

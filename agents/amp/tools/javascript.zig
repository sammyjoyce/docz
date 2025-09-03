//! JavaScript execution tool for AMP agent.
//!
//! Executes JavaScript code in a sandboxed Node.js environment with async support.
//! Based on amp-javascript-tool.md specification.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// JavaScript execution request structure
const JavaScriptRequest = struct {
    /// JavaScript code to execute (alternative to codePath)
    code: ?[]const u8 = null,
    /// Path to JavaScript file to execute (alternative to code)
    codePath: ?[]const u8 = null,
    /// Optional working directory (defaults to current directory)
    workingDirectory: ?[]const u8 = null,
};

/// JavaScript execution response structure
const JavaScriptResponse = struct {
    success: bool,
    tool: []const u8 = "javascript",
    result: ?std.json.Value = null,
    error_message: ?[]const u8 = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,
    exit_code: ?i32 = null,
    execution_time_ms: ?i64 = null,
};

/// Execute JavaScript code in Node.js environment
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(JavaScriptResponse);
        const response = JavaScriptResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(JavaScriptRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const req = request.value;

    // Validate request - need either code or codePath
    if (req.code == null and req.codePath == null) {
        return error.MissingParameter;
    }

    if (req.code != null and req.codePath != null) {
        return error.InvalidInput;
    }

    const start_time = std.time.milliTimestamp();

    // Check if Node.js is available
    var node_check = std.process.Child.init(&[_][]const u8{ "node", "--version" }, allocator);
    node_check.stdout_behavior = .Ignore;
    node_check.stderr_behavior = .Ignore;
    const node_check_result = try node_check.spawnAndWait();

    if (node_check_result != .Exited or node_check_result.Exited != 0) {
        return error.ExecutionFailed;
    }

    var script_to_execute: []const u8 = undefined;
    var temp_file: ?std.fs.File = null;
    var temp_file_path: ?[]u8 = null;

    defer {
        if (temp_file) |file| {
            file.close();
        }
        if (temp_file_path) |path| {
            std.fs.cwd().deleteFile(path) catch {};
            allocator.free(path);
        }
    }

    if (req.code) |code| {
        // Create temporary file for inline code
        const temp_dir = std.fs.cwd().openDir(".", .{}) catch return error.PermissionDenied;

        // Generate unique temporary filename
        const timestamp = std.time.timestamp();
        temp_file_path = try std.fmt.allocPrint(allocator, "amp_js_temp_{d}.js", .{timestamp});

        temp_file = try temp_dir.createFile(temp_file_path.?, .{});

        // Wrap code in async IIFE as per spec
        const wrapped_code = try std.fmt.allocPrint(allocator,
            \\(async () => {{
            \\{s}
            \\}})().then(result => {{
            \\    console.log('__RESULT_START__');
            \\    console.log(JSON.stringify(result));
            \\    console.log('__RESULT_END__');
            \\}}).catch(error => {{
            \\    console.error('__ERROR_START__');
            \\    console.error(error.message || error.toString());
            \\    console.error('__ERROR_END__');
            \\    process.exit(1);
            \\}});
        , .{code});
        defer allocator.free(wrapped_code);

        try temp_file.?.writeAll(wrapped_code);

        script_to_execute = temp_file_path.?;
    } else if (req.codePath) |path| {
        // Use existing file
        script_to_execute = path;

        // Verify file exists and is readable
        const file = std.fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
        file.close();
    }

    // Execute Node.js with the script
    var child = std.process.Child.init(&[_][]const u8{ "node", script_to_execute }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    if (req.workingDirectory) |wd| {
        child.cwd = wd;
    }

    try child.spawn();

    // Read stdout and stderr
    const stdout_bytes = try child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(stdout_bytes);

    const stderr_bytes = try child.stderr.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(stderr_bytes);

    const term_result = try child.wait();

    const end_time = std.time.milliTimestamp();
    const execution_time = end_time - start_time;

    const exit_code = switch (term_result) {
        .Exited => |code| @as(i32, @intCast(code)),
        .Signal => -1,
        .Stopped => -2,
        .Unknown => -3,
    };

    // Parse result from stdout if execution was successful
    var result_value: ?std.json.Value = null;
    if (exit_code == 0 and req.code != null) {
        // Extract result from wrapped output
        if (std.mem.indexOf(u8, stdout_bytes, "__RESULT_START__")) |start_idx| {
            if (std.mem.indexOf(u8, stdout_bytes[start_idx..], "__RESULT_END__")) |end_offset| {
                const result_start = start_idx + "__RESULT_START__".len;
                const result_end = start_idx + end_offset;
                const result_json = std.mem.trim(u8, stdout_bytes[result_start..result_end], " \n\r\t");

                if (result_json.len > 0) {
                    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result_json, .{}) catch null;
                    if (parsed) |p| {
                        result_value = p.value;
                    }
                }
            }
        }
    }

    const ResponseMapper = toolsMod.JsonReflector.mapper(JavaScriptResponse);
    const response = JavaScriptResponse{
        .success = exit_code == 0,
        .result = result_value,
        .error_message = if (exit_code != 0) allocator.dupe(u8, stderr_bytes) catch null else null,
        .stdout = if (stdout_bytes.len > 0) allocator.dupe(u8, stdout_bytes) catch null else null,
        .stderr = if (stderr_bytes.len > 0) allocator.dupe(u8, stderr_bytes) catch null else null,
        .exit_code = exit_code,
        .execution_time_ms = execution_time,
    };

    return ResponseMapper.toJsonValue(allocator, response);
}

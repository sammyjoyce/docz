//! Command Risk Assessment Tool
//!
//! Analyzes commands for security risks and determines if they require user approval.
//! Based on specs/amp/prompts/amp-command-risk.md specification.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Input parameters for command risk assessment
const CommandRiskInput = struct {
    command: []const u8,
};

/// Risk assessment result
const CommandRiskResult = struct {
    success: bool = true,
    tool: []const u8 = "command_risk",
    analysis: []const u8,
    requires_approval: bool,
    reason: []const u8,
    to_allow: ?[]const u8 = null, // null for empty prefix
};

/// Execute command risk assessment
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(CommandRiskResult);
        const response = CommandRiskResult{
            .success = false,
            .analysis = @errorName(err),
            .requires_approval = true,
            .reason = "Error during analysis",
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(CommandRiskInput);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const input = request.value;
    const command = std.mem.trim(u8, input.command, " \t\n\r");

    // Check if command contains inline code execution flags
    const inline_code_flags = [_][]const u8{ "-c", "-e", "-eval", "--eval", "-p", "<<EOF", "<<<" };

    var has_inline_code = false;
    for (inline_code_flags) |flag| {
        if (std.mem.indexOf(u8, command, flag) != null) {
            has_inline_code = true;
            break;
        }
    }

    // Check for interpreters with inline code
    const interpreter_patterns = [_][]const u8{ "python -c", "python3 -c", "node -e", "bash -c", "sh -c", "powershell -c", "pwsh -c", "ruby -e", "perl -e" };

    for (interpreter_patterns) |pattern| {
        if (std.mem.indexOf(u8, command, pattern) != null) {
            has_inline_code = true;
            break;
        }
    }

    // Analyze risk factors
    var risk_factors = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer risk_factors.deinit(allocator);

    var requires_approval = false;
    var analysis_parts = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer analysis_parts.deinit(allocator);

    // Check for destructive operations
    const destructive_commands = [_][]const u8{ "rm -rf", "rmdir", "del /s", "format", "fdisk", "mkfs", "dd if=", "shred", "wipe", "truncate", ">[>]", ">>", "> /dev", "chmod 777", "chown", "mv", "move" };

    for (destructive_commands) |destructive| {
        if (std.mem.indexOf(u8, command, destructive) != null) {
            try risk_factors.append(allocator, "destructive file operations");
            requires_approval = true;
            break;
        }
    }

    // Check for network operations
    const network_commands = [_][]const u8{ "curl", "wget", "fetch", "http", "nc ", "netcat", "ssh", "scp", "rsync", "git push", "git pull" };

    for (network_commands) |net_cmd| {
        if (std.mem.indexOf(u8, command, net_cmd) != null) {
            try risk_factors.append(allocator, "network operations");
            if (std.mem.indexOf(u8, command, "git push") != null or
                std.mem.indexOf(u8, command, "ssh") != null)
            {
                requires_approval = true;
            }
            break;
        }
    }

    // Check for package managers and installers
    const installer_commands = [_][]const u8{ "npm install", "pip install", "apt install", "yum install", "brew install", "dnf install", "pacman -S", "cargo install", "go install", "gem install", "composer install" };

    for (installer_commands) |installer| {
        if (std.mem.indexOf(u8, command, installer) != null) {
            try risk_factors.append(allocator, "package installation");
            requires_approval = true;
            break;
        }
    }

    // Check for unknown commands (basic heuristic)
    const known_safe_commands = [_][]const u8{ "ls", "dir", "cat", "echo", "pwd", "cd", "mkdir", "touch", "grep", "find", "awk", "sed", "sort", "uniq", "head", "tail", "git log", "git status", "git diff", "git show", "git branch", "npm test", "npm run", "yarn test", "yarn run", "make", "cmake", "zig build", "zig test", "zig fmt", "cargo build", "cargo test", "python", "node", "java -jar", "dotnet run" };

    var is_known_command = false;
    const first_word = if (std.mem.indexOf(u8, command, " ")) |space_idx|
        command[0..space_idx]
    else
        command;

    for (known_safe_commands) |safe_cmd| {
        if (std.mem.startsWith(u8, command, safe_cmd)) {
            is_known_command = true;
            break;
        }
    }

    if (!is_known_command and first_word.len > 0) {
        try risk_factors.append(allocator, "unknown command");
        requires_approval = true;
    }

    // Generate analysis
    if (has_inline_code) {
        try analysis_parts.append(allocator, "Command executes inline code");
        requires_approval = true;
    }

    if (risk_factors.items.len > 0) {
        const factors_str = try std.mem.join(allocator, ", ", risk_factors.items);
        const analysis_part = try std.fmt.allocPrint(allocator, "Risk factors: {s}", .{factors_str});
        try analysis_parts.append(allocator, analysis_part);
    } else {
        try analysis_parts.append(allocator, "Command appears safe with standard operations");
    }

    const full_analysis = try std.mem.join(allocator, ". ", analysis_parts.items);

    // Determine reason and prefix
    var reason: []const u8 = undefined;
    var to_allow: ?[]const u8 = null;

    if (requires_approval) {
        if (has_inline_code) {
            reason = "Inline code execution";
        } else if (std.mem.indexOf(u8, command, "rm -rf") != null) {
            reason = "Destructive file operations";
        } else if (std.mem.indexOf(u8, command, "git push") != null) {
            reason = "Remote git operations";
        } else if (!is_known_command) {
            reason = "Unknown command";
        } else {
            reason = "Potentially risky operation";
        }
    } else {
        reason = "Safe command";
        // Generate appropriate prefix for safe commands
        if (std.mem.startsWith(u8, command, "git log")) {
            to_allow = try allocator.dupe(u8, "git log");
        } else if (std.mem.startsWith(u8, command, "git status")) {
            to_allow = try allocator.dupe(u8, "git status");
        } else if (std.mem.startsWith(u8, command, "git diff")) {
            to_allow = try allocator.dupe(u8, "git diff");
        } else if (std.mem.startsWith(u8, command, "npm test")) {
            to_allow = try allocator.dupe(u8, "npm test");
        } else if (std.mem.startsWith(u8, command, "zig build")) {
            to_allow = try allocator.dupe(u8, "zig build");
        } else if (first_word.len > 0 and is_known_command) {
            to_allow = try allocator.dupe(u8, first_word);
        }
    }

    const result = CommandRiskResult{
        .analysis = full_analysis,
        .requires_approval = requires_approval,
        .reason = reason,
        .to_allow = to_allow,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(CommandRiskResult);
    return ResponseMapper.toJsonValue(allocator, result);
}

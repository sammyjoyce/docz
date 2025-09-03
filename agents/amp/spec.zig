//! Agent specification for AMP agent.
//!
//! This file defines the agent's interface to the core engine by:
//! - Assembling system prompt from specs/amp/* files
//! - Registering foundation tools with the shared registry
//! - Following Zig 0.15.1+ best practices

const std = @import("std");
const engine = @import("core_engine");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

// Explicit agent metadata for discovery/logging
pub const agentName: []const u8 = "amp";

/// Build the system prompt for the AMP agent.
/// Prefers file-based prompt when present; otherwise assembles from specs/amp/*
fn buildSystemPrompt(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options;

    // First try to load from system_prompt.txt
    const prompt_path = "agents/amp/system_prompt.txt";
    if (std.fs.cwd().openFile(prompt_path, .{})) |file| {
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return assembleFromSpecs(allocator),
        };
    } else |_| {
        // Fallback: assemble from specs/amp/*
        return assembleFromSpecs(allocator);
    }
}

/// Fallback system prompt assembly from specs/amp/* files
fn assembleFromSpecs(allocator: std.mem.Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Use initCapacity instead of init for Zig 0.15.1 compatibility
    var prompt_parts = try std.ArrayList([]const u8).initCapacity(a, 0);
    defer prompt_parts.deinit(a);

    // Core system identity and behavior (essential)
    if (std.fs.cwd().openFile("specs/amp/amp.system.md", .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(a, 1024 * 1024);
        // Extract content after frontmatter
        if (std.mem.indexOf(u8, content, "\n---\n")) |end_pos| {
            const main_content = content[end_pos + 5 ..];
            try prompt_parts.append(a, main_content);
        } else {
            try prompt_parts.append(a, content);
        }
    } else |_| {}

    // Communication style guidelines (essential)
    if (std.fs.cwd().openFile("specs/amp/amp-communication-style.md", .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(a, 1024 * 1024);
        if (std.mem.indexOf(u8, content, "\n---\n")) |end_pos| {
            const main_content = content[end_pos + 5 ..];
            try prompt_parts.append(a, "\n\n# Additional Communication Guidelines\n\n");
            try prompt_parts.append(a, main_content);
        }
    } else |_| {}

    // Task workflow conventions (essential)
    if (std.fs.cwd().openFile("specs/amp/amp-task.md", .{})) |file| {
        defer file.close();
        const content = try file.readToEndAlloc(a, 1024 * 1024);
        if (std.mem.indexOf(u8, content, "\n---\n")) |end_pos| {
            const main_content = content[end_pos + 5 ..];
            try prompt_parts.append(a, "\n\n# Task Management Guidelines\n\n");
            try prompt_parts.append(a, main_content);
        }
    } else |_| {}

    // Assemble final prompt
    const parts = prompt_parts.items;
    if (parts.len == 0) {
        // Fallback if no spec files found
        return allocator.dupe(u8, "You are Amp, a powerful AI coding agent built by Sourcegraph. You help users with software engineering tasks.");
    }

    var total_len: usize = 0;
    for (parts) |part| {
        total_len += part.len;
    }

    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (parts) |part| {
        @memcpy(result[pos .. pos + part.len], part);
        pos += part.len;
    }

    return result;
}

/// Register all tools for the AMP agent.
/// Follows markdown agent pattern by registering foundation built-ins.
fn registerTools(registry: *toolsMod.Registry) !void {
    // Register built-in foundation tools (grep, read, edit, bash, etc.)
    try toolsMod.registerBuiltins(registry);

    // Future: AMP-specific tools will be registered here
    // Based on specs/amp/amp-javascript-tool.md, amp-code-search.md, etc.
}

/// ============================================================================
/// AGENT SPECIFICATION EXPORT
/// ============================================================================
/// The agent specification that defines this agent's interface to the core engine.
/// This is the main export of this file and is used by the core engine to
/// interact with this agent.
///
/// The specification includes:
/// - buildSystemPrompt: Function to generate the system prompt
/// - registerTools: Function to register agent-specific tools
pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPrompt,
    .registerTools = registerTools,
};

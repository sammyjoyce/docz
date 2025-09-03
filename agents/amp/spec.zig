//! Agent specification for AMP agent.
//!
//! This file defines the agent's interface to the core engine by:
//! - Loading refined, deduplicated system prompt from system_prompt.txt
//! - Registering foundation tools with the shared registry
//! - Following Zig 0.15.1+ best practices
//!
//! Prompt Curation Strategy:
//! - Uses curated system_prompt.txt that eliminates duplication from specs/amp/*
//! - Provides logical section ordering and provenance tracking
//! - Minimal token usage with clean prompt structure

const std = @import("std");
const engine = @import("core_engine");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

// Explicit agent metadata for discovery/logging
pub const agentName: []const u8 = "amp";

/// Build the system prompt for the AMP agent.
/// Uses refined system_prompt.txt with fallback to minimal prompt
fn buildSystemPrompt(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options;

    // Load from refined system_prompt.txt
    const prompt_path = "agents/amp/system_prompt.txt";
    if (std.fs.cwd().openFile(prompt_path, .{})) |file| {
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return buildMinimalPrompt(allocator),
        };
    } else |_| {
        // Minimal fallback if system_prompt.txt is missing
        return buildMinimalPrompt(allocator);
    }
}

/// Minimal fallback prompt if system_prompt.txt is unavailable
fn buildMinimalPrompt(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "You are Amp, a powerful AI coding agent built by Sourcegraph. " ++
        "You help users with software engineering tasks. " ++
        "Use the tools available to you to assist the user. " ++
        "Be concise and direct in your responses.");
}

/// Register all tools for the AMP agent.
/// Registers foundation built-ins plus AMP-specific tools.
fn registerTools(registry: *toolsMod.Registry) !void {
    // Register built-in foundation tools (grep, read, edit, bash, etc.)
    try toolsMod.registerBuiltins(registry);

    // Register AMP-specific tools from tools/mod.zig
    const ampToolsMod = @import("tools/mod.zig");
    try ampToolsMod.registerAll(registry);
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

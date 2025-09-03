//! AMP agent tools module.
//!
//! This provides AMP-specific tools based on the specifications in specs/amp/prompts/
//! and follows the foundation framework patterns for tool registration.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Register all AMP-specific tools with the shared registry.
pub fn registerAll(registry: *toolsMod.Registry) !void {
    // JavaScript execution tool - executes JavaScript code in sandboxed Node.js environment
    try toolsMod.registerJsonTool(
        registry,
        "javascript",
        "Execute JavaScript code in a sandboxed Node.js environment with async support",
        @import("javascript.zig").execute,
        "amp",
    );

    // Glob tool - fast file pattern matching with sorting by modification time
    try toolsMod.registerJsonTool(
        registry,
        "glob",
        "Match files by glob pattern (supports **, *, ?, {a,b}, [a-z]) and return paths sorted by mtime desc",
        @import("glob.zig").run,
        "amp",
    );

    // Code Search tool - intelligent codebase exploration with semantic search capabilities
    try toolsMod.registerJsonTool(
        registry,
        "code_search",
        "Intelligently search codebase for code based on functionality or concepts. Uses ripgrep for fast search with fallback to manual search.",
        @import("code_search.zig").run,
        "amp",
    );

    // Task tool temporarily disabled in test builds pending Zig 0.15 API adjustments
    // try toolsMod.registerJsonTool(
    //     registry,
    //     "task",
    //     "Launch a new agent to handle complex, multi-step tasks autonomously. Use for parallel work delegation and complex analysis tasks.",
    //     @import("task.zig").execute,
    //     "amp",
    // );

    // Note: Oracle tool is currently disabled for tests due to network surface mismatch.
    // Re-enable after Http client error-set alignment.
    // try toolsMod.registerJsonTool(
    //     registry,
    //     "oracle",
    //     "Provide high-quality technical guidance, code reviews, architectural advice, and strategic planning with optional web research",
    //     @import("oracle.zig").execute,
    //     "amp",
    // );
}

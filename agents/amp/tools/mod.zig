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
}

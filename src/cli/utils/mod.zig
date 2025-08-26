//! CLI utilities module
//! Shared utilities for CLI operations

const std = @import("std");

// For now, provide basic utilities
pub fn printVersion() void {
    std.debug.print("DocZ v0.1.0\n");
}

pub fn printHelp() void {
    std.debug.print("DocZ - Elegant terminal AI assistant\n");
    std.debug.print("Run 'docz --help' for detailed usage information.\n");
}

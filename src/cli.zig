//! Main CLI interface using the enhanced modular architecture
//! This is the new primary CLI module that applications should use

const std = @import("std");

// Import the modular CLI system
const cli_mod = @import("cli/mod.zig");

// Re-export the main public interface
pub const EnhancedParser = cli_mod.EnhancedParser;
pub const ParsedArgs = cli_mod.ParsedArgs;
pub const CliError = cli_mod.CliError;
pub const parseArgs = cli_mod.parseArgs;
pub const parseAndHandle = cli_mod.parseAndHandle;

// Re-export modules for advanced usage
pub const core = cli_mod.core;
pub const enhanced = cli_mod.enhanced;
pub const types = cli_mod.types;
pub const commands = cli_mod.commands;
pub const interactive = cli_mod.interactive;
pub const formatters = cli_mod.formatters;
pub const utils = cli_mod.utils;

// Legacy compatibility (for gradual migration)
pub const LegacyParser = cli_mod.LegacyParser;
pub const legacyParseArgs = cli_mod.legacyParseArgs;

/// Main entry point for CLI applications
/// Handles argument parsing and built-in commands (help, version, auth)
/// Returns null if a built-in command was handled, or ParsedArgs if there's user input to process
pub fn main(allocator: std.mem.Allocator, args: [][]const u8) !?ParsedArgs {
    return try parseAndHandle(allocator, args);
}

/// Simple parsing without built-in command handling
/// Use this if you want to handle all commands yourself
pub fn parse(allocator: std.mem.Allocator, args: [][]const u8) !ParsedArgs {
    return try parseArgs(allocator, args);
}
//! Enhanced CLI with new modular architecture
//! Main interface for CLI functionality with all advanced features

const std = @import("std");
const cli_mod = @import("cli/mod.zig");

// Core CLI functionality
pub const EnhancedParser = cli_mod.EnhancedParser;
pub const ParsedArgs = cli_mod.ParsedArgs;
pub const CliError = cli_mod.CliError;
pub const parseArgs = cli_mod.parseArgs;
pub const parseAndHandle = cli_mod.parseAndHandle;

// Module re-exports
pub const core = cli_mod.core;
pub const enhanced = cli_mod.enhanced;
pub const types = cli_mod.types;
pub const commands = cli_mod.commands;
pub const interactive = cli_mod.interactive;
pub const formatters = cli_mod.formatters;
pub const utils = cli_mod.utils;

// TUI integration
pub const tui = @import("tui/mod.zig");
pub const Section = tui.Section;
pub const Menu = tui.Menu;
pub const MenuItem = tui.MenuItem;
pub const Notification = tui.Notification;
pub const NotificationHandler = interactive.notification_manager.NotificationHandler;
pub const GraphicsWidget = tui.GraphicsWidget;

// Terminal capabilities
pub const TermCaps = @import("term/caps.zig").TermCaps;
pub const getTermCaps = @import("term/caps.zig").getTermCaps;

// Advanced features
pub const HyperlinkBuilder = utils.hyperlinks.HyperlinkBuilder;
pub const CommonLinks = utils.hyperlinks.CommonLinks;
pub const LinkMenu = utils.hyperlinks.LinkMenu;
pub const CompletionEngine = interactive.CompletionEngine;
pub const CommandPalette = interactive.CommandPalette;
pub const FuzzyMatcher = interactive.FuzzyMatcher;

/// Main CLI entry point - handles full parsing and built-in commands
pub fn main(allocator: std.mem.Allocator, args: [][]const u8) !?ParsedArgs {
    return try parseAndHandle(allocator, args);
}

/// Quick CLI parsing without built-in command handling
pub fn quickParse(allocator: std.mem.Allocator, args: [][]const u8) !ParsedArgs {
    return try parseArgs(allocator, args);
}

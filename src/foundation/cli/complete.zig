//! CLI with new modular architecture
//! Main interface for CLI functionality with all features

const std = @import("std");
const components = @import("../components.zig");
const cli_mod = @import("../cli.zig");

// Core CLI functionality
pub const Parser = cli_mod.parser.Parser;
pub const ParsedArgs = cli_mod.ParsedArgs;
pub const CliError = cli_mod.CliError;
pub const parseArgs = cli_mod.parseArgs;
pub const parseAndHandle = cli_mod.parseAndHandle;

// Module re-exports
pub const core = cli_mod.core;
pub const legacy = cli_mod.parser;
pub const types = cli_mod.types;
pub const commands = cli_mod.commands;
pub const interactive = cli_mod.interactive;
pub const formatters = cli_mod.formatters;
pub const hyperlinks = cli_mod.hyperlinks;

// TUI integration
pub const tui = @import("../tui.zig");
pub const Section = tui.Section;
pub const Menu = tui.Menu;
pub const MenuItem = tui.MenuItem;
pub const Notification = tui.Notification;
pub const NotificationHandler = interactive.notification_manager.NotificationHandler;
pub const GraphicsWidget = tui.GraphicsWidget;

// Terminal capabilities
const term = @import("../term.zig");
pub const TermCaps = term.capabilities.TermCaps;
pub const getTermCaps = struct {};

// Advanced features
pub const HyperlinkBuilder = hyperlinks.hyperlinks.HyperlinkBuilder;
pub const CommonLinks = hyperlinks.hyperlinks.CommonLinks;
pub const LinkMenu = hyperlinks.hyperlinks.LinkMenu;
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

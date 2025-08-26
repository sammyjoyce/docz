//! Enhanced CLI with new modular architecture
//! Backward compatibility layer for existing CLI functionality

const std = @import("std");
const cli_mod = @import("cli/mod.zig");

// Re-export the enhanced CLI functionality
pub const core = cli_mod.core;
pub const types = cli_mod.types;
pub const commands = cli_mod.commands;
pub const interactive = cli_mod.interactive;
pub const formatters = cli_mod.formatters;
pub const utils = cli_mod.utils;

// Backward compatibility aliases
pub const ParsedArgs = cli_mod.ParsedArgs;
pub const CliError = cli_mod.CliError;
pub const parseArgs = cli_mod.parseArgs;

// Enhanced functionality exports
pub const HyperlinkBuilder = @import("cli/utils/hyperlinks.zig").HyperlinkBuilder;
pub const CommonLinks = @import("cli/utils/hyperlinks.zig").CommonLinks;
pub const LinkMenu = @import("cli/utils/hyperlinks.zig").LinkMenu;

pub const EnhancedTheme = @import("tui/themes/enhanced.zig").EnhancedTheme;
pub const ThemeManager = @import("tui/themes/enhanced.zig").ThemeManager;

pub const CompletionEngine = interactive.CompletionEngine;
pub const CommandPalette = interactive.CommandPalette;
pub const FuzzyMatcher = interactive.FuzzyMatcher;

// Enhanced TUI widgets
pub const Section = @import("tui/widgets/section.zig").Section;
pub const Menu = @import("tui/widgets/menu.zig").Menu;
pub const MenuItem = @import("tui/widgets/menu.zig").MenuItem;

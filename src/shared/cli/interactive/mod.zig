//! Interactive CLI components
//! Command palette and autocomplete functionality

pub const completion = @import("completion.zig");
pub const command_palette = @import("command_palette.zig");

// Re-export commonly used types
pub const CompletionItem = completion.CompletionItem;
pub const FuzzyMatcher = completion.FuzzyMatcher;
pub const CompletionEngine = completion.CompletionEngine;
pub const CompletionSets = completion.CompletionSets;

pub const CommandPalette = command_palette.CommandPalette;
pub const CommandPaletteResult = command_palette.CommandPaletteResult;
pub const CommandPaletteAction = command_palette.CommandPaletteAction;

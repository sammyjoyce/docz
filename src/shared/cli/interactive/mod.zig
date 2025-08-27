//! Interactive CLI components
//! Command palette and autocomplete functionality

pub const completion = @import("completion.zig");
pub const CommandPalette = @import("CommandPalette.zig");

// Re-export commonly used types
pub const CompletionItem = completion.CompletionItem;
pub const FuzzyMatcher = completion.FuzzyMatcher;
pub const CompletionEngine = completion.CompletionEngine;
pub const CompletionSets = completion.CompletionSets;

pub const Palette = CommandPalette.Palette;
pub const PaletteResult = CommandPalette.PaletteResult;
pub const PaletteAction = CommandPalette.PaletteAction;

//! Interactive CLI components
//! Command palette and autocomplete functionality

pub const completion = @import("completion.zig");
const CommandPaletteImpl = @import("interactive/command_palette.zig");

// Re-export commonly used types
pub const CompletionItem = completion.CompletionItem;
pub const FuzzyMatcher = completion.FuzzyMatcher;
pub const CompletionEngine = completion.CompletionEngine;
pub const CompletionSets = completion.CompletionSets;

// Module surface: keep prior alias while pointing to canonical impl
pub const CommandPalette = CommandPaletteImpl;

// Back-compat aliases used elsewhere
pub const Palette = CommandPaletteImpl.CommandPalette;
pub const PaletteResult = CommandPaletteImpl.CommandPaletteResult;
pub const PaletteAction = CommandPaletteImpl.CommandPaletteAction;

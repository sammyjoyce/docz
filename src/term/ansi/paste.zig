// Bracketed paste delimiters emitted by terminals when DECSET 2004 is enabled.
// Applications can look for these markers in input streams to detect pastes.
// Enabling/disabling bracketed paste mode is handled via mode.zig.

pub const BracketedPasteStart: []const u8 = "\x1b[200~";
pub const BracketedPasteEnd: []const u8 = "\x1b[201~";

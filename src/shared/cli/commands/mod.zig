//! CLI commands module
//! Organized command implementations

// Re-export command enums from core types directly
const types = @import("../core/types.zig");
pub const AuthSubcommand = types.AuthSubcommand;
pub const Command = types.Command;

// Note: Command implementations live under this directory per-file when added.
// Legacy commands (if any) are exposed via `cli.legacy` behind `-Dlegacy`.

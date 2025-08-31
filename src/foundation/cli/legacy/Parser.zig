// DEPRECATED: Legacy CLI parser retained for compatibility only.
// This shim re-exports the legacy parser under the legacy/ namespace.

const legacy = @import("core/legacy_parser.zig");

pub const Parser = legacy.Parser;
pub const Args = legacy.Args;
pub const CliError = legacy.CliError;

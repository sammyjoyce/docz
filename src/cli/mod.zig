//! CLI module entry point
//! Re-exports all CLI functionality in a clean modular structure

// Core parser and types
pub const core = @import("core/parser.zig");
pub const enhanced = @import("core/enhanced_parser.zig");
pub const types = @import("core/types.zig");

// Re-export commonly used types for convenience
pub const ParsedArgs = enhanced.ParsedArgs;
pub const CliError = enhanced.CliError;
pub const EnhancedParser = enhanced.EnhancedParser;
pub const parseArgs = enhanced.parseArgsEnhanced;
pub const parseAndHandle = enhanced.parseAndHandle;

// Legacy compatibility
pub const LegacyParser = core.Parser;
pub const legacyParseArgs = core.parseArgs;

// Commands
pub const commands = @import("commands/mod.zig");

// Interactive components
pub const interactive = @import("interactive/mod.zig");

// Formatters
pub const formatters = @import("formatters/mod.zig");

// Utilities
pub const utils = @import("utils/mod.zig");

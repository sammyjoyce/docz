//! Unified CLI Module
//! New unified CLI system with smart terminal integration

// New unified core system
pub const core = struct {
    pub const app = @import("core/app.zig");
    pub const context = @import("core/context.zig");
    pub const router = @import("core/router.zig");
    pub const types = @import("core/types.zig");
    
    // Legacy parsers for compatibility
    pub const parser = @import("core/parser.zig");
    pub const enhanced_parser = @import("core/enhanced_parser.zig");
};

// Main exports for the new system
pub const CliApp = core.app.CliApp;
pub const CliContext = core.context.CliContext;
pub const CliError = core.types.CliError;
pub const Config = core.types.Config;
pub const CommandResult = core.types.CommandResult;

// Components (smart + base)
pub const components = @import("components/mod.zig");

// Legacy compatibility - existing modules
pub const enhanced = @import("core/enhanced_parser.zig");
pub const types = @import("core/types.zig");

// Re-export commonly used legacy types for compatibility
pub const ParsedArgs = enhanced.ParsedArgs;
pub const EnhancedParser = enhanced.EnhancedParser;
pub const parseArgs = enhanced.parseArgsEnhanced;
pub const parseAndHandle = enhanced.parseAndHandle;

// Legacy compatibility
pub const LegacyParser = @import("core/parser.zig").Parser;
pub const legacyParseArgs = @import("core/parser.zig").parseArgs;

// Existing modules
pub const commands = @import("commands/mod.zig");
pub const interactive = @import("interactive/mod.zig");
pub const formatters = @import("formatters/mod.zig");
pub const utils = @import("utils/mod.zig");
pub const workflows = @import("workflows/mod.zig");
pub const themes = @import("themes/mod.zig");

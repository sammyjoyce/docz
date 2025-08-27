//! CLI Module
//! CLI system with terminal integration

// Core system
pub const Core = struct {
    pub const app = @import("core/app.zig");
    pub const state = @import("core/state.zig");
    pub const router = @import("core/Router.zig");
    pub const types = @import("core/types.zig");

    // Parsers for compatibility
    pub const parser = @import("core/parser.zig");
    // DEPRECATED: Legacy parser exports - new code should use modern CLI system via agent_main.zig
    // These are temporarily kept as comments for reference during migration
    // pub const legacy_parser = @import("core/legacy_parser.zig");
};

// Main exports
pub const App = Core.app.App;
pub const Cli = Core.state.Cli;
pub const Error = Core.types.Error;
pub const Config = Core.types.Config;
pub const CommandResult = Core.types.CommandResult;

// Components (smart + base)
pub const components = @import("components/mod.zig");

// Legacy compatibility - existing modules
pub const parser = @import("core/legacy_parser.zig");
// DEPRECATED: Legacy parser exports - new code should use modern CLI system via agent_main.zig
// These are temporarily kept as comments for reference during migration
// pub const legacy = @import("core/legacy_parser.zig");
pub const types = @import("core/types.zig");

// DEPRECATED: Legacy parser exports - new code should use modern CLI system via agent_main.zig
// These are temporarily kept as comments for reference during migration
// Re-export commonly used legacy types for compatibility
// pub const Args = legacy.Args;
// pub const Parser = legacy.Parser;
// pub const parseArgs = legacy.parseArgs;
// pub const parseAndHandle = legacy.parseAndHandle;

// DEPRECATED: Legacy parser exports - new code should use modern CLI system via agent_main.zig
// These are temporarily kept as comments for reference during migration
// Legacy compatibility
// pub const LegacyParser = @import("core/legacy_parser.zig").Parser;
// pub const legacyParseArgs = @import("core/legacy_parser.zig").parseArgs;

// Existing modules
pub const commands = @import("commands/mod.zig");
pub const interactive = @import("interactive/mod.zig");
pub const formatters = @import("formatters/mod.zig");
pub const utils = @import("utils/mod.zig");
pub const workflows = @import("workflows/mod.zig");
// pub const themes = @import("themes/mod.zig");

// Presenters are optional; excluded in minimal builds to avoid cross-module imports
// pub const presenters = @import("presenters/mod.zig");

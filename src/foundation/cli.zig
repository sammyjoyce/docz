//! CLI Module Barrel (Public API)
//! Single entry surface for the CLI: `CliApp`.
//! Direct access to submodules is phased out.

const deps = @import("internal/deps.zig");
comptime {
    deps.assertLayer(.cli);
}

pub const CliApp = @import("CliApp.zig").CliApp;

// Auth CLI components namespace
pub const Auth = struct {
    pub const Commands = @import("cli/auth/Commands.zig");
    // Additional auth CLI components can be added here

    // Convenience re-exports
    pub const runAuthCommand = Commands.runAuthCommand;
    pub const handleLoginCommand = Commands.handleLoginCommand;
    pub const handleStatusCommand = Commands.handleStatusCommand;
    pub const handleRefreshCommand = Commands.handleRefreshCommand;
};

// Components barrel re-export
// Expose CLI component surface via the main CLI barrel to avoid deep imports
// from agents. This aligns with the consolidation plan’s “barrels, not deep
// imports” guideline.
pub const components = @import("cli/components.zig");
// Commonly used component shortcuts
pub const Breadcrumb = components.Breadcrumb;

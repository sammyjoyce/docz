//! CLI Module Barrel (Public API)
//! Single entry surface for the CLI: `CliApp`.
//! Direct access to submodules is phased out.

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

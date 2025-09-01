//! CLI Module Barrel (Public API)
//! Single entry surface for the CLI: `CliApp`.
//! Direct access to submodules is phased out.

const deps = @import("internal/deps.zig");
comptime {
    deps.assertLayer(.cli);
}

pub const CliApp = @import("cli/core/app.zig").CliApp;

// Auth CLI components namespace
pub const Auth = struct {
    pub const Commands = @import("cli/auth.zig").Commands;

    // Convenience re-exports
    pub const login = Commands.login;
    pub const status = Commands.status;
    pub const whoami = Commands.whoami;
    pub const logout = Commands.logout;
    pub const testCall = Commands.testCall;
};

// Run CLI components namespace
pub const Run = struct {
    pub const Commands = @import("cli/run/Commands.zig");

    // Convenience re-exports
    pub const handleRunCommand = Commands.handleRunCommand;
    pub const RunConfig = Commands.RunConfig;
};

// Components barrel re-export
// Expose CLI component surface via the main CLI barrel to avoid deep imports
// from agents. This aligns with the consolidation plan’s “barrels, not deep
// imports” guideline.
pub const components = @import("cli/components.zig");
// Commonly used component shortcuts
pub const Breadcrumb = components.Breadcrumb;

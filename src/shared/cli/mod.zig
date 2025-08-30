//! CLI Module Barrel (Public API)
//! Single entry surface for the CLI: `CliApp`.
//! Direct access to submodules is phased out.

pub const CliApp = @import("CliApp.zig").CliApp;

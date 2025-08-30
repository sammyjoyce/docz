//! Unified CLI entry point
//! Exposes a single `CliApp` struct that encapsulates state, routing, and
//! configuration. This is the only public export of the CLI namespace.

pub const CliApp = @import("core/app.zig").CliApp;

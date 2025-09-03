//! Foundation Prelude (external facade)
//!
//! This module is the public facade that L1/L2/L3 import as `@import("foundation")`.
//! It re-exports the stable surface of the foundation platform while avoiding
//! importing the facade from within L4 itself. Leaf L4 modules must import
//! sibling barrels directly (e.g., `@import("foundation/ui.zig")`).
//!
//! Rule: Do not import this prelude from any file under `src/foundation/**`.

const std = @import("std");

// Core modules
pub const config = @import("config.zig");
pub const tools = @import("tools.zig");
pub const context = @import("context.zig");
pub const logger = @import("logger.zig");
pub const testing = @import("testing.zig");

// Terminal and rendering
pub const term = @import("term.zig");
pub const render = @import("render.zig");

// UI layers
pub const ui = @import("ui.zig");
pub const tui = @import("tui.zig");
pub const cli = @import("cli.zig");

// Network (auth lives under network)
pub const network = @import("network.zig");

// Agent support modules
pub const agent_base = @import("agent_base.zig");
pub const agent_main = @import("agent_main.zig");
pub const agent_registry = @import("agent_registry.zig");
pub const interactive_session = @import("interactive_session.zig");
pub const session = @import("session.zig");

// Common convenience re-exports
pub const Config = config.Config;
pub const Tool = tools.Tool;
pub const Component = ui.Component;
pub const App = tui.App;
pub const Http = network.Http;

// Version information
pub const version = "1.0.0";
pub const min_zig_version = "0.15.1";

// Optional exports for DI wiring from outer layers
pub const ports = struct {
    pub const auth = @import("ports/auth.zig");
};

pub const adapters = struct {
    pub const auth_network = @import("adapters/auth_network.zig");
    pub const auth_mock = @import("adapters/auth_mock.zig");
};

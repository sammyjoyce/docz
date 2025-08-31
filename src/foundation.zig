//! Unified foundation module providing access to all foundation capabilities.
//! This is the main entry point for agents to import foundation functionality.

const std = @import("std");

// Core modules - always available (engine is imported by agents directly to avoid
// duplicate module inclusion of the same source file under different names)
pub const config = @import("foundation/config.zig");
pub const tools = @import("foundation/tools.zig");
pub const context = @import("foundation/context.zig");
pub const logger = @import("foundation/logger.zig");
pub const testing = @import("foundation/testing.zig");

// Terminal and rendering modules
pub const term = @import("foundation/term.zig");
pub const render = @import("foundation/render.zig");
pub const theme = @import("foundation/theme.zig");

// UI modules
pub const ui = @import("foundation/ui.zig");
pub const tui = @import("foundation/tui.zig");
pub const cli = @import("foundation/cli.zig");

// Network module (includes auth)
pub const network = @import("foundation/network.zig");

// Agent support modules
pub const agent_base = @import("foundation/agent_base.zig");
pub const agent_main = @import("foundation/agent_main.zig");
pub const agent_launcher = @import("foundation/agent_launcher.zig");
pub const agent_registry = @import("foundation/agent_registry.zig");
pub const interactive_session = @import("foundation/interactive_session.zig");
pub const session = @import("foundation/session.zig");


// Re-export commonly used types for convenience
pub const Config = config.Config;
pub const Tool = tools.Tool;
pub const Component = ui.Component;
pub const App = tui.App;
pub const Http = network.Http;
pub const Theme = theme.Theme;

// Version information
pub const version = "1.0.0";
pub const min_zig_version = "0.15.1";

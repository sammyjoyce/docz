//! Shared infrastructure modules for all agents.
//! This module exports all shared functionality that agents can use.

pub const cli = @import("cli/mod.zig");
pub const tui = @import("tui/mod.zig");
pub const render = @import("render/mod.zig");
pub const components = @import("components/mod.zig");
pub const tools = @import("tools/mod.zig");
pub const network = struct {
    pub const anthropic = @import("network/anthropic.zig");
    pub const curl = @import("network/curl.zig");
    pub const sse = @import("network/sse.zig");
};
pub const auth = @import("auth/mod.zig");
pub const term = @import("term/mod.zig");

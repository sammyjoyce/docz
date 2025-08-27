//! Shared infrastructure modules for all agents.
//! This module exports all shared functionality that agents can use.

pub const cli = @import("cli/mod.zig");
pub const tui = @import("tui/mod.zig");
pub const render = @import("render/mod.zig");
pub const components = @import("components/mod.zig");
pub const tools = @import("tools/mod.zig");
// New guardrail barrels for refactor
pub const ui = @import("ui/mod.zig");
pub const widgets = @import("widgets/mod.zig");
pub const Network = struct {
    // Prefer the split submodule barrel; keep legacy as explicit alias
    pub const anthropic = @import("network/anthropic/mod.zig");
    pub const anthropic_legacy = @import("network/anthropic.zig");
    pub const curl = @import("network/curl.zig");
    pub const sse = @import("network/sse.zig");
    pub const client = @import("network/client.zig");
};
pub const auth = @import("auth/mod.zig");
// Re-export service types for convenience
pub const Service = auth.Service;
pub const NetworkClient = Network.client.Service;
// Align with consolidated terminal layout
pub const term = @import("term/mod.zig");

// Unified types - consolidated data structures
pub const types = @import("types.zig");

// Unified input system - located in components/input.zig
pub const input = @import("components/input.zig");

//! Shared infrastructure modules for all agents.
//! This module exports all shared functionality that agents can use.

pub const cli = @import("cli/mod.zig");
pub const tui = @import("tui/mod.zig");
pub const render = @import("render/mod.zig");
pub const components = @import("components/mod.zig");
pub const tools = @import("tools/mod.zig");
pub const Network = struct {
    // Prefer the split submodule barrel; keep legacy as explicit alias
    pub const anthropic = @import("network/anthropic/mod.zig");
    pub const anthropic_legacy = @import("network/anthropic.zig");
    pub const curl = @import("network/curl.zig");
    pub const sse = @import("network/sse.zig");
    pub const service = @import("network/service.zig");
};
pub const auth = @import("auth/mod.zig");
pub const term = @import("term_refactored/mod.zig");

// Unified types - consolidated data structures
pub const types = @import("types.zig");

// Unified input system - located in components/input.zig
pub const input = @import("components/input.zig");

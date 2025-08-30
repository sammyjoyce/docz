//! Shared infrastructure modules for all agents.
//! This barrel exports shared functionality and provides a central
//! compile-time options hook. To override defaults project-wide,
//! define at the root module (build root):
//!
//!   pub const shared_options = @import("src/shared/mod.zig").Options{
//!     .feature_tui = true,
//!     .feature_render = true,
//!     .feature_widgets = true,
//!     .feature_network_anthropic = true,
//!     .quality = .medium,
//!   };
//!
//! Notes:
//! - `shared_options` may be any struct. Submodules use `@hasField` to probe
//!   for recognized fields (e.g., `render_enable_braille`). Using `Options`
//!   is convenient, but not required if you need extra fields.
//!
//! Consumers should import features via these barrels (no deep imports).
//! Feature-gate by checking `shared.options.feature_*` at comptime.

pub const cli = @import("cli/mod.zig");
pub const tui = @import("tui/mod.zig");
pub const render = @import("render/mod.zig");
pub const components = @import("components/mod.zig");
pub const tools = @import("tools/mod.zig");
// New guardrail barrels for refactor
pub const ui = @import("ui/mod.zig");
pub const widgets = @import("widgets/mod.zig");
const build_options = @import("build_options");
// Network barrel re-export (module, not container struct)
pub const network = @import("network/mod.zig");
pub const auth = @import("auth/mod.zig");
// Re-export commonly used network types for convenience
pub const Service = network.Service;
pub const ClientError = network.ClientError;
pub const Request = network.Request;
pub const Response = network.Response;
pub const Event = network.Event;
// Backward-compat alias
pub const NetworkClient = network.Service;
// Align with consolidated terminal layout
pub const term = @import("term/mod.zig");

// Unified types - consolidated data structures
pub const types = @import("types.zig");

// Unified input system - located in components/input.zig
pub const input = @import("components/input.zig");

// -----------------------------------------------------------------------------
// Compile-time Options
// -----------------------------------------------------------------------------
const root = @import("root");

/// Global shared options that submodules may consult.
/// Override by declaring `pub const shared_options = shared.Options{...};`
pub const Options = struct {
    // Default quality tier used by renderers that support tiers
    pub const Quality = enum { low, medium, high };

    // Feature flags to selectively include subsystems
    feature_tui: bool = true,
    feature_render: bool = true,
    feature_widgets: bool = true,
    feature_network_anthropic: bool = true,
    quality: Quality = .medium,
};

/// Resolved options derived from root.shared_options when present.
pub const options: Options = blk: {
    const defaults = Options{};
    if (@hasDecl(root, "shared_options")) {
        const T = @TypeOf(root.shared_options);
        break :blk Options{
            .feature_tui = if (@hasField(T, "feature_tui")) @field(root.shared_options, "feature_tui") else defaults.feature_tui,
            .feature_render = if (@hasField(T, "feature_render")) @field(root.shared_options, "feature_render") else defaults.feature_render,
            .feature_widgets = if (@hasField(T, "feature_widgets")) @field(root.shared_options, "feature_widgets") else defaults.feature_widgets,
            .feature_network_anthropic = if (@hasField(T, "feature_network_anthropic")) @field(root.shared_options, "feature_network_anthropic") else defaults.feature_network_anthropic,
            .quality = if (@hasField(T, "quality")) @field(root.shared_options, "quality") else defaults.quality,
        };
    }
    break :blk defaults;
};

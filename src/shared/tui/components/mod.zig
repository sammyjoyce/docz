//! TUI Components Module
//! Shared terminal user interface components

// Core components
// Note: Legacy Dashboard/DiffViewer moved to examples or legacy modules. Use
// `tui.widgets.dashboard/*` for the new dashboard implementation.
pub const Authentication = @import("Authentication.zig").Authentication;
pub const Session = @import("Session.zig").Session;
pub const Progress = @import("Progress.zig").Progress;

// Submodule exports
// Note: Canvas functionality is now available through tui.canvas or tui.canvas_engine
pub const dashboard = @import("dashboard/mod.zig");

// Note: Renderer functionality has been consolidated into src/shared/render/Renderer.zig
// Note: AgentLauncher functionality is available through src/core/agent_launcher.zig

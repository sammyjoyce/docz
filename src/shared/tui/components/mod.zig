//! TUI Components Module
//! Shared terminal user interface components

// Core components
pub const Canvas = @import("canvas/Canvas.zig");
pub const Dashboard = @import("Dashboard.zig");
pub const DiffViewer = @import("DiffViewer.zig");
pub const Renderer = @import("graphics/Renderer.zig");

// Submodule exports
pub const canvas = @import("canvas/Canvas.zig");
pub const dashboard = @import("dashboard/mod.zig");
pub const graphics = @import("graphics/Renderer.zig");

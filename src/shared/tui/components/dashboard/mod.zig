//! Modern Dashboard Component System (barrel)
//! Canonical dashboard lives here. Keep this barrel minimal and valid.

// Main dashboard exports (canonical)
pub const Dashboard = @import("AdaptiveDashboard.zig").AdaptiveDashboard;
pub const DashboardConfig = @import("AdaptiveDashboard.zig").DashboardConfig;

// Theme helpers available today
pub const DashboardTheme = @import("theme.zig").DashboardTheme;

// Note: Additional submodules (renderer/layout/widgets) will be introduced in
// a later phase. Avoid importing non-existent files here to keep the barrel
// healthy even when only the canonical dashboard is used.

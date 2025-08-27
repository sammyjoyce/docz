//! Modern Dashboard Component System
//! Leverages full src/term capabilities with progressive enhancement

pub const core = struct {
    pub const Renderer = @import("renderer.zig").DashboardRenderer;
    pub const Layout = @import("layout.zig").LayoutManager;
    pub const Theme = @import("theme.zig").DashboardTheme;
};

pub const widgets = struct {
    pub const MetricCard = @import("widgets/metric_card.zig");
    pub const Chart = @import("widgets/chart.zig");
    pub const ProgressRing = @import("widgets/progress_ring.zig");
    pub const StatusPanel = @import("widgets/status_panel.zig");
    pub const DataTable = @import("widgets/data_table.zig");
    pub const NotificationCenter = @import("widgets/notification_center.zig");
};

pub const adaptive = struct {
    pub const GraphicsRenderer = @import("adaptive/graphics_renderer.zig");
    pub const CapabilityMatcher = @import("adaptive/capability_matcher.zig");
    pub const FallbackChain = @import("adaptive/fallback_chain.zig");
};

// Main dashboard exports
pub const Dashboard = @import("dashboard.zig").AdaptiveDashboard;
pub const DashboardConfig = @import("dashboard.zig").DashboardConfig;

// Convenience re-exports
pub const Renderer = core.Renderer;
pub const LayoutManager = core.Layout;
pub const DashboardTheme = core.Theme;

# UX Improvements Integration Guide

## Table of Contents

1. [Overview](#overview)
2. [New UX Improvements Catalog](#new-ux-improvements-catalog)
3. [Enhanced Agent Interface Integration](#enhanced-agent-interface-integration)
4. [OAuth Callback Server Implementation](#oauth-callback-server-implementation)
5. [Real-time Dashboard Integration](#real-time-dashboard-integration)
6. [Upgrading Markdown Agent](#upgrading-markdown-agent)
7. [Before/After Comparisons](#beforeafter-comparisons)
8. [New Capabilities Summary](#new-capabilities-summary)
9. [Migration Guide](#migration-guide)
10. [Code Examples](#code-examples)
11. [Troubleshooting](#troubleshooting)

## Overview

This guide provides comprehensive instructions for integrating the new UX improvements into existing and new agents. The enhanced features provide modern terminal experiences with rich interactions, beautiful interfaces, and seamless workflows.

### Key Improvements

- **Enhanced Agent Interface** - Modern, adaptive terminal interface with rich UI components
- **OAuth Callback Server** - Robust authentication flow with automatic code capture
- **Real-time Dashboards** - Live monitoring with charts, metrics, and performance data
- **Interactive Markdown Editor** - Split-screen editing with live preview
- **Smart Command Palette** - Fuzzy search and intelligent command discovery
- **Adaptive Rendering** - Terminal capability detection and graceful degradation
- **Theme System** - Customizable color schemes and visual styles

## New UX Improvements Catalog

### 1. Enhanced Agent Interface (`src/core/agent_interface.zig`)

Modern agent interface leveraging all terminal capabilities:

```zig
// Features Available
- Advanced terminal integration (mouse, graphics, notifications)
- Rich CLI/TUI experience with command palette and dashboards
- OAuth integration with authentication wizards
- Adaptive rendering based on terminal capabilities
- Session management with full state preservation
- Beautiful responsive interface with animations
```

### 2. OAuth Callback Server (`src/shared/auth/oauth/callback_server.zig`)

Local HTTP server for OAuth authorization code capture:

```zig
// Features
- Configurable port (default: 8080)
- Automatic authorization code capture
- PKCE verification for security
- State parameter validation
- Beautiful success/error pages
- Real-time terminal status updates
- Timeout handling and cleanup
- Support for multiple concurrent flows
```

### 3. Enhanced Session Dashboard (`src/core/agent_dashboard.zig`)

Comprehensive real-time monitoring:

```zig
// Dashboard Components
- Real-time statistics and metrics
- Live charts with dynamic data visualization
- Cost tracking (tokens and API usage)
- Performance metrics (response time, throughput)
- Resource monitoring (memory, CPU, network)
- Network status indicators
- Theme support (dark/light modes)
```

### 4. Interactive Markdown Editor (`agents/markdown/enhanced_markdown_editor.zig`)

Feature-rich markdown editing environment:

```zig
// Editor Features
- Syntax highlighting with themes
- Live preview with synchronized scrolling
- Auto-completion and snippets
- Table of contents generation
- Export to HTML/PDF
- Multi-cursor support
- Smart indentation
- Bracket matching
```

### 5. Smart Command Palette (`src/shared/tui/widgets/rich/command_palette.zig`)

Intelligent command discovery:

```zig
// Palette Features
- Fuzzy search with scoring algorithm
- Frecency-based command history
- Visual match highlighting
- Command categorization
- Keyboard-driven navigation
- Session integration
```

## Enhanced Agent Interface Integration

### Step 1: Update Agent Configuration

Modify your agent's configuration to use the enhanced interface:

```zig
// agents/your_agent/agent.zig
const enhanced_interface = @import("../../src/core/agent_interface.zig");

pub const Config = struct {
    // Base configuration
    base_config: enhanced_interface.Config,
    
    // Your agent-specific settings
    custom_settings: CustomSettings = .{},
};

pub const CustomSettings = struct {
    // Add your custom configuration fields
    enable_special_feature: bool = true,
    max_operations: u32 = 100,
};
```

### Step 2: Initialize Enhanced Agent

```zig
// agents/your_agent/main.zig
const std = @import("std");
const enhanced_interface = @import("../../src/core/agent_interface.zig");
const agent_impl = @import("agent.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create enhanced agent with all UX features
    const agent = try enhanced_interface.createAgent(allocator, .{
        .base_config = .{
            .ui_settings = .{
                .enable_dashboard = true,
                .enable_mouse = true,
                .enable_graphics = true,
                .enable_notifications = true,
                .enable_command_palette = true,
                .enable_animations = true,
                .theme = "cyberpunk", // or "auto" for system detection
            },
            .session_settings = .{
                .enable_persistence = true,
                .auto_save = true,
                .session_dir = ".agent_sessions",
            },
            .interactive_features = .{
                .enable_rich_prompt = true,
                .enable_syntax_highlighting = true,
                .enable_auto_complete = true,
            },
        },
    });
    defer agent.deinit();
    
    // Run in enhanced interactive mode
    try agent.runInteractive();
}
```

### Step 3: Implement Agent Methods

```zig
// agents/your_agent/agent.zig
pub const YourAgent = struct {
    config: Config,
    interface: *enhanced_interface.Interface,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        return .{
            .allocator = allocator,
            .config = config,
            .interface = try enhanced_interface.create(allocator, config.base_config),
        };
    }
    
    pub fn runInteractive(self: *Self) !void {
        // Start dashboard if enabled
        if (self.config.base_config.ui_settings.enable_dashboard) {
            try self.interface.startDashboard();
        }
        
        // Main interaction loop with enhanced UI
        while (true) {
            // Use rich prompt with auto-complete
            const input = try self.interface.getRichInput(.{
                .prompt = "Enter command: ",
                .enable_history = true,
                .enable_suggestions = true,
            });
            
            // Process with visual feedback
            try self.interface.showProgress("Processing...");
            const result = try self.processCommand(input);
            try self.interface.hideProgress();
            
            // Display with syntax highlighting
            try self.interface.displayRichOutput(result, .{
                .syntax = "markdown",
                .theme = self.config.base_config.ui_settings.theme,
            });
        }
    }
};
```

## OAuth Callback Server Implementation

### Step 1: Configure OAuth Settings

```zig
// agents/your_agent/auth_config.zon
.{
    .oauth = .{
        .client_id = "your_client_id",
        .auth_url = "https://provider.com/oauth/authorize",
        .token_url = "https://provider.com/oauth/token",
        .redirect_uri = "http://localhost:8080/callback",
        .scopes = &[_][]const u8{ "read", "write" },
        .use_pkce = true,
    },
    .callback_server = .{
        .port = 8080,
        .timeout_ms = 300_000, // 5 minutes
        .show_success_page = true,
        .auto_close = true,
    },
}
```

### Step 2: Implement OAuth Flow

```zig
const oauth = @import("../../src/shared/auth/oauth/mod.zig");
const callback_server = @import("../../src/shared/auth/oauth/callback_server.zig");

pub fn authenticateWithOAuth(allocator: std.mem.Allocator) !oauth.TokenResponse {
    // Create callback server
    var server = try callback_server.CallbackServer.init(allocator, .{
        .port = 8080,
        .timeout_ms = 300_000,
        .show_success_page = true,
        .verbose = true,
    });
    defer server.deinit();
    
    // Start server in background
    try server.start();
    
    // Generate OAuth URL with PKCE
    const auth_params = try oauth.generateAuthUrl(allocator, .{
        .client_id = "your_client_id",
        .redirect_uri = "http://localhost:8080/callback",
        .scopes = &[_][]const u8{ "read", "write" },
        .use_pkce = true,
    });
    defer auth_params.deinit(allocator);
    
    // Display auth URL with clickable link (OSC 8)
    try displayAuthUrl(auth_params.auth_url);
    
    // Wait for callback with visual progress
    const auth_result = try server.waitForCallback(.{
        .expected_state = auth_params.state,
        .show_progress = true,
    });
    defer auth_result.deinit(allocator);
    
    // Exchange code for token
    const token = try oauth.exchangeCodeForToken(allocator, .{
        .code = auth_result.code,
        .verifier = auth_params.verifier,
        .client_id = "your_client_id",
        .client_secret = "your_secret", // If not using PKCE
        .redirect_uri = "http://localhost:8080/callback",
    });
    
    return token;
}

fn displayAuthUrl(url: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    
    // Use OSC 8 for clickable hyperlink
    try stdout.print("\n🔐 OAuth Authentication Required\n", .{});
    try stdout.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});
    
    // Clickable link with OSC 8
    try stdout.print("\x1b]8;;{s}\x1b\\", .{url});
    try stdout.print("📋 Click here to authenticate", .{});
    try stdout.print("\x1b]8;;\x1b\\\n\n", .{});
    
    try stdout.print("Or manually visit:\n{s}\n\n", .{url});
}
```

### Step 3: Enhanced OAuth Wizard Integration

```zig
const enhanced_oauth = @import("../../src/shared/auth/tui/enhanced_oauth_wizard.zig");

pub fn runOAuthWizard(allocator: std.mem.Allocator) !void {
    // Create enhanced OAuth wizard
    var wizard = try enhanced_oauth.EnhancedOAuthWizard.init(allocator, .{
        .enable_animations = true,
        .show_progress_bar = true,
        .enable_notifications = true,
        .theme = "modern",
    });
    defer wizard.deinit();
    
    // Run the complete flow with visual feedback
    const result = try wizard.runFlow(.{
        .provider = "github", // or "google", "microsoft", etc.
        .scopes = &[_][]const u8{ "repo", "user" },
        .use_callback_server = true,
    });
    
    // Save tokens securely
    try saveTokens(allocator, result.tokens);
    
    // Show success notification
    try wizard.showSuccessNotification("Authentication successful!");
}
```

## Real-time Dashboard Integration

### Step 1: Configure Dashboard Components

```zig
// agents/your_agent/dashboard_config.zon
.{
    .dashboard = .{
        .layout = "grid", // or "flex", "tabs"
        .refresh_interval_ms = 1000,
        .components = &[_]Component{
            .{
                .type = "stats",
                .position = .{ .row = 0, .col = 0, .width = 2, .height = 1 },
                .config = .{
                    .title = "Session Statistics",
                    .metrics = &[_][]const u8{
                        "requests_handled",
                        "tokens_used",
                        "response_time_avg",
                    },
                },
            },
            .{
                .type = "chart",
                .position = .{ .row = 1, .col = 0, .width = 3, .height = 2 },
                .config = .{
                    .title = "Performance Metrics",
                    .chart_type = "line",
                    .data_source = "performance_monitor",
                },
            },
            .{
                .type = "cost_tracker",
                .position = .{ .row = 0, .col = 2, .width = 1, .height = 1 },
                .config = .{
                    .title = "API Costs",
                    .show_projection = true,
                },
            },
        },
    },
}
```

### Step 2: Implement Dashboard

```zig
const dashboard = @import("../../src/core/agent_dashboard.zig");

pub const AgentDashboard = struct {
    allocator: std.mem.Allocator,
    dashboard_instance: *dashboard.Dashboard,
    metrics_collector: MetricsCollector,
    update_thread: ?std.Thread,
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        const config = try loadDashboardConfig(allocator);
        
        return .{
            .allocator = allocator,
            .dashboard_instance = try dashboard.Dashboard.init(allocator, config),
            .metrics_collector = try MetricsCollector.init(allocator),
            .update_thread = null,
        };
    }
    
    pub fn start(self: *Self) !void {
        // Start dashboard rendering
        try self.dashboard_instance.start();
        
        // Start metrics collection thread
        self.update_thread = try std.Thread.spawn(.{}, updateMetrics, .{self});
    }
    
    fn updateMetrics(self: *Self) void {
        while (self.dashboard_instance.isRunning()) {
            // Collect metrics
            const metrics = self.metrics_collector.collect() catch continue;
            
            // Update dashboard components
            self.dashboard_instance.updateStats("requests_handled", metrics.requests) catch {};
            self.dashboard_instance.updateStats("tokens_used", metrics.tokens) catch {};
            self.dashboard_instance.updateStats("response_time_avg", metrics.avg_response) catch {};
            
            // Update chart data
            self.dashboard_instance.addChartPoint("performance", .{
                .x = std.time.timestamp(),
                .y = metrics.avg_response,
            }) catch {};
            
            // Update cost tracking
            self.dashboard_instance.updateCost(metrics.estimated_cost) catch {};
            
            // Sleep for refresh interval
            std.time.sleep(1_000_000_000); // 1 second
        }
    }
};
```

### Step 3: Live Chart Integration

```zig
const charts = @import("../../src/shared/render/components/charts.zig");

pub fn createLiveChart(allocator: std.mem.Allocator) !*charts.LiveChart {
    return try charts.LiveChart.init(allocator, .{
        .title = "Real-time Performance",
        .type = .line,
        .width = 60,
        .height = 15,
        .max_points = 100,
        .update_interval_ms = 500,
        .style = .{
            .border = .rounded,
            .colors = .gradient,
            .show_grid = true,
            .show_legend = true,
        },
    });
}

// Usage in dashboard
pub fn addPerformanceChart(dashboard: *Dashboard) !void {
    const chart = try createLiveChart(dashboard.allocator);
    
    // Add data source
    try chart.addDataSource("response_time", .{
        .label = "Response Time (ms)",
        .color = .blue,
        .style = .smooth,
    });
    
    try chart.addDataSource("throughput", .{
        .label = "Requests/sec",
        .color = .green,
        .style = .bars,
    });
    
    // Add to dashboard
    try dashboard.addComponent(chart, .{
        .position = .{ .x = 0, .y = 10 },
        .auto_refresh = true,
    });
}
```

## Upgrading Markdown Agent

### Step 1: Current Markdown Agent Structure

```zig
// Before: Basic markdown agent
// agents/markdown/main.zig (OLD)
pub fn main() !void {
    // Basic CLI argument parsing
    const args = try std.process.argsAlloc(allocator);
    // Simple text processing
    const result = try processMarkdown(args[1]);
    // Basic output
    try stdout.print("{s}\n", .{result});
}
```

### Step 2: Upgrade to Enhanced Editor

```zig
// After: Enhanced markdown agent
// agents/markdown/main.zig (NEW)
const enhanced_editor = @import("enhanced_markdown_editor.zig");
const enhanced_interface = @import("../../src/core/agent_interface.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    // Check for interactive mode
    if (args.len > 1 and std.mem.eql(u8, args[1], "edit")) {
        // Launch enhanced interactive editor
        try launchEnhancedEditor(allocator, args[2..]);
    } else {
        // Run standard agent mode with enhanced interface
        try runEnhancedAgent(allocator, args);
    }
}

fn launchEnhancedEditor(allocator: std.mem.Allocator, args: [][]u8) !void {
    // Create enhanced markdown editor
    var editor = try enhanced_editor.MarkdownEditor.init(allocator, .{
        .base_config = .{
            .ui_settings = .{
                .enable_dashboard = true,
                .enable_mouse = true,
                .enable_graphics = true,
                .theme = "github-dark",
            },
        },
        .editor_settings = .{
            .syntax_highlighting = true,
            .auto_complete = true,
            .smart_indent = true,
            .multi_cursor = true,
        },
        .preview_settings = .{
            .live_preview = true,
            .enable_mermaid = true,
            .enable_math = true,
        },
    });
    defer editor.deinit();
    
    // Load file if provided
    if (args.len > 0) {
        try editor.loadFile(args[0]);
    }
    
    // Run interactive editor with split-screen
    try editor.runInteractive();
}
```

### Step 3: Add Interactive Features

```zig
// agents/markdown/enhanced_features.zig
pub const EnhancedFeatures = struct {
    allocator: std.mem.Allocator,
    editor: *enhanced_editor.MarkdownEditor,
    
    // Split-screen editing
    pub fn enableSplitScreen(self: *Self) !void {
        try self.editor.setLayout(.{
            .mode = .split_vertical,
            .left_pane = .editor,
            .right_pane = .preview,
            .sync_scroll = true,
        });
    }
    
    // Live preview with hot reload
    pub fn enableLivePreview(self: *Self) !void {
        try self.editor.preview.enable(.{
            .auto_refresh = true,
            .refresh_delay_ms = 300,
            .render_mermaid = true,
            .render_math = true,
            .syntax_highlight = true,
        });
    }
    
    // Table of contents generation
    pub fn generateTOC(self: *Self) !void {
        const toc = try self.editor.generateTableOfContents();
        try self.editor.sidebar.display(toc);
    }
    
    // Export capabilities
    pub fn exportDocument(self: *Self, format: ExportFormat) !void {
        const exporter = try self.editor.getExporter(format);
        const output = try exporter.export(self.editor.getContent());
        
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "export.{s}",
            .{@tagName(format)},
        );
        defer self.allocator.free(filename);
        
        try std.fs.cwd().writeFile(filename, output);
        
        // Show success notification
        try self.editor.showNotification(.{
            .type = .success,
            .title = "Export Complete",
            .message = try std.fmt.allocPrint(
                self.allocator,
                "Exported to {s}",
                .{filename},
            ),
        });
    }
};
```

## Before/After Comparisons

### 1. Authentication Flow

#### Before (Basic)
```bash
$ ./agent auth
Enter API key: _____
Saved to ~/.agent/config
```

#### After (Enhanced)
```bash
$ ./agent auth
🔐 OAuth Authentication Wizard
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Step 1: Opening browser...
🌐 Click here to authenticate [clickable link]

⏳ Waiting for authorization...
━━━━━━━━━ 65% [███████████░░░░░] ETA: 8s

✅ Authentication successful!
🔑 Token saved securely
📊 Rate limits: 1000 requests/hour
```

### 2. Command Input

#### Before (Basic)
```bash
$ ./agent
> help
Available commands: ...
> process file.md
Processing...
Done.
```

#### After (Enhanced)
```bash
$ ./agent
╭─ AI Agent v2.0 ─────────────────────────────────╮
│ Welcome! Press Ctrl+P for command palette        │
│ Mouse support enabled • Theme: Cyberpunk         │
╰──────────────────────────────────────────────────╯

> proc[TAB]
  └─ process (Process a markdown file)
     process-batch (Process multiple files)
     process-directory (Process all files in directory)

> process file.md
⠋ Processing file.md...
  ████████████░░░░░ 75% [12.3s elapsed]
  
✅ Processing complete!
📊 Stats: 234 lines • 1.2k tokens • 0.8s
```

### 3. Dashboard View

#### Before (None)
```bash
# No dashboard available
```

#### After (Enhanced)
```bash
╭─ Session Dashboard ──────────────────────────────╮
│ ┌─ Statistics ─────┬─ Performance ──────────┐   │
│ │ Requests: 156    │ Avg Response: 234ms     │   │
│ │ Tokens: 45,234   │ Throughput: 12 req/s    │   │
│ │ Cost: $0.89      │ Success Rate: 99.2%     │   │
│ └──────────────────┴────────────────────────┘   │
│                                                  │
│ ┌─ Live Chart ─────────────────────────────────┐ │
│ │     ▂▄▆█▇▅▃▂▄▆████▇▅▃▂▄▆█▇▅▃                │ │
│ │ 300ms ─────────────────────────              │ │
│ │ 200ms ─────────────────────────              │ │
│ │ 100ms ─────────────────────────              │ │
│ │        └─────────────────────────┘           │ │
│ │        0s          30s          60s          │ │
│ └──────────────────────────────────────────────┘ │
╰──────────────────────────────────────────────────╯
```

### 4. Markdown Editing

#### Before (Basic)
```bash
$ ./markdown-agent edit file.md
# Editing file.md
# Type :w to save, :q to quit
```

#### After (Enhanced)
```bash
┌─ Editor ──────────────┬─ Live Preview ─────────┐
│ # My Document 🚀      │ My Document 🚀         │
│ │                     │                        │
│ ## Features           │ Features               │
│ - Syntax highlight│   │ • Syntax highlighting  │
│ - Live preview        │ • Live preview         │
│ - Auto-complete       │ • Auto-complete        │
│                       │                        │
│ ```zig                │ ┌────────────────────┐ │
│ const x = 42;         │ │ const x = 42;      │ │
│ ```                   │ └────────────────────┘ │
└───────────────────────┴────────────────────────┘
 Ln 8, Col 15 • Markdown • Modified • Auto-save ON
```

## New Capabilities Summary

### Terminal Capabilities
- **Mouse Support**: Click buttons, select text, drag to scroll
- **Graphics Rendering**: Charts, progress bars, visualizations
- **OSC 8 Hyperlinks**: Clickable URLs in terminal
- **Notifications**: Desktop notifications for important events
- **Themes**: Dark/light modes with custom color schemes
- **Animations**: Smooth transitions and progress indicators

### UI Components
- **Command Palette**: Fuzzy search with Ctrl+P
- **Rich Prompts**: Auto-complete, syntax highlighting, history
- **Progress Bars**: Gradient styles with ETA calculations
- **Live Charts**: Real-time data visualization
- **Split Views**: Synchronized panes for editing
- **Status Bars**: Contextual information display

### Agent Features
- **Session Persistence**: Save and restore agent state
- **Dashboard Monitoring**: Real-time metrics and analytics
- **OAuth Integration**: Complete authentication flows
- **Export Capabilities**: Multiple output formats
- **Network Monitoring**: Connection status indicators
- **Cost Tracking**: Token usage and API cost monitoring

### Developer Features
- **Modular Architecture**: Easy component integration
- **Event System**: Reactive updates and notifications
- **Configuration Management**: ZON-based settings
- **Error Handling**: Graceful degradation and recovery
- **Testing Support**: Mock interfaces for testing
- **Documentation**: Inline help and tooltips

## Migration Guide

### Phase 1: Assessment

1. **Inventory Current Features**
   ```zig
   // List current agent capabilities
   - Basic CLI arguments
   - Simple text processing
   - File I/O operations
   - API communication
   ```

2. **Identify Enhancement Opportunities**
   ```zig
   // Determine which features to add
   - [ ] Enhanced interface
   - [ ] OAuth authentication
   - [ ] Dashboard monitoring
   - [ ] Interactive editing
   - [ ] Command palette
   ```

### Phase 2: Preparation

1. **Update Dependencies**
   ```zig
   // build.zig.zon
   .{
       .dependencies = .{
           .enhanced_interface = .{
               .path = "src/core/agent_interface.zig",
           },
           .auth = .{
               .path = "src/shared/auth/mod.zig",
           },
           .dashboard = .{
               .path = "src/core/agent_dashboard.zig",
           },
       },
   }
   ```

2. **Create Configuration Files**
   ```zig
   // agents/your_agent/enhanced_config.zon
   .{
       .ui_settings = .{
           .enable_dashboard = true,
           .enable_mouse = true,
           .theme = "auto",
       },
   }
   ```

### Phase 3: Implementation

1. **Update Main Entry Point**
   ```zig
   // Minimal changes to main.zig
   const enhanced = @import("enhanced_interface.zig");
   
   pub fn main() !void {
       // Check for --enhanced flag
       if (shouldUseEnhanced()) {
           try enhanced.run();
       } else {
           try legacyMain();
       }
   }
   ```

2. **Add Enhanced Mode Gradually**
   ```zig
   // Start with basic enhancements
   pub fn runEnhanced() !void {
       // Phase 1: Add dashboard
       if (config.enable_dashboard) {
           try showDashboard();
       }
       
       // Phase 2: Add OAuth
       if (config.enable_oauth) {
           try authenticateOAuth();
       }
       
       // Phase 3: Add full interface
       if (config.enable_full_ui) {
           try runFullInterface();
       }
   }
   ```

### Phase 4: Testing

1. **Test Individual Components**
   ```zig
   test "dashboard initialization" {
       const dashboard = try Dashboard.init(allocator, .{});
       defer dashboard.deinit();
       try testing.expect(dashboard.isReady());
   }
   ```

2. **Integration Testing**
   ```zig
   test "enhanced interface integration" {
       const agent = try createTestAgent();
       defer agent.deinit();
       
       try agent.enableDashboard();
       try agent.runCommand("test");
       
       const metrics = try agent.getMetrics();
       try testing.expect(metrics.requests > 0);
   }
   ```

### Phase 5: Deployment

1. **Gradual Rollout**
   ```bash
   # Use feature flags
   ./agent --enhanced-ui=dashboard  # Dashboard only
   ./agent --enhanced-ui=oauth      # OAuth only
   ./agent --enhanced-ui=full       # All features
   ```

2. **Documentation Update**
   ```markdown
   ## New Enhanced Mode
   
   To use enhanced features:
   ```bash
   ./agent --enhanced
   ```
   
   Features available:
   - Real-time dashboard (--dashboard)
   - OAuth authentication (--oauth)
   - Interactive editor (--editor)
   ```

## Code Examples

### Example 1: Complete Enhanced Agent

```zig
// agents/example/enhanced_agent.zig
const std = @import("std");
const enhanced = @import("../../src/core/agent_interface.zig");
const dashboard = @import("../../src/core/agent_dashboard.zig");
const oauth = @import("../../src/shared/auth/oauth/mod.zig");

pub const EnhancedExampleAgent = struct {
    allocator: std.mem.Allocator,
    interface: *enhanced.Interface,
    dashboard: *dashboard.Dashboard,
    auth_manager: *oauth.AuthManager,
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .interface = try enhanced.Interface.init(allocator, .{
                .enable_all_features = true,
            }),
            .dashboard = try dashboard.Dashboard.init(allocator, .{}),
            .auth_manager = try oauth.AuthManager.init(allocator, .{}),
        };
    }
    
    pub fn run(self: *Self) !void {
        // Authenticate if needed
        if (!self.auth_manager.isAuthenticated()) {
            try self.runOAuthFlow();
        }
        
        // Start dashboard
        try self.dashboard.start();
        
        // Main loop with enhanced interface
        while (true) {
            const command = try self.interface.getCommand();
            
            switch (command) {
                .process => |file| {
                    try self.processWithProgress(file);
                },
                .dashboard => {
                    try self.dashboard.toggle();
                },
                .quit => break,
            }
            
            // Update metrics
            try self.dashboard.updateMetrics(self.getMetrics());
        }
    }
};
```

### Example 2: OAuth Integration

```zig
// Complete OAuth flow with all enhancements
pub fn authenticateWithEnhancements(allocator: std.mem.Allocator) !void {
    // Create enhanced OAuth wizard
    var wizard = try EnhancedOAuthWizard.init(allocator, .{
        .provider = "github",
        .theme = "modern",
        .enable_animations = true,
    });
    defer wizard.deinit();
    
    // Show animated introduction
    try wizard.showIntro();
    
    // Start callback server
    var server = try CallbackServer.init(allocator, .{
        .port = 8080,
        .show_success_page = true,
    });
    defer server.deinit();
    try server.start();
    
    // Generate and display auth URL
    const auth_url = try wizard.generateAuthUrl();
    try wizard.displayClickableUrl(auth_url);
    
    // Wait with progress bar
    const result = try wizard.waitForAuth(.{
        .show_progress = true,
        .timeout_ms = 300_000,
    });
    
    // Exchange and save tokens
    const tokens = try wizard.exchangeCode(result.code);
    try wizard.saveTokens(tokens);
    
    // Show success notification
    try wizard.showSuccess("Authentication complete!");
}
```

### Example 3: Dashboard with Live Updates

```zig
// Real-time dashboard with all components
pub fn createFullDashboard(allocator: std.mem.Allocator) !*Dashboard {
    const dash = try Dashboard.init(allocator, .{
        .layout = .grid,
        .theme = "cyberpunk",
    });
    
    // Add statistics panel
    try dash.addComponent(.{
        .type = .stats,
        .metrics = &[_]Metric{
            .{ .name = "Requests", .value = 0 },
            .{ .name = "Tokens", .value = 0 },
            .{ .name = "Cost", .value = 0.0 },
        },
    });
    
    // Add live chart
    try dash.addComponent(.{
        .type = .chart,
        .config = .{
            .title = "Performance",
            .type = .line,
            .max_points = 100,
        },
    });
    
    // Add cost tracker
    try dash.addComponent(.{
        .type = .cost_tracker,
        .config = .{
            .show_projection = true,
            .alert_threshold = 10.0,
        },
    });
    
    // Start update loop
    try dash.startUpdateLoop(1000); // 1 second refresh
    
    return dash;
}
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Terminal Compatibility

**Problem**: Features not working in certain terminals

**Solution**:
```zig
// Add terminal detection
const term_type = try detectTerminal();
const features = try getTerminalFeatures(term_type);

// Adapt features based on capabilities
if (!features.supports_mouse) {
    config.ui_settings.enable_mouse = false;
}
if (!features.supports_graphics) {
    config.ui_settings.enable_graphics = false;
}
```

#### 2. OAuth Callback Issues

**Problem**: Callback server fails to start

**Solution**:
```zig
// Try alternative ports
const ports = [_]u16{ 8080, 8081, 8082, 3000 };
for (ports) |port| {
    server.config.port = port;
    server.start() catch |err| {
        if (err == error.AddressInUse) continue;
        return err;
    };
    break;
}
```

#### 3. Dashboard Performance

**Problem**: Dashboard causes high CPU usage

**Solution**:
```zig
// Adjust refresh rates
dashboard.config.refresh_interval_ms = 2000; // Increase from 1000
dashboard.config.enable_animations = false;  // Disable animations
dashboard.config.chart_max_points = 50;      // Reduce data points
```

#### 4. Memory Usage

**Problem**: Enhanced features use too much memory

**Solution**:
```zig
// Use arena allocator for temporary data
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// Configure limits
config.limits = .{
    .max_chart_points = 100,
    .history_size = 50,
    .cache_size_mb = 10,
};
```

### Debug Mode

Enable debug mode for troubleshooting:

```zig
// Enable verbose logging
config.debug = .{
    .enable_logging = true,
    .log_level = .debug,
    .log_file = "agent_debug.log",
    .show_timings = true,
    .trace_ui_events = true,
};

// Use debug build
// zig build -Dagent=your_agent -Ddebug=true
```

### Getting Help

1. **Check Documentation**
   - Read `docs/UX.md` for feature details
   - Review `AGENTS.md` for architecture
   - See example agents in `agents/`

2. **Run Diagnostics**
   ```bash
   ./agent --diagnose
   # Shows terminal capabilities, config, and system info
   ```

3. **Enable Verbose Mode**
   ```bash
   ./agent --verbose --debug
   # Shows detailed operation logs
   ```

4. **Test Individual Components**
   ```bash
   # Test dashboard only
   ./agent --test-dashboard
   
   # Test OAuth only  
   ./agent --test-oauth
   
   # Test terminal capabilities
   ./agent --test-terminal
   ```

## Conclusion

The new UX improvements transform the agent experience from basic CLI tools into rich, interactive terminal applications. By following this guide, you can incrementally adopt these enhancements while maintaining backward compatibility.

Key benefits:
- **Better User Experience**: Rich, interactive interfaces
- **Improved Productivity**: Smart features like command palette and auto-complete
- **Enhanced Monitoring**: Real-time dashboards and metrics
- **Seamless Authentication**: OAuth flows with visual feedback
- **Modern Terminal Features**: Mouse, graphics, animations

Start with the features most valuable to your use case and gradually expand. The modular architecture ensures you only include what you need, keeping your agent lean and performant.

For additional examples and implementation details, refer to:
- `agents/markdown/` - Full implementation of enhanced markdown editor
- `examples/cli_demo/` - CLI component demonstrations
- `src/shared/tui/demos/` - TUI feature showcases
- `tests/` - Integration test examples
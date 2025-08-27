# UX Improvements Integration Guide

## Table of Contents

1. [Overview](#overview)
2. [OAuth Flow with Progressive Enhancement](#oauth-flow-with-progressive-enhancement)
3. [Markdown Agent Interactive Session Enhancements](#markdown-agent-interactive-session-enhancements)
4. [Unified Agent Startup and Branding](#unified-agent-startup-and-branding)
5. [Error Handling UX Patterns](#error-handling-ux-patterns)
6. [Progress Feedback Patterns](#progress-feedback-patterns)
7. [Interactive Help System](#interactive-help-system)
8. [Implementation Examples and Code Patterns](#implementation-examples-and-code-patterns)
9. [Component Reference](#component-reference)
10. [Best Practices](#best-practices)

## Overview

This guide provides comprehensive instructions for implementing modern UX improvements across all agents' CLI and TUI interfaces. The patterns leverage existing terminal UI components while introducing progressive enhancements that gracefully adapt to terminal capabilities.

### Core Principles

- **Progressive Enhancement**: Start with basic functionality, enhance based on terminal capabilities
- **Consistency**: Unified patterns across all agents
- **Accessibility**: Keyboard-first navigation with screen reader support
- **Performance**: Optimized rendering and minimal latency
- **Feedback**: Clear, immediate user feedback for all actions
- **Discoverability**: Intuitive interfaces with built-in help

## OAuth Flow with Progressive Enhancement

### Architecture Overview

The OAuth flow implements a three-tier progressive enhancement strategy:

1. **Basic Mode**: Simple URL display with manual code input
2. **Enhanced Mode**: Local callback server with automatic code capture
3. **Advanced Mode**: Full TUI wizard with visual feedback and animations

### Implementation Pattern

```zig
//! OAuth Flow with Progressive Enhancement
//! agents/your_agent/auth/oauth_flow.zig

const std = @import("std");
const auth = @import("../../../src/shared/auth/mod.zig");
const term = @import("../../../src/shared/term/mod.zig");
const tui = @import("../../../src/shared/tui/mod.zig");

pub const OAuthFlowConfig = struct {
    /// OAuth provider configuration
    provider: auth.oauth.ProviderConfig,
    
    /// Terminal capability requirements
    capabilities: struct {
        min_terminal: term.TerminalLevel = .basic,
        require_colors: bool = false,
        require_mouse: bool = false,
        require_unicode: bool = false,
    } = .{},
    
    /// Progressive enhancement levels
    enhancement: struct {
        use_callback_server: bool = true,
        use_visual_wizard: bool = true,
        use_animations: bool = true,
        use_notifications: bool = true,
    } = .{},
    
    /// UI configuration
    ui: struct {
        show_progress: bool = true,
        show_instructions: bool = true,
        theme: []const u8 = "default",
        branding: ?BrandingConfig = null,
    } = .{},
};

/// Progressive OAuth flow implementation
pub const ProgressiveOAuthFlow = struct {
    allocator: std.mem.Allocator,
    config: OAuthFlowConfig,
    terminal_level: term.TerminalLevel,
    
    pub fn init(allocator: std.mem.Allocator, config: OAuthFlowConfig) !ProgressiveOAuthFlow {
        const terminal_level = try term.detectCapabilities();
        return .{
            .allocator = allocator,
            .config = config,
            .terminal_level = terminal_level,
        };
    }
    
    pub fn run(self: *ProgressiveOAuthFlow) !auth.oauth.TokenResponse {
        // Determine enhancement level based on terminal capabilities
        const enhancement_level = self.determineEnhancementLevel();
        
        switch (enhancement_level) {
            .basic => return self.runBasicFlow(),
            .enhanced => return self.runEnhancedFlow(),
            .advanced => return self.runAdvancedFlow(),
        }
    }
    
    fn determineEnhancementLevel(self: *ProgressiveOAuthFlow) EnhancementLevel {
        // Check terminal capabilities
        if (self.terminal_level == .basic) {
            return .basic;
        }
        
        // Check for callback server support
        if (!self.config.enhancement.use_callback_server) {
            return .basic;
        }
        
        // Check for TUI support
        if (self.terminal_level.supportsFullTUI() and 
            self.config.enhancement.use_visual_wizard) {
            return .advanced;
        }
        
        return .enhanced;
    }
    
    fn runBasicFlow(self: *ProgressiveOAuthFlow) !auth.oauth.TokenResponse {
        // Basic flow: Display URL, manual code input
        const auth_url = try self.buildAuthorizationUrl();
        
        // Display instructions
        try self.displayBasicInstructions(auth_url);
        
        // Wait for manual code input
        const code = try self.promptForCode();
        
        // Exchange code for token
        return self.exchangeCodeForToken(code);
    }
    
    fn runEnhancedFlow(self: *ProgressiveOAuthFlow) !auth.oauth.TokenResponse {
        // Enhanced flow: Callback server with status updates
        var server = try auth.oauth.CallbackServer.init(self.allocator, .{
            .port = 8080,
            .timeout_ms = 300_000,
            .show_success_page = true,
        });
        defer server.deinit();
        
        // Start server
        try server.start();
        
        // Build and display auth URL
        const auth_url = try self.buildAuthorizationUrlWithRedirect(server.getRedirectUri());
        try self.displayEnhancedInstructions(auth_url);
        
        // Show progress indicator
        var progress = try ProgressIndicator.init(self.allocator);
        defer progress.deinit();
        
        // Wait for callback
        const result = try server.waitForCallback();
        progress.complete();
        
        // Exchange code for token
        return self.exchangeCodeForToken(result.code);
    }
    
    fn runAdvancedFlow(self: *ProgressiveOAuthFlow) !auth.oauth.TokenResponse {
        // Advanced flow: Full TUI wizard
        var wizard = try auth.tui.OAuthWizard.init(self.allocator, .{
            .provider = self.config.provider,
            .theme = self.config.ui.theme,
            .enable_animations = self.config.enhancement.use_animations,
            .enable_notifications = self.config.enhancement.use_notifications,
        });
        defer wizard.deinit();
        
        // Apply branding if configured
        if (self.config.ui.branding) |branding| {
            try wizard.applyBranding(branding);
        }
        
        // Run interactive wizard
        return wizard.runInteractive();
    }
};

/// Visual states for OAuth flow
pub const OAuthFlowState = enum {
    initializing,
    checking_network,
    generating_pkce,
    building_url,
    launching_browser,
    waiting_for_code,
    exchanging_token,
    saving_credentials,
    complete,
    error,
};

/// Enhanced OAuth wizard with visual feedback
pub const EnhancedOAuthWizard = struct {
    allocator: std.mem.Allocator,
    canvas: *tui.Canvas,
    current_state: OAuthFlowState,
    progress: f32,
    
    pub fn render(self: *EnhancedOAuthWizard) !void {
        // Clear screen
        try self.canvas.clear();
        
        // Render header with branding
        try self.renderHeader();
        
        // Render current state
        try self.renderStateVisual();
        
        // Render progress bar
        try self.renderProgressBar();
        
        // Render instructions
        try self.renderInstructions();
        
        // Render status messages
        try self.renderStatusMessages();
        
        // Flush to terminal
        try self.canvas.flush();
    }
    
    fn renderStateVisual(self: *EnhancedOAuthWizard) !void {
        const visuals = switch (self.current_state) {
            .initializing => "⚡ Setting up OAuth flow...",
            .checking_network => "🌐 Checking network connectivity...",
            .generating_pkce => "🔧 Generating secure parameters...",
            .building_url => "🔗 Building authorization URL...",
            .launching_browser => "🌐 Opening browser...",
            .waiting_for_code => "⏳ Waiting for authorization...",
            .exchanging_token => "🔄 Exchanging code for token...",
            .saving_credentials => "💾 Saving credentials securely...",
            .complete => "✅ Authentication successful!",
            .error => "❌ Authentication failed",
        };
        
        try self.canvas.writeAt(10, 8, visuals);
    }
};
```

### Progressive Enhancement Examples

#### Level 1: Basic Terminal

```
OAuth Authentication Required
============================

Please visit the following URL to authenticate:
https://provider.com/oauth/authorize?client_id=xxx&redirect_uri=urn:ietf:wg:oauth:2.0:oob

After authorizing, enter the code below:
Code: [_____________________]
```

#### Level 2: Enhanced Terminal

```
🔐 OAuth Authentication
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Step 1: Authorization
Click to open browser: https://provider.com/oauth/authorize?...
Or press ENTER to open automatically

⏳ Waiting for authorization...
[███████████░░░░░] 65% • ETA: 8s

Local server listening on: http://localhost:8080/callback
```

#### Level 3: Advanced Terminal (Full TUI)

```
╭─────────────────── OAuth Setup Wizard ───────────────────╮
│                                                           │
│  🔐 Authenticating with GitHub                          │
│                                                           │
│  ┌─ Current Step ─────────────────────────────────────┐ │
│  │                                                     │ │
│  │  🌐 Opening browser for authorization...           │ │
│  │                                                     │ │
│  │  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  65%                      │ │
│  │                                                     │ │
│  └────────────────────────────────────────────────────┘ │
│                                                           │
│  📊 Progress                                             │
│  ├─ ✅ Network check complete                           │
│  ├─ ✅ PKCE parameters generated                        │
│  ├─ ✅ Authorization URL built                          │
│  ├─ ⏳ Waiting for callback...                          │
│  └─ ⏸  Token exchange pending                          │
│                                                           │
│  [Continue] [Manual Input] [Cancel]                      │
╰───────────────────────────────────────────────────────────╯
```

## Markdown Agent Interactive Session Enhancements

### Enhanced Architecture

The markdown agent's interactive session implements a multi-pane dashboard with live preview, metrics tracking, and intelligent editing features.

```zig
//! Enhanced Markdown Interactive Session
//! agents/markdown/enhanced_session.zig

const std = @import("std");
const tui = @import("../../src/shared/tui/mod.zig");
const components = @import("../../src/shared/components/mod.zig");

pub const EnhancedSessionConfig = struct {
    /// Layout configuration
    layout: LayoutConfig = .{
        .mode = .split_horizontal,
        .editor_ratio = 0.6,
        .preview_ratio = 0.4,
        .show_outline = true,
        .show_metrics = true,
    },
    
    /// Editor features
    editor: EditorConfig = .{
        .syntax_highlighting = true,
        .line_numbers = true,
        .auto_indent = true,
        .bracket_matching = true,
        .word_wrap = true,
        .vim_mode = false,
    },
    
    /// Preview settings
    preview: PreviewConfig = .{
        .live_update = true,
        .update_delay_ms = 300,
        .render_mode = .enhanced,
        .sync_scroll = true,
        .show_outline = true,
    },
    
    /// Interactive features
    interactive: InteractiveConfig = .{
        .command_palette = true,
        .quick_actions = true,
        .context_menu = true,
        .drag_drop = true,
        .multi_cursor = false,
    },
};

pub const EnhancedMarkdownSession = struct {
    allocator: std.mem.Allocator,
    config: EnhancedSessionConfig,
    
    // UI components
    layout: *tui.Layout,
    editor: *components.Editor,
    preview: *components.MarkdownPreview,
    outline: *components.DocumentOutline,
    metrics: *components.MetricsPanel,
    command_palette: *components.CommandPalette,
    
    // State management
    document: Document,
    session_state: SessionState,
    undo_stack: UndoStack,
    
    pub fn init(allocator: std.mem.Allocator, config: EnhancedSessionConfig) !EnhancedMarkdownSession {
        var session = EnhancedMarkdownSession{
            .allocator = allocator,
            .config = config,
            .layout = undefined,
            .editor = undefined,
            .preview = undefined,
            .outline = undefined,
            .metrics = undefined,
            .command_palette = undefined,
            .document = Document.init(allocator),
            .session_state = SessionState.init(),
            .undo_stack = UndoStack.init(allocator),
        };
        
        // Initialize layout
        session.layout = try tui.Layout.init(allocator, .{
            .mode = config.layout.mode,
            .resizable = true,
        });
        
        // Initialize components
        try session.initializeComponents();
        
        return session;
    }
    
    fn initializeComponents(self: *EnhancedMarkdownSession) !void {
        // Initialize editor with enhanced features
        self.editor = try components.Editor.init(self.allocator, .{
            .syntax_highlighting = self.config.editor.syntax_highlighting,
            .line_numbers = self.config.editor.line_numbers,
            .language = "markdown",
            .theme = "github-dark",
        });
        
        // Initialize live preview
        self.preview = try components.MarkdownPreview.init(self.allocator, .{
            .render_mode = self.config.preview.render_mode,
            .live_update = self.config.preview.live_update,
        });
        
        // Initialize document outline
        self.outline = try components.DocumentOutline.init(self.allocator, .{
            .collapsible = true,
            .clickable = true,
        });
        
        // Initialize metrics panel
        self.metrics = try components.MetricsPanel.init(self.allocator, .{
            .show_sparklines = true,
            .update_interval_ms = 1000,
        });
        
        // Initialize command palette
        self.command_palette = try components.CommandPalette.init(self.allocator, .{
            .fuzzy_search = true,
            .show_shortcuts = true,
        });
        
        // Register commands
        try self.registerCommands();
    }
    
    fn registerCommands(self: *EnhancedMarkdownSession) !void {
        const commands = [_]Command{
            .{ .name = "Save", .shortcut = "Ctrl+S", .action = .save },
            .{ .name = "Preview", .shortcut = "Ctrl+P", .action = .toggle_preview },
            .{ .name = "Format", .shortcut = "Ctrl+Shift+F", .action = .format_document },
            .{ .name = "Export HTML", .shortcut = "Ctrl+E", .action = .export_html },
            .{ .name = "Insert Table", .shortcut = "Ctrl+T", .action = .insert_table },
            .{ .name = "Toggle Outline", .shortcut = "Ctrl+O", .action = .toggle_outline },
            .{ .name = "Find", .shortcut = "Ctrl+F", .action = .find },
            .{ .name = "Replace", .shortcut = "Ctrl+H", .action = .replace },
        };
        
        for (commands) |cmd| {
            try self.command_palette.registerCommand(cmd);
        }
    }
    
    pub fn render(self: *EnhancedMarkdownSession) !void {
        // Update layout
        try self.layout.update();
        
        // Render main editor
        try self.renderEditor();
        
        // Render preview if enabled
        if (self.config.preview.live_update) {
            try self.renderPreview();
        }
        
        // Render outline if visible
        if (self.config.layout.show_outline) {
            try self.renderOutline();
        }
        
        // Render metrics panel
        if (self.config.layout.show_metrics) {
            try self.renderMetrics();
        }
        
        // Render command palette if active
        if (self.command_palette.isActive()) {
            try self.renderCommandPalette();
        }
    }
};
```

### Interactive Session UI Layout

```
╭────────── Markdown Interactive Session ──────────╮
│ File: document.md • Modified • 1,234 words      │
├──────────────────┬──────────────┬───────────────┤
│                  │              │               │
│  Editor          │  Preview     │  Outline      │
│                  │              │               │
│  # Title         │  Title       │  📁 Title     │
│                  │  ═══════     │   ├─ Intro   │
│  ## Introduction │              │   ├─ Content │
│  Lorem ipsum...  │  Introduction│   └─ Summary │
│                  │  Lorem...    │               │
│                  │              │               │
├──────────────────┴──────────────┴───────────────┤
│ 📊 Metrics                                       │
│ Words: 1,234 • Chars: 6,789 • Reading: 5 min   │
│ Tokens: ▂▄█▅▃ • Cost: $0.02 • Time: ▁▂▄█▅      │
├──────────────────────────────────────────────────┤
│ Ready • Ln 12, Col 45 • Markdown • UTF-8       │
╰──────────────────────────────────────────────────╯
```

## Unified Agent Startup and Branding

### Consistent Startup Sequence

All agents should implement a unified startup sequence with consistent branding and progressive initialization feedback.

```zig
//! Unified Agent Startup Pattern
//! src/core/agent_startup.zig

const std = @import("std");
const term = @import("../shared/term/mod.zig");
const tui = @import("../shared/tui/mod.zig");

pub const StartupConfig = struct {
    /// Agent branding
    branding: BrandingConfig,
    
    /// Startup options
    options: struct {
        show_splash: bool = true,
        show_version: bool = true,
        show_capabilities: bool = false,
        animation_duration_ms: u64 = 1500,
        check_updates: bool = false,
    } = .{},
    
    /// Progress tracking
    progress: struct {
        show_progress: bool = true,
        show_steps: bool = true,
        verbose: bool = false,
    } = .{},
};

pub const BrandingConfig = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    logo_ascii: ?[]const u8 = null,
    color_scheme: ColorScheme = .default,
};

pub const UnifiedStartup = struct {
    allocator: std.mem.Allocator,
    config: StartupConfig,
    terminal: *term.Terminal,
    
    pub fn run(self: *UnifiedStartup) !void {
        // Phase 1: Terminal initialization
        try self.initializeTerminal();
        
        // Phase 2: Show splash screen
        if (self.config.options.show_splash) {
            try self.showSplashScreen();
        }
        
        // Phase 3: Progressive initialization
        try self.progressiveInit();
        
        // Phase 4: Welcome message
        try self.showWelcomeMessage();
    }
    
    fn showSplashScreen(self: *UnifiedStartup) !void {
        const splash = SplashScreen.init(self.allocator, self.config.branding);
        defer splash.deinit();
        
        // Render animated logo if available
        if (self.config.branding.logo_ascii) |logo| {
            try splash.renderAnimatedLogo(logo, .{
                .duration_ms = self.config.options.animation_duration_ms,
                .effect = .fade_in,
            });
        }
        
        // Show version and description
        if (self.config.options.show_version) {
            try splash.renderVersionInfo();
        }
    }
    
    fn progressiveInit(self: *UnifiedStartup) !void {
        const steps = [_]InitStep{
            .{ .name = "Terminal capabilities", .action = checkTerminalCapabilities },
            .{ .name = "Configuration", .action = loadConfiguration },
            .{ .name = "Authentication", .action = verifyAuthentication },
            .{ .name = "Tools registration", .action = registerTools },
            .{ .name = "Session restore", .action = restoreSession },
        };
        
        var progress = try ProgressTracker.init(self.allocator, .{
            .total_steps = steps.len,
            .show_steps = self.config.progress.show_steps,
        });
        defer progress.deinit();
        
        for (steps) |step| {
            try progress.startStep(step.name);
            try step.action();
            try progress.completeStep();
        }
    }
};

/// Example ASCII art logos for agents
pub const AgentLogos = struct {
    pub const markdown =
        \\    __  ___           __       __                    
        \\   /  |/  /___ ______/ /______/ /___ _      ______  
        \\  / /|_/ / __ `/ ___/ //_/ __  / __ \ | /| / / __ \ 
        \\ / /  / / /_/ / /  / ,< / /_/ / /_/ / |/ |/ / / / / 
        \\/_/  /_/\__,_/_/  /_/|_|\__,_/\____/|__/|__/_/ /_/  
    ;
    
    pub const code_assistant =
        \\   ______          __        ___    ____
        \\  / ____/___  ____/ /__     /   |  /  _/
        \\ / /   / __ \/ __  / _ \   / /| |  / /  
        \\/ /___/ /_/ / /_/ /  __/  / ___ |_/ /   
        \\\____/\____/\__,_/\___/  /_/  |_/___/   
    ;
};
```

### Startup Visual Examples

#### Minimal Startup
```
Markdown Agent v1.0.0
Initializing...
Ready.
```

#### Standard Startup
```
┌─────────────────────────────────────┐
│     Markdown Agent v1.0.0          │
│     AI-powered document editor      │
└─────────────────────────────────────┘

Initializing...
✓ Terminal capabilities detected
✓ Configuration loaded
✓ Authentication verified
✓ Tools registered (12 available)
✓ Session restored

Ready. Type 'help' for commands.
```

#### Enhanced Startup with Animation
```
    __  ___           __       __                    
   /  |/  /___ ______/ /______/ /___ _      ______  
  / /|_/ / __ `/ ___/ //_/ __  / __ \ | /| / / __ \ 
 / /  / / /_/ / /  / ,< / /_/ / /_/ / |/ |/ / / / / 
/_/  /_/\__,_/_/  /_/|_|\__,_/\____/|__/|__/_/ /_/  
                                                      
        Markdown Agent • Version 1.0.0
        Your AI-powered document assistant
        
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Initializing components...
[████████████████████] 100% Complete

✨ Welcome! Type 'help' to get started.
```

## Error Handling UX Patterns

### Comprehensive Error Presentation

Error handling should provide clear, actionable feedback with progressive detail levels.

```zig
//! Error Handling UX Patterns
//! src/shared/error_ux.zig

const std = @import("std");
const term = @import("term/mod.zig");

pub const ErrorLevel = enum {
    warning,
    error,
    critical,
};

pub const ErrorContext = struct {
    level: ErrorLevel,
    code: []const u8,
    message: []const u8,
    details: ?[]const u8 = null,
    suggestion: ?[]const u8 = null,
    help_url: ?[]const u8 = null,
    stack_trace: ?[]const u8 = null,
};

pub const ErrorPresenter = struct {
    allocator: std.mem.Allocator,
    terminal: *term.Terminal,
    verbose: bool = false,
    
    pub fn present(self: *ErrorPresenter, context: ErrorContext) !void {
        switch (context.level) {
            .warning => try self.presentWarning(context),
            .error => try self.presentError(context),
            .critical => try self.presentCritical(context),
        }
    }
    
    fn presentError(self: *ErrorPresenter, context: ErrorContext) !void {
        // Clear line for clean presentation
        try self.terminal.clearLine();
        
        // Error header with icon and color
        try self.terminal.setColor(.red);
        try self.terminal.write("❌ Error");
        if (context.code.len > 0) {
            try self.terminal.write(" [");
            try self.terminal.write(context.code);
            try self.terminal.write("]");
        }
        try self.terminal.write(": ");
        try self.terminal.resetColor();
        
        // Error message
        try self.terminal.writeLine(context.message);
        
        // Details if available
        if (context.details) |details| {
            try self.terminal.setColor(.dim);
            try self.terminal.write("   ");
            try self.terminal.writeLine(details);
            try self.terminal.resetColor();
        }
        
        // Suggestion with icon
        if (context.suggestion) |suggestion| {
            try self.terminal.setColor(.yellow);
            try self.terminal.write("💡 ");
            try self.terminal.resetColor();
            try self.terminal.writeLine(suggestion);
        }
        
        // Help URL if available
        if (context.help_url) |url| {
            try self.terminal.setColor(.blue);
            try self.terminal.write("📚 Learn more: ");
            try self.terminal.writeLine(url);
            try self.terminal.resetColor();
        }
        
        // Stack trace in verbose mode
        if (self.verbose and context.stack_trace != null) {
            try self.presentStackTrace(context.stack_trace.?);
        }
    }
    
    fn presentWarning(self: *ErrorPresenter, context: ErrorContext) !void {
        try self.terminal.setColor(.yellow);
        try self.terminal.write("⚠️  Warning: ");
        try self.terminal.resetColor();
        try self.terminal.writeLine(context.message);
    }
    
    fn presentCritical(self: *ErrorPresenter, context: ErrorContext) !void {
        // Box drawing for critical errors
        const box = Box.init(self.allocator, .{
            .style = .double,
            .color = .red,
            .padding = 1,
        });
        defer box.deinit();
        
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        try content.appendSlice("CRITICAL ERROR\n\n");
        try content.appendSlice(context.message);
        
        try box.render(self.terminal, content.items);
        
        // Recovery instructions
        try self.terminal.writeLine("\nRecovery options:");
        try self.terminal.writeLine("  1. Save your work and restart");
        try self.terminal.writeLine("  2. Check the logs at ~/.agent/logs");
        try self.terminal.writeLine("  3. Report issue: github.com/org/repo/issues");
    }
};
```

### Error Display Examples

#### Warning
```
⚠️  Warning: Configuration file not found, using defaults
```

#### Standard Error
```
❌ Error [E001]: Failed to connect to API
   Connection timeout after 30 seconds
💡 Check your internet connection and try again
📚 Learn more: docs.agent.ai/errors/E001
```

#### Critical Error
```
╔════════════════════════════════════════╗
║          CRITICAL ERROR                ║
║                                        ║
║  Out of memory: Cannot allocate 2GB    ║
║                                        ║
╚════════════════════════════════════════╝

Recovery options:
  1. Save your work and restart
  2. Check the logs at ~/.agent/logs
  3. Report issue: github.com/org/repo/issues
```

## Progress Feedback Patterns

### Multi-Level Progress Indicators

```zig
//! Progress Feedback Patterns
//! src/shared/progress_patterns.zig

const std = @import("std");
const term = @import("term/mod.zig");
const components = @import("components/mod.zig");

pub const ProgressStyle = enum {
    simple,      // Basic percentage
    bar,         // Progress bar
    spinner,     // Animated spinner
    detailed,    // Multi-line with substeps
    dashboard,   // Full dashboard view
};

pub const ProgressContext = struct {
    operation: []const u8,
    total_steps: ?usize = null,
    current_step: usize = 0,
    substeps: ?[]const SubStep = null,
    show_eta: bool = true,
    show_speed: bool = false,
    cancelable: bool = true,
};

pub const AdaptiveProgress = struct {
    allocator: std.mem.Allocator,
    terminal: *term.Terminal,
    style: ProgressStyle,
    context: ProgressContext,
    start_time: i64,
    
    pub fn update(self: *AdaptiveProgress, progress: f32) !void {
        switch (self.style) {
            .simple => try self.renderSimple(progress),
            .bar => try self.renderBar(progress),
            .spinner => try self.renderSpinner(progress),
            .detailed => try self.renderDetailed(progress),
            .dashboard => try self.renderDashboard(progress),
        }
    }
    
    fn renderBar(self: *AdaptiveProgress, progress: f32) !void {
        const width = 40;
        const filled = @floatToInt(usize, progress * @intToFloat(f32, width));
        
        try self.terminal.saveCursor();
        try self.terminal.clearLine();
        
        // Operation name
        try self.terminal.write(self.context.operation);
        try self.terminal.write(": ");
        
        // Progress bar
        try self.terminal.write("[");
        for (0..width) |i| {
            if (i < filled) {
                try self.terminal.setColor(.green);
                try self.terminal.write("█");
            } else {
                try self.terminal.setColor(.dim);
                try self.terminal.write("░");
            }
        }
        try self.terminal.resetColor();
        try self.terminal.write("] ");
        
        // Percentage
        try self.terminal.write(try std.fmt.allocPrint(
            self.allocator,
            "{d:.0}%",
            .{progress * 100}
        ));
        
        // ETA if enabled
        if (self.context.show_eta) {
            const eta = self.calculateETA(progress);
            try self.terminal.write(" • ETA: ");
            try self.terminal.write(eta);
        }
        
        try self.terminal.restoreCursor();
    }
    
    fn renderDetailed(self: *AdaptiveProgress, progress: f32) !void {
        // Clear area for multi-line display
        try self.terminal.saveCursor();
        for (0..5) |_| {
            try self.terminal.clearLine();
            try self.terminal.cursorDown(1);
        }
        try self.terminal.restoreCursor();
        
        // Main operation
        try self.terminal.writeLine(self.context.operation);
        
        // Progress bar
        try self.renderBar(progress);
        try self.terminal.newLine();
        
        // Substeps if available
        if (self.context.substeps) |substeps| {
            for (substeps) |substep| {
                try self.renderSubstep(substep);
            }
        }
        
        // Cancel hint
        if (self.context.cancelable) {
            try self.terminal.setColor(.dim);
            try self.terminal.writeLine("Press Ctrl+C to cancel");
            try self.terminal.resetColor();
        }
    }
};

/// Indeterminate progress for unknown duration operations
pub const IndeterminateProgress = struct {
    allocator: std.mem.Allocator,
    terminal: *term.Terminal,
    message: []const u8,
    animation: Animation,
    
    const Animation = enum {
        dots,
        spinner,
        pulse,
        bounce,
    };
    
    const animations = .{
        .dots = [_][]const u8{ "   ", ".  ", ".. ", "..." },
        .spinner = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        .pulse = [_][]const u8{ "○", "◔", "◑", "◕", "●", "◕", "◑", "◔" },
        .bounce = [_][]const u8{ "[    ]", "[=   ]", "[==  ]", "[=== ]", "[ ===]", "[  ==]", "[   =]" },
    };
    
    pub fn render(self: *IndeterminateProgress, frame: usize) !void {
        const frames = switch (self.animation) {
            .dots => animations.dots,
            .spinner => animations.spinner,
            .pulse => animations.pulse,
            .bounce => animations.bounce,
        };
        
        const current_frame = frames[frame % frames.len];
        
        try self.terminal.saveCursor();
        try self.terminal.clearLine();
        try self.terminal.write(current_frame);
        try self.terminal.write(" ");
        try self.terminal.write(self.message);
        try self.terminal.restoreCursor();
    }
};
```

### Progress Display Examples

#### Simple Progress
```
Processing: 65%
```

#### Progress Bar
```
Analyzing document: [████████████████████░░░░░░░░░] 65% • ETA: 12s
```

#### Detailed Progress
```
Building project
[████████████████████░░░░░░░░░] 65% • ETA: 12s

✓ Dependencies resolved
✓ Source files compiled
⠙ Running tests... (15/42)
  Optimizing output...

Press Ctrl+C to cancel
```

#### Indeterminate Progress
```
⠸ Connecting to server...
```

## Interactive Help System

### Context-Aware Help Implementation

```zig
//! Interactive Help System
//! src/shared/help_system.zig

const std = @import("std");
const tui = @import("tui/mod.zig");

pub const HelpLevel = enum {
    quick,      // Single line hints
    standard,   // Basic help text
    detailed,   // Full documentation
    tutorial,   // Interactive tutorial
};

pub const HelpContext = struct {
    command: ?[]const u8 = null,
    feature: ?[]const u8 = null,
    error_code: ?[]const u8 = null,
    current_view: []const u8,
};

pub const InteractiveHelp = struct {
    allocator: std.mem.Allocator,
    help_database: HelpDatabase,
    current_context: HelpContext,
    
    pub fn show(self: *InteractiveHelp, level: HelpLevel) !void {
        switch (level) {
            .quick => try self.showQuickHelp(),
            .standard => try self.showStandardHelp(),
            .detailed => try self.showDetailedHelp(),
            .tutorial => try self.runTutorial(),
        }
    }
    
    fn showQuickHelp(self: *InteractiveHelp) !void {
        // Context-aware single line help
        const hint = try self.help_database.getQuickHint(self.current_context);
        try self.displayHint(hint);
    }
    
    fn showDetailedHelp(self: *InteractiveHelp) !void {
        // Full help modal
        var modal = try tui.Modal.init(self.allocator, .{
            .title = "Help Documentation",
            .width = 80,
            .height = 24,
            .closeable = true,
        });
        defer modal.deinit();
        
        // Add navigation
        try modal.addSection("Navigation", .{
            .content = 
                \\↑/↓ or j/k    Navigate items
                \\←/→ or h/l    Switch tabs
                \\PgUp/PgDn     Scroll pages
                \\Home/End      Jump to start/end
                \\/ or Ctrl+F   Search
                \\Esc           Close help
            ,
        });
        
        // Add command reference
        try modal.addSection("Commands", try self.getCommandHelp());
        
        // Add keyboard shortcuts
        try modal.addSection("Shortcuts", try self.getShortcuts());
        
        try modal.render();
    }
    
    fn runTutorial(self: *InteractiveHelp) !void {
        var tutorial = try InteractiveTutorial.init(self.allocator, .{
            .agent_name = "Markdown Agent",
            .steps = &[_]TutorialStep{
                .{
                    .title = "Welcome",
                    .content = "Let's learn how to use the Markdown Agent!",
                    .action = .continue,
                },
                .{
                    .title = "Creating Documents",
                    .content = "Type 'new' to create a new document",
                    .action = .wait_for_command,
                    .expected = "new",
                },
                .{
                    .title = "Editing",
                    .content = "Use the editor to write markdown",
                    .action = .interactive_edit,
                },
                // More steps...
            },
        });
        defer tutorial.deinit();
        
        try tutorial.run();
    }
};

pub const CommandHelp = struct {
    pub const categories = [_]Category{
        .{
            .name = "File Operations",
            .commands = &[_]Command{
                .{ .name = "new", .args = "[filename]", .desc = "Create new document" },
                .{ .name = "open", .args = "<filename>", .desc = "Open existing document" },
                .{ .name = "save", .args = "[filename]", .desc = "Save current document" },
                .{ .name = "export", .args = "<format>", .desc = "Export to HTML/PDF" },
            },
        },
        .{
            .name = "Editing",
            .commands = &[_]Command{
                .{ .name = "format", .args = "", .desc = "Format document" },
                .{ .name = "validate", .args = "", .desc = "Check for errors" },
                .{ .name = "preview", .args = "", .desc = "Toggle preview" },
            },
        },
    };
};
```

### Help Display Examples

#### Quick Hint
```
💡 Tip: Press Ctrl+P to toggle preview mode
```

#### Standard Help
```
Available commands:
  new [name]    Create new document
  open <file>   Open existing file
  save          Save current document
  help          Show this help
  quit          Exit application

Press F1 for detailed help
```

#### Detailed Help Modal
```
╭───────────── Help Documentation ─────────────╮
│                                               │
│  Navigation                                   │
│  ├─ ↑/↓ or j/k    Navigate items            │
│  ├─ ←/→ or h/l    Switch tabs               │
│  ├─ PgUp/PgDn     Scroll pages              │
│  └─ Esc           Close help                 │
│                                               │
│  Commands                                     │
│  ├─ File Operations                          │
│  │  ├─ new [name]   Create document         │
│  │  ├─ open <file>  Open file               │
│  │  └─ save [name]  Save document           │
│  └─ Editing                                  │
│     ├─ format       Auto-format              │
│     └─ validate     Check errors             │
│                                               │
│  [Search] [Tutorial] [Close]                 │
╰───────────────────────────────────────────────╯
```

## Implementation Examples and Code Patterns

### Complete Agent Integration Example

```zig
//! Complete agent with all UX improvements
//! agents/enhanced_agent/main.zig

const std = @import("std");
const core = @import("../../src/core/mod.zig");
const shared = @import("../../src/shared/mod.zig");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize with enhanced startup
    var startup = try shared.startup.UnifiedStartup.init(allocator, .{
        .branding = .{
            .name = "Enhanced Agent",
            .version = "1.0.0",
            .description = "Next-generation AI agent",
            .author = "Agent Team",
            .logo_ascii = spec.logo,
            .color_scheme = .modern,
        },
        .options = .{
            .show_splash = true,
            .show_capabilities = true,
            .check_updates = true,
        },
    });
    
    try startup.run();
    
    // Initialize agent with enhanced features
    var agent = try spec.Agent.init(allocator, .{
        .enable_oauth = true,
        .enable_dashboard = true,
        .enable_help = true,
        .progress_style = .detailed,
        .error_handling = .enhanced,
    });
    defer agent.deinit();
    
    // Run with enhanced session
    try agent.runInteractive();
}
```

### Testing UX Components

```zig
//! UX Component Testing
//! tests/ux_test.zig

const std = @import("std");
const testing = std.testing;
const ux = @import("../src/shared/ux/mod.zig");

test "OAuth flow progression" {
    const allocator = testing.allocator;
    
    var flow = try ux.ProgressiveOAuthFlow.init(allocator, .{
        .provider = .{
            .name = "github",
            .client_id = "test_id",
        },
        .capabilities = .{
            .min_terminal = .basic,
        },
    });
    defer flow.deinit();
    
    // Test level detection
    const level = flow.determineEnhancementLevel();
    try testing.expect(level != null);
}

test "Error presenter formatting" {
    const allocator = testing.allocator;
    
    var presenter = ux.ErrorPresenter.init(allocator);
    defer presenter.deinit();
    
    const context = ux.ErrorContext{
        .level = .error,
        .code = "E001",
        .message = "Test error",
        .suggestion = "Try again",
    };
    
    const output = try presenter.format(context);
    defer allocator.free(output);
    
    try testing.expect(std.mem.indexOf(u8, output, "E001") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Try again") != null);
}

test "Progress bar rendering" {
    const allocator = testing.allocator;
    
    var progress = try ux.AdaptiveProgress.init(allocator, .{
        .style = .bar,
        .context = .{
            .operation = "Testing",
            .show_eta = true,
        },
    });
    defer progress.deinit();
    
    // Test various progress values
    for ([_]f32{ 0.0, 0.25, 0.5, 0.75, 1.0 }) |value| {
        const output = try progress.render(value);
        defer allocator.free(output);
        try testing.expect(output.len > 0);
    }
}
```

## Component Reference

### Available UI Components

| Component | Location | Purpose | Terminal Requirements |
|-----------|----------|---------|----------------------|
| **OAuth Wizard** | `src/shared/auth/tui/oauth_wizard.zig` | Visual OAuth flow | Colors, Unicode |
| **Progress Bar** | `src/shared/components/progress.zig` | Progress indication | Basic |
| **Command Palette** | `src/shared/tui/components/command_palette.zig` | Command discovery | Colors, Mouse |
| **Error Modal** | `src/shared/tui/widgets/modal.zig` | Error display | Colors |
| **Dashboard** | `src/shared/tui/components/dashboard/` | Metrics display | Full TUI |
| **Editor** | `src/shared/components/editor.zig` | Text editing | Colors, Unicode |
| **Preview** | `src/shared/render/markdown_renderer.zig` | Markdown preview | Colors, Unicode |
| **Help System** | `src/shared/help/mod.zig` | Interactive help | Colors |
| **Notification** | `src/shared/components/notification.zig` | Status messages | Colors |
| **Splash Screen** | `src/shared/tui/components/welcome_screen.zig` | Startup branding | Colors, Unicode |

### Component Integration Matrix

| Feature | Basic Terminal | Enhanced Terminal | Full TUI |
|---------|---------------|-------------------|----------|
| **OAuth** | URL + Manual Code | Callback Server | Visual Wizard |
| **Progress** | Percentage | Progress Bar | Dashboard |
| **Errors** | Plain Text | Formatted + Color | Modal Dialog |
| **Help** | Text List | Categorized | Interactive |
| **Editor** | Line Input | Syntax Highlight | Split Pane |
| **Preview** | None | Basic Render | Live Update |
| **Commands** | CLI Args | Menu | Palette |
| **Notifications** | Print | Styled | Toast |

## Best Practices

### 1. Terminal Capability Detection

Always detect and adapt to terminal capabilities:

```zig
const capabilities = try term.detectCapabilities();
const ui_level = switch (capabilities.level) {
    .basic => UILevel.minimal,
    .enhanced => UILevel.standard,
    .full => UILevel.rich,
};
```

### 2. Graceful Degradation

Provide fallbacks for limited terminals:

```zig
if (capabilities.supports_unicode) {
    try render.drawBox("╭──────╮");
} else {
    try render.drawBox("+------+");
}
```

### 3. Responsive Design

Adapt to terminal size changes:

```zig
pub fn handleResize(self: *Component, width: u16, height: u16) !void {
    if (width < 80) {
        self.layout = .compact;
    } else {
        self.layout = .full;
    }
    try self.rerender();
}
```

### 4. Consistent Key Bindings

Follow standard conventions:

- **Ctrl+C**: Cancel/Interrupt
- **Ctrl+S**: Save
- **Ctrl+Q**: Quit
- **Ctrl+F**: Find
- **F1**: Help
- **Esc**: Close/Cancel
- **Tab**: Next field
- **Shift+Tab**: Previous field

### 5. Performance Optimization

Minimize terminal operations:

```zig
// Batch updates
var buffer = try BufferedRenderer.init(allocator);
defer buffer.deinit();

try buffer.begin();
// Multiple render operations
try buffer.commit(); // Single flush to terminal
```

### 6. Accessibility

Ensure keyboard-only navigation:

```zig
pub fn handleKeyPress(self: *Component, key: Key) !void {
    switch (key) {
        .tab => try self.focusNext(),
        .shift_tab => try self.focusPrevious(),
        .enter, .space => try self.activate(),
        else => {},
    }
}
```

### 7. Error Recovery

Provide clear recovery paths:

```zig
catch |err| {
    try self.showError(.{
        .error = err,
        .recovery_options = &[_]RecoveryOption{
            .{ .label = "Retry", .action = .retry },
            .{ .label = "Skip", .action = .skip },
            .{ .label = "Abort", .action = .abort },
        },
    });
}
```

### 8. Session Persistence

Save and restore session state:

```zig
pub fn saveSession(self: *Session) !void {
    const state = try self.serialize();
    defer self.allocator.free(state);
    try std.fs.cwd().writeFile(".agent_session", state);
}

pub fn restoreSession(self: *Session) !void {
    const state = try std.fs.cwd().readFileAlloc(
        self.allocator,
        ".agent_session",
        1024 * 1024
    );
    defer self.allocator.free(state);
    try self.deserialize(state);
}
```

## Conclusion

This guide provides comprehensive patterns for implementing modern UX improvements across all agents. The key principles are:

1. **Progressive Enhancement**: Adapt to terminal capabilities
2. **Consistent Experience**: Unified patterns across agents
3. **Clear Feedback**: Immediate, actionable user feedback
4. **Discoverability**: Intuitive interfaces with built-in help
5. **Performance**: Optimized rendering and responsiveness
6. **Accessibility**: Full keyboard navigation support
7. **Error Handling**: Clear error presentation with recovery options
8. **Visual Polish**: Professional appearance with animations and theming

By following these patterns, agents provide a modern, professional terminal experience that rivals graphical applications while maintaining the efficiency and power of command-line interfaces.

## Resources

- [Terminal UI Components Documentation](../src/shared/tui/README.md)
- [OAuth Implementation Guide](../src/shared/auth/README.md)
- [Markdown Agent Documentation](../agents/markdown/README.md)
- [Theme System Guide](../src/shared/theme_manager/README.md)
- [Testing Guide](../tests/README.md)
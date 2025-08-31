# Build.zig Changes Summary

## Overview
Updated build.zig to integrate new UX enhancement modules and features into the build system.

## Feature Flags & Profiles (2025-08-31)

The build supports a profile mechanism and explicit feature flags for selective compilation:

- Profiles: `-Dprofile=minimal|standard|full` (default: `standard`).
- Features string: `-Dfeatures=<csv>` where `<csv>` ⟂ `{cli,tui,network,anthropic,auth,sixel,theme-dev}`.
- Keep profile defaults without overriding: `-Dfeatures=all`.
- Per-flag overrides: `-Denable-tui/cli/network/anthropic/auth/sixel/theme-dev` with `=true|false`.

Rules and precedence:
- Precedence: profile → features string → per-flag overrides.
- Enabling `auth` or `anthropic` implies `network` unless explicitly disabled via `-Denable-network=false`.
- Explicitly disabling `network` forces `auth` and `anthropic` off.

Diagnostics:
- The configure step prints a feature matrix summarizing the active settings.
- A helper step `zig build test-feature-combinations` runs a common matrix (see `test_feature_combinations.sh`).

See `docs/FEATURE_FLAGS.md` for examples and recipes.

## Key Changes Made

### 1. Added New Core Module Paths
- `AGENT_INTERFACE_ZIG = "src/shared/tui/agent_interface.zig"`
- `AGENT_DASHBOARD_ZIG = "src/shared/tui/components/agent_dashboard.zig"`
- `INTERACTIVE_SESSION_ZIG = "src/core/interactive_session.zig"`
- `OAUTH_CALLBACK_SERVER_ZIG = "src/shared/auth/oauth/callback_server.zig"`

### 2. Updated Module Structures
Extended both `SharedModules` and `ConditionalSharedModules` structs to include:
- `agent_interface`
- `agent_dashboard`
- `interactive_session`
- `oauth_callback_server`

### 3. Module Creation and Dependencies
Updated `createSharedModules` and `createConditionalSharedModules` functions to:
- Create new core modules with proper dependencies
- Link agent_interface with config, engine, and tools modules
- Link agent_dashboard with TUI, terminal, and agent_interface modules
- Link interactive_session with engine, CLI, and auth modules
- Link oauth_callback_server with auth module

### 4. Enhanced Markdown Agent Support
Added special handling in `createAgentModules` for the markdown agent:
- Automatically includes `markdown_editor.zig` when building markdown agent
- Links editor with CLI, TUI, tools, terminal, and config modules

### 5. New Demo Build Targets
Created `setupDemoTargets` function that adds demo commands:
- `zig build demo-dashboard` - Run agent dashboard demo
- `zig build demo-interactive` - Run interactive session demo
- `zig build demo-oauth` - Run OAuth callback server demo
- `zig build demo-markdown-editor` - Run enhanced markdown editor demo (markdown agent only)

### 6. Import Enhancements
Updated `createAgentModules` to provide all new modules as imports to agents:
- Agents can now import and use agent_interface, agent_dashboard, interactive_session
- OAuth callback server is available for agents with network capabilities

## Usage Examples

### Building with New Features
```bash
# Build markdown agent with enhanced editor
zig build -Dagent=markdown

# Run dashboard demo
zig build demo-dashboard

# Run interactive session demo
zig build demo-interactive

# Run OAuth server demo
zig build demo-oauth

# Run enhanced markdown editor demo (requires markdown agent)
zig build -Dagent=markdown demo-markdown-editor
```

### Agent Access to New Modules
Agents can now import and use the new modules:
```zig
const agent_interface = @import("agent_interface");
const dashboard = @import("../../src/shared/tui/components/agent_dashboard.zig");
const interactive = @import("interactive_session");
const oauth_server = @import("oauth_callback_server");
const markdown_editor = @import("markdown_editor"); // markdown agent only
```

## Conditional Module Inclusion
The build system intelligently includes modules based on agent capabilities:
- OAuth callback server is only included when `network_access` is enabled
- Agent dashboard is only included when `terminal_ui` is enabled
- Enhanced markdown editor is only included for the markdown agent

## Benefits
1. **Modular Architecture**: New UX features are cleanly separated into modules
2. **Optimized Builds**: Only necessary modules are included based on agent capabilities
3. **Easy Testing**: Demo targets allow quick testing of individual features
4. **Enhanced Markdown Agent**: Automatically gets the enhanced editor module
5. **Clean Dependencies**: All module dependencies are properly managed

## Next Steps
1. Test all demo targets to ensure proper module loading
2. Update agent implementations to use new UX features
3. Document the new modules in agent development guides
4. Consider adding more demo scenarios for complex interactions

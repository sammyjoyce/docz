# Auth Port and TUI Decoupling

This document explains the new authentication port (AuthPort) and how TUI consumes it to stay decoupled from the network layer.

## Goals

- Break TUI → Network dependency edges (guarded by graph-lint).
- Allow multiple backends (real network, mocks) via dependency injection.
- Keep agent flows working by providing a default adapter from engine.

## Key Modules

- `src/foundation/ports/auth.zig` — Neutral interface for authentication:
  - Types: `Credentials`, `OAuthSession`, `Error`.
  - API: `load`, `save`, `startOAuth`, `completeOAuth`, `refreshIfNeeded`, `authHeader`.
  - `nullAuthPort()` for headless/tests.

- `src/foundation/adapters/auth_network.zig` — Default adapter backed by `foundation.network.Auth` and PKCE helpers.

- `src/foundation/tui/AuthenticationManager.zig` — Refactored to depend on the port only; no network imports.

- `src/engine.zig` — `pub fn defaultAuthPort()` creates the default adapter for DI.

## Using the Port

Most callers don’t need to do anything: `agent_interface` now auto-wires the default port from the engine.

```zig
const foundation = @import("foundation");
const tui = foundation.tui;
const engine = @import("core_engine");

// Default interactive run (uses engine.defaultAuthPort internally)
try tui.agent_interface.runInteractive(alloc, my_agent_ptr);

// Custom auth wiring
const port = foundation.adapters.auth_network.make();
const agent = try tui.agent_interface.createAgent(alloc, my_agent_ptr, .{});
defer agent.deinit();
try tui.agent_interface.setAuthPort(agent, port);
try agent.runInteractive();
```

## CI Guardrails

- Graph lint runs on install and defaults to strict:
  - `scripts/graph_lint.sh` enforces:
    - No `src/foundation/**` may import the facade (`@import("foundation")`).
    - No `ui/** → term/**` imports.
    - No `tui/** → network/**` imports (now a violation).

- Environment override:
  - `CI_STRICT_GRAPH=0` to allow non-strict (not recommended for CI).

## Rationale

Decoupling TUI from network reduces rebuild blast radius, improves testability, and makes alternate UIs/backends easier without sacrificing current functionality.


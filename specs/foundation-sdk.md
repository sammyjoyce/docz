# Foundation SDK — Structure, Layers, Packages, Gates, and Enforcement

Purpose

- Define the end‑state where the whole of `src/foundation` is an SDK.
- Specify module boundaries, strict layering, package wiring, barrels, feature gates, and enforcement.
- Include the terminal stack (`term`, `render`, `ui`, `tui`, `cli`) and leave room for additional modules (`network`, `tools`, `theme`, `logger`, `context`) under the same rules.

TL;DR — Key upgrades

1) Enforce layering in the build graph: each namespace is its own build module/package; only allowed imports are wired.
2) Ban cross‑namespace path imports: require package imports across namespaces; keep path imports for intra‑namespace internals only.
3) Gate by swapping modules (build.zig): for each feature, register either the real package or a typed stub package.
4) Tighten `sdk.zig`: keep `features`; external users import `foundation_sdk`; internal code uses per‑namespace packages to avoid cycles.
5) Renderer negotiation contract: formalize `Capabilities`, `Negotiation`, and the renderer’s error set. Make downgrades explicit.
6) Deterministic import rules: deep imports across namespaces are impossible by construction; a tiny linter enforces the `tui→term` allowlist.
7) Allocator + error discipline: narrow error sets, explicit `init/deinit(allocator)`, failing‑allocator tests in CI matrices.

Scope

- In scope: entire `src/foundation` tree. The SDK umbrella is `src/foundation/sdk.zig`.
- Initial focus: `src/foundation/{term,render,ui,tui,cli}`.
- Future-ready: `src/foundation/{network,tools,theme,logger,context,...}` included by the same pattern as they are integrated.

Outcomes

1) Single SDK entry to import.
2) Exactly one renderer implementation (under `render/`); TUI uses a thin adapter.
3) Strict, one‑direction layering; no deep imports; no cycles.
4) Compile‑time feature gates for each namespace; lean builds.
5) Narrow public APIs with allocator injection and precise error sets.
6) Deterministic enforcement in CI (import rules, layer rules, disabled‑module usage).

Layering Model (Allowed Dependencies)

- Base: `term` (terminal I/O and capabilities) — no SDK dependencies.
- Headless: `ui` (components/layout/events) — no terminal calls; std only.
- Rendering: `render` → `term`.
- Terminal UI: `tui` → `ui`, `render`; `tui` may import `term` only for terminal mode and raw input handling (never painting).
- CLI: `cli` → `tui` (may use `term` for process lifecycle and raw stdio).
- Networking: `network` — std only; no dependency on UI/TUI/Render/Term.
  - Handles OAuth credential storage at `~/.local/share/{agent name}/auth.json` (read/write tokens).
- Tools: `tools` → `network` (headless surfaces; no direct UI/TUI coupling).
- Theme/Logger/Context: headless utilities referenced by any layer; must not pull higher layers.

Rules

- A module imports its own barrel and barrels of lower layers only.
- No module imports internals of a higher layer.
- No deep imports across module trees; barrels only.
- Cross‑cutting utilities (`logger`, `context`, `theme`) are headless; higher layers import via barrels.

Public Entry Surface (Umbrella)

File: `src/foundation/sdk.zig`

- Exposes the SDK surface behind feature gates.
- External code imports:

```zig
const sdk = @import("foundation_sdk");
const render = sdk.render;
const tui = sdk.tui;
const term = sdk.terminal;
const ui = sdk.ui;
// Optional modules when enabled: sdk.cli, sdk.network, sdk.tools, sdk.theme, sdk.logger, ...
```

sdk.zig Exports (Guarded)

- `pub const terminal = @import("term.zig");`
- `pub const render   = @import("render.zig");`
- `pub const ui       = @import("ui.zig");`
- `pub const tui      = @import("tui.zig");`
- `pub const cli      = @import("cli.zig");`
- Future modules follow the same pattern: `network`, `tools`, `theme`, `logger`, `context`, ...

Build Options & Feature Gates (Compile‑time)

- A dedicated options module is required and can be overridden by build.zig. Default file lives at `src/foundation/build_options_default.zig` with:

```zig
pub const enable_terminal = true;
pub const enable_render   = true;
pub const enable_ui       = true;
pub const enable_tui      = true;
pub const enable_cli      = false;
pub const enable_network  = false;
pub const enable_tools    = false;
pub const enable_theme    = true;
pub const enable_logger   = true;
pub const enable_context  = true;
```

- Consumers supply flags with the `foundation_enable_*` prefix and wire them into an Options object in build.zig, then pass that object as `foundation_build_options` (see “Reference Snippets”).

Behavior

- `sdk.zig` conditionally re‑exports modules based on flags.
- Disabled modules are represented by a typed stub (see “Disabled‑module stubs”).
- CI enforces that imports respect disabled flags.

Renderer Unification & Capability Handshake

- Single authoritative renderer under `src/foundation/render/renderer.zig` exposed by `src/foundation/render.zig`.
- TUI calls the renderer via `src/foundation/tui/renderer_adapter.zig`:
  - Re‑exports `Renderer`, `Render`, `Style`, `Bounds`, `Image` from `render.zig`.
  - May add naming shims or lightweight wrappers. No rendering logic in the adapter.
- `render` defines `Capabilities`. `term` provides detection. `render.Renderer.init(alloc, caps)` validates capabilities and returns an error (or downgrades) when requirements aren’t satisfied.
- All TUI modules import from the adapter (or `tui.zig` which re‑exports it).

Barrels and Module Surfaces

- Each namespace exposes one barrel file:
  - `src/foundation/term.zig`      — terminal capabilities + OSC/CSI
  - `src/foundation/render.zig`    — renderer core + widgets adapters + diff/canvas
  - `src/foundation/ui.zig`        — headless UI primitives (Component, Layout, Event)
  - `src/foundation/tui.zig`       — terminal UI widgets, app scaffolding, presenters
  - `src/foundation/cli.zig`       — CLI app and commands
  - `src/foundation/network.zig`   — HTTP/SSE/auth surfaces (headless)
  - `src/foundation/tools.zig`     — tool registry and callable tool surfaces (headless)
  - `src/foundation/theme.zig`     — theme, palette, styling helpers (headless)
  - `src/foundation/logger.zig`    — logging surface (headless)
  - `src/foundation/context.zig`   — shared context contracts (headless)
  - `src/foundation/sdk.zig`       — umbrella re‑exports (public SDK entry)

Import Rules (Enforced)

- External code imports via `foundation_sdk` (preferred) or top‑level barrels.
- Disallowed:
  - Deep imports (e.g., `@import("tui/core/renderer.zig")`).
  - Importing `render/renderer.zig` from outside `render.zig`.
  - Up‑layer imports (e.g., `render` importing `tui`).
  - Painting from `tui` using `term` primitives.
- Allowed patterns:
  - External consumers: `@import("foundation_sdk")`.
  - Internal cross‑namespace: `@import("foundation_render")`, `@import("foundation_term")`, etc (package names only).
  - Intra‑namespace: relative path imports.
  - Headless consumers may import `foundation_network`/`foundation_tools` when enabled.

CLI and Headless Modules

- `cli/` is part of the SDK and gated by `enable_cli`.
- `network/` and `tools/` are headless and gated by `enable_network` and `enable_tools`.
- UI/TUI must not depend on `network` or `tools`; any composition occurs at application level.

Events, Error & Allocator Conventions

- Public APIs define narrow error sets per function.
- No `anyerror` in public signatures.
- All stateful types accept a caller‑supplied `std.mem.Allocator` and expose `deinit(allocator)`.

- Unified headless input model:
  - `ui.Event` is the canonical input union (keyboard, mouse, resize, focus, timers, custom signals).
  - `term` owns raw scancode decoding.
  - `tui/input_adapter.zig` translates `term` input to `ui.Event`.
  - `render` owns no input types.

Naming & Style

- Files/dirs: snake_case; barrels named for the namespace (no `mod.zig`).
- Types: PascalCase; funcs/vars: camelCase; constants: ALL_CAPS; error names: PascalCase.
- Keep imports alphabetical (std first). Run `zig fmt`.

Acceptance Criteria

1) `src/foundation/sdk.zig` exists and re‑exports all SDK namespaces guarded by feature flags.
2) `src/foundation/tui/renderer_adapter.zig` exists and re‑exports renderer types from `render.zig`.
3) The single renderer implementation lives under `src/foundation/render/renderer.zig` and is re‑exported by `render.zig`.
4) All TUI modules import renderer symbols via the adapter (or `tui.zig` re‑export); no deep imports.
5) No source file outside a namespace deep‑imports that namespace’s internals; barrels only.
6) Import checks enforce:
   - No deep imports.
   - No up‑layer imports.
   - No references to disabled modules when feature gates are off.
   - `tui` imports `term` only in allowlisted files (`tui/input_*`, `tui/terminal_mode.zig`).
7) `sdk.features` struct is present and reflects effective `foundation_enable_*` flags.
8) Disabled modules compile as typed stubs that emit a friendly `@compileError` when referenced.
9) `render.Renderer.init(alloc, caps)` validates capabilities; mismatches are detected early.
10) Future namespaces (`network`, `tools`, `theme`, `logger`, `context`) can be enabled via flags and imported through `sdk.zig` without code changes elsewhere.

Reference Snippets

Build options wiring (build.zig excerpt):

```zig
const sdk = b.addModule("foundation_sdk", .{ .root_source_file = .{ .path = "src/foundation/sdk.zig" } });

const opts = b.addOptions();
const enable_tui = b.option(bool, "foundation_enable_tui", "Enable TUI") orelse true;
// Map all prefixed flags to unprefixed fields expected by the SDK
opts.addOption(bool, "enable_terminal",  b.option(bool, "foundation_enable_terminal",  "") orelse true);
opts.addOption(bool, "enable_render",    b.option(bool, "foundation_enable_render",    "") orelse true);
opts.addOption(bool, "enable_ui",        b.option(bool, "foundation_enable_ui",        "") orelse true);
opts.addOption(bool, "enable_tui",       enable_tui);
opts.addOption(bool, "enable_cli",       b.option(bool, "foundation_enable_cli",       "") orelse false);
opts.addOption(bool, "enable_network",   b.option(bool, "foundation_enable_network",   "") orelse false);
opts.addOption(bool, "enable_tools",     b.option(bool, "foundation_enable_tools",     "") orelse false);
opts.addOption(bool, "enable_theme",     b.option(bool, "foundation_enable_theme",     "") orelse true);
opts.addOption(bool, "enable_logger",    b.option(bool, "foundation_enable_logger",    "") orelse true);
opts.addOption(bool, "enable_context",   b.option(bool, "foundation_enable_context",   "") orelse true);

// Provide the options module and a default fallback for local dev
sdk.addOptions("foundation_build_options", opts);
sdk.addImport("foundation_build_options", .{ .path = "src/foundation/build_options_default.zig" });
```

Umbrella export (sdk.zig excerpt):

```zig
const bo = @import("foundation_build_options");

fn Disabled(comptime name: []const u8) type {
    return struct {
        pub const _disabled = true;
        pub fn _use() void {
            @compileError("foundation: module '" ++ name ++ "' is disabled; " ++
                "enable with -Dfoundation_enable_" ++ name ++ "=true");
        }
    };
}

pub const features = struct {
    pub const terminal = bo.enable_terminal;
    pub const render   = bo.enable_render;
    pub const ui       = bo.enable_ui;
    pub const tui      = bo.enable_tui;
    pub const cli      = bo.enable_cli;
    pub const network  = bo.enable_network;
    pub const tools    = bo.enable_tools;
    pub const theme    = bo.enable_theme;
    pub const logger   = bo.enable_logger;
    pub const context  = bo.enable_context;
};

pub const terminal = if (features.terminal) @import("term.zig")     else Disabled("terminal");
pub const render   = if (features.render)   @import("render.zig")   else Disabled("render");
pub const ui       = if (features.ui)       @import("ui.zig")       else Disabled("ui");
pub const tui      = if (features.tui)      @import("tui.zig")      else Disabled("tui");
pub const cli      = if (features.cli)      @import("cli.zig")      else Disabled("cli");
pub const network  = if (features.network)  @import("network.zig")  else Disabled("network");
pub const tools    = if (features.tools)    @import("tools.zig")    else Disabled("tools");
pub const theme    = if (features.theme)    @import("theme.zig")    else Disabled("theme");
pub const logger   = if (features.logger)   @import("logger.zig")   else Disabled("logger");
pub const context  = if (features.context)  @import("context.zig")  else Disabled("context");
```

TUI adapter (renderer_adapter.zig excerpt):

```zig
const render = @import("../../render.zig");
pub const Renderer   = render.Renderer;
pub const Render     = render.Render;
pub const Style      = render.Style;
pub const Bounds     = render.Bounds;
pub const Image      = render.Image;
pub const Event      = @import("../../ui.zig").Event; // input belongs to UI
```

Import Cheatsheet

- Preferred: `const sdk = @import("foundation_sdk");`
  - `sdk.terminal` — terminal capabilities, OSC/CSI helpers
  - `sdk.render`   — renderer core + quality tiers + adapters
  - `sdk.ui`       — headless UI primitives
  - `sdk.tui`      — TUI widgets + app scaffolding
  - `sdk.cli`      — CLI entry (when enabled)
  - `sdk.network`  — HTTP/SSE/auth (when enabled)
  - `sdk.tools`    — tool registry and surfaces (when enabled)
  - `sdk.theme`    — theme utilities (when enabled)
  - `sdk.logger`   — logging surface (when enabled)
  - `sdk.context`  — shared context contracts (when enabled)

Testing & CI Expectations

- Build matrix uses gates to test minimal and combined profiles (e.g., headless, render‑only, tui‑only, render+tui, full stack with/without cli, headless + network/tools).
- Import validation ensures no deep imports or cross‑layer leaks; allowlist check confirms `tui` uses `term` only for mode/input files.
- Unit tests cover public APIs with failing allocators where applicable.

Import‑rule Enforcement Tooling (required)

- Add a CI scanner that parses `@import("...")` occurrences and enforces:
  - Only package names are imported across namespaces (no path escapes).
  - No up‑layer imports.
  - `tui` → `term` imports allowed only in `tui/input_*` and `tui/terminal_mode.zig`.
- Add tiny compile checks (test files) that attempt to deep‑import forbidden paths to ensure violations fail deterministically.

Build‑graph Enforcement (required)

- Create a build module/package per namespace; wire only allowed imports using `addImport`:

```zig
// build.zig (excerpt)
const mod_term    = b.addModule("foundation_term",    .{ .root_source_file = .{ .path = "src/foundation/term.zig" } });
const mod_render  = b.addModule("foundation_render",  .{ .root_source_file = .{ .path = "src/foundation/render.zig" } });
const mod_ui      = b.addModule("foundation_ui",      .{ .root_source_file = .{ .path = "src/foundation/ui.zig" } });
const mod_tui     = b.addModule("foundation_tui",     .{ .root_source_file = .{ .path = "src/foundation/tui.zig" } });
const mod_cli     = b.addModule("foundation_cli",     .{ .root_source_file = .{ .path = "src/foundation/cli.zig" } });

mod_render.addImport("foundation_term", mod_term);
mod_tui.addImport("foundation_ui",     mod_ui);
mod_tui.addImport("foundation_render", mod_render);
mod_tui.addImport("foundation_term",   mod_term); // input/mode only
mod_cli.addImport("foundation_tui",    mod_tui);
mod_cli.addImport("foundation_term",   mod_term);
```

Feature Gates via Module Swapping (required)

- For each feature, register either the real package or a typed stub package, then wire the umbrella to the effective package:

```zig
const mod_term_pkg   = bo.enable_terminal ? mod_term   : b.addModule("foundation_term",   .{ .root_source_file = .{ .path = "src/foundation/stubs/term_disabled.zig" } });
const mod_render_pkg = bo.enable_render   ? mod_render : b.addModule("foundation_render", .{ .root_source_file = .{ .path = "src/foundation/stubs/render_disabled.zig" } });
// ...repeat for others...

const sdk = b.addModule("foundation_sdk", .{ .root_source_file = .{ .path = "src/foundation/sdk.zig" } });
sdk.addImport("foundation_term",   mod_term_pkg);
sdk.addImport("foundation_render", mod_render_pkg);
// ...
```

Typed Stub Packages (friendly failures)

- Per‑namespace stubs preserve API shape and produce targeted `@compileError` at first executable step (e.g., `Client.init`).
- Use a small generator or comptime reflection helper to keep stubs in sync with the barrel’s public surface.

# Multi‑Agent Terminal AI System — Code Review Cheat Sheet
## Purpose
	•	Build independent terminal agents on shared infra with minimal duplication.
	•	Enforce consistent structure, names, errors, config, and build rules.
## Assumptions & Risks
	•	Targeting Zig 0.15.1 semantics (IO, formatting, containers). If compiling with 0.14.x, expect breakage.
	•	Agents compile independently; unused modules must not leak in.
	•	ZON at comptime, JSON at runtime; avoid mixing concerns.

## Directory & Build Layout (must match)
	•	agents/<name>/: main.zig (CLI entry), spec.zig (prompt+tools), agent.zig (impl); optional: config.zon, system_prompt.txt, tools.zon, tools/, common/, examples/, README.md.
	•	src/core/: engine.zig, config.zig, agent_base.zig, agent_main.zig.
	•	src/foundation/: cli/, tui/, render/, ui/, network/, tools/, auth/, term/; each namespace exports via a module‑named barrel file (no `mod.zig`). JSON reflection is consolidated into `src/foundation/tools.zig`.
	•	examples/, tests/.
	•	Build commands:
	◦	zig build -Dagent=<name> [run|run-agent|install-agent|test]
	◦	zig build list-agents | validate-agents | scaffold-agent -- <name>
	◦	Multi: zig build -Dagents=a,b ; Release: -Drelease-safe ; Size: -Doptimize-binary.

## Architecture Principles (enforced)
	•	Independence: only selected agent compiles.
	•	Shared infra via src/core + src/shared/*.
	•	Barrel exports: every shared namespace exposes a clean API via a module‑named barrel file (no `mod.zig`).
	•	Compile‑time agent interface: static verification + dead‑code elimination.
	•	Build‑generated registry: scan agents/, validate required files, fail loud.
	•	Selective inclusion: feature flags gate shared modules.
	•	Clean error sets: no anyerror; use AgentError, ConfigError, ToolError.
	•	Service interfaces: network/terminal/config/tools are swappable/testable.

## Input System Layering (don’t break)
shared/term/input (primitives) → shared/components/input.zig (abstraction) → shared/tui/core/input (TUI features). No cross‑layer shortcuts.

## Config & Prompts
	•	ZON for static config & tool schemas (agents/<name>/config.zon, tools.zon).
	•	Load with @embedFile + std.zig.parseFromSlice.
	•	Template vars in prompts auto‑filled from config: {agent_name}, {agent_version}, {current_date}, feature flags, limits, model settings.
	•	Pattern: ZON templates → JSON at runtime for API payloads.

## Tools Registration (pick one, be consistent)
	•	ZON‑defined tools: define schema/metadata in ZON; validate runtime params.

## Naming & Style (reviewers will reject violations)
	•	Dirs/files: snake_case; barrel filename equals module/main‑struct name (e.g., `api.zig`, `tui.zig`); do not use `mod.zig`. Single‑type files may use `PascalCase.zig` when they primarily define one public type.
	•	Types: PascalCase; func/vars: camelCase; consts: ALL_CAPS; errors: PascalCase.
	•	Modules: no redundant suffixes (“Module/Lib/Utils”).
	•	Follow Zig Style Guide; run zig fmt.

## Core Modules (know where things live)
	•	core/engine.zig: run loop, tool calls, API comms.
	•	core/config.zig: AgentConfig + validation/defaults.
	•	core/agent_base.zig: lifecycle, template vars, config helpers.
	•	core/agent_main.zig: standardized CLI parsing + engine delegation.

## Shared Modules (feature‑gated)
	•	cli/ (args, routing, color/output, multi‑step flows)
	•	tui/ (canvas, renderer, widgets, layouts)
	•	render/ (charts/tables/progress, quality levels)
	•	components/ (shared UI incl. unified input)
	•	network/ (HTTP clients, Anthropic/Claude, SSE)
	•	tools/ (registry, metadata, agent attribution)
	•	auth/ (OAuth + API keys; TUI flows; CLI commands)
	•	tools/ (registry, schemas, JSON reflection)
	•	term/ (terminal caps, low‑level input/mouse)

## Error Handling (hard rules)
	•	Define specific error sets; do not export anyerror.
	•	Public APIs return typed errors; handle locally when appropriate.
	•	Use try; catch |e| to attach context; prefer error chaining for debugging.
	•	No panics except unrecoverable invariants (documented).

## Resource & Memory
	•	Use defer for cleanup; clarify ownership.
	•	Prefer stack; use arena allocators for short‑lived bursts.
	•	Avoid leaks in long‑running TUI loops; free after tool invocations.
	•	Keep stdout buffering global if reused; don’t forget flush.

## Zig 0.15.1 Key Changes You Must Observe
	•	usingnamespace, async/await, @frameSize: removed.
	•	IO: new std.Io.Reader/Writer concrete types; caller‑owned buffers; ring buffers.
	•	Formatting: {} no longer auto‑calls format; use {f} or {any}; new {t}, {b64}, {d} behavior.
	•	Containers: std.ArrayList is unmanaged; use std.array_list.Managed if needed.
	•	FS: fs.File.reader()/writer() now .deprecatedReader/.deprecatedWriter; prefer new Reader/Writer.
	•	Build: use root_module; UBSan enum (.full|.trap|.off).
	•	Deleted: LinearFifo, RingBuffer, BoundedArray (use ArrayListUnmanaged.initBuffer or fixed slices).

## Build & Validation Expectations
	•	CI must run:
	◦	zig build list-agents (registry OK)
	◦	zig build validate-agents (required files present)
	◦	zig build -Dagent=<each> test
	◦	zig build fmt (lint) + zig fmt src/**/*.zig build.zig build.zig.zon
	•	Examples moved to examples/cli_demo/ (don’t assume old path).

## Testing Strategy (min bar)
	•	Unit test core services & tools.
	•	Integration test agent E2E (engine ↔ tools ↔ network).
	•	Test error cases (config invalid, tool failure, network timeouts).
	•	Consider fuzzing parsers and terminal input.

## Agent Implementation Skeleton (reviewer‑approved)
	•	main.zig: delegate to agent_main.runAgent(); no bespoke CLI parsing.
	•	spec.zig: define system prompt (with template vars) + register tools.
	•	agent.zig: pub const <Name>Agent = struct { config: Config, allocator: Allocator, ... }; implement lifecycle and service usage.
	•	config.zon: extend AgentConfig; set limits, features, model, defaults.

## Performance & Binary Size
	•	Feature‑gate shared modules; avoid accidental imports.
	•	Use compile‑time interfaces to prune code paths.
	•	Prefer streaming IO; avoid large heap JSON when not required.
	•	Rendering: use quality levels; avoid overdraw in TUI.

## Code Review Pass Checklist
	•	 Directory structure & filenames match conventions.
	•	 No anyerror; specific error sets exported.
	•	 Uses agent_main for CLI; no duplicated parsers.
	•	 Tools registered via registry with agent attribution.
	•	 ZON config loads, validates, and drives template vars.
	•	 JSON only for runtime API payloads; ZON at comptime.
	•	 Barrel exports present; no deep imports into subfiles.
	•	 Memory ownership clear; all defer paths covered; no leaks.
	•	 IO updated to new std.Io APIs; formatting uses {f}/{any} as needed.
	•	 Feature flags gate module inclusion; binary size reasonable.
	•	 Tests cover success + failure; CI commands included.
	•	 zig fmt clean; imports alphabetical (std first).

## Common Pitfalls (preempt them)
	•	Mixing 0.14 and 0.15 IO/formatting APIs.
	•	Leaking agent‑specific code into shared modules.
	•	Circular deps across term/ ↔ components/ ↔ tui/.
	•	Tool names with redundant prefixes/snake_case fns.
	•	Prompt templates missing required vars (unreplaced {...}).
	•	Pulling in tui/ or render/ without feature‑gating.

## Zig Idioms and Patterns (Zig 0.15.1)
Use these patterns across `agents/<name>/`, `src/core/`, and `src/shared/*` to keep agents independent, small, and consistent with this repository.

### Key Points
- No `usingnamespace`: re-export explicitly via `pub const`.
- I/O: use `std.Io` Writer/Reader and concrete adapters; avoid deprecated `std.io.*` and `fs.File.deprecated*` helpers.
- Build: `build.zig` should use `root_module`.
- Errors: return specific error sets; never `anyerror`.
- Memory: pair `init`/`deinit`; keep `deinit` infallible; use `defer`/`errdefer`.
- Interfaces: function-pointer + `*anyopaque`; cast with `@alignCast` then `@ptrCast`.
- Modules: barrel exports via module‑named files (e.g., `api.zig`); no deep imports; only the selected agent compiles.
- Naming: snake_case dirs/files; PascalCase types; camelCase funcs/vars.

### Examples
```zig
// Re-export (no usingnamespace)
pub const Config = @import("config.zig").Config;
pub const http = @import("network/http.zig");

// RAII
var r = try Resource.init(alloc);
defer r.deinit();

// Builder chaining
const cfg = ServerConfig.builder().port(3000).build();

// anyopaque cast
const self: *T = @ptrCast(@alignCast(ctx));
```

### Commands
- Build agent: `zig build -Dagent=demo run`
- Validate registry: `zig build validate-agents`
- List agents: `zig build list-agents`

## Codex Cloud Development

This project is configured for development in Codex cloud environments.

### Setup
The environment is automatically configured with:
- Zig 0.15.1 compiler
- ripgrep for code analysis
- Standard Unix development tools

### Building Agents

List available agents:
```bash
zig build list-agents
```

Build and run a specific agent:
```bash
zig build -Dagent=<name> run
```

Test an agent:
```bash
zig build -Dagent=<name> test
```

### Code Quality Checks

Format code:
```bash
zig fmt src/**/*.zig build.zig build.zig.zon
```

Check import boundaries:
```bash
scripts/check_imports.sh
```

Validate agent structure:
```bash
zig build validate-agents
```

### Feature Flags & Profiles
- Profiles: `-Dprofile=minimal|standard|full` (default: `standard`).
- Explicit features: `-Dfeatures=cli,tui,network,anthropic,auth,sixel,theme-dev`.
- Keep profile defaults: `-Dfeatures=all`.
- Per-flag overrides: `-Denable-<name>=true|false` (wins last).
- Dependency rules: `auth`/`anthropic` imply `network` unless `-Denable-network=false`.
- See docs/FEATURE_FLAGS.md for full examples and recipes.

### Common Tasks

**Creating a new agent:**
```bash
zig build scaffold-agent -- <name>
```

**Building for release:**
```bash
zig build -Dagent=<name> -Drelease-safe
```

**Size-optimized build:**
```bash
zig build -Dagent=<name> -Doptimize-binary
```

### Debugging Tips
- Use `zig build --help` to see all available targets
- Run individual tests with `zig test <file.zig>`
- Use `zig build-exe -freference-trace` for detailed error traces

### Architecture Notes
- Each agent compiles independently
- Shared infrastructure in `src/core/` and `src/shared/`
- Feature flags gate module inclusion to minimize binary size
- Follow Zig 0.15.1 patterns (no `usingnamespace`, new I/O APIs)

**Idiomatic Module Design (0.15.1)**
- **Single-Entry Structs:** Design each module around one primary struct (the entry point) that encapsulates state and exposes methods. Keep helper types/functions private to the file. For agents, the entry type lives in `agents/<name>/agent.zig` and holds `config`, `allocator`, and any injected services.
- **@This For Methods:** Inside a struct, declare `const Self = @This();` and use it for method receivers and constructors. Avoid legacy `@Self`. Example:
  ```zig
  const Thing = struct {
      const Self = @This();
      x: u32 = 0,
      pub fn init(x: u32) Self { return .{ .x = x }; }
      pub fn bump(self: *Self, by: u32) void { self.x += by; }
  };
  ```
- **Barrels, Not Deep Imports:** Export each namespace via a module‑named barrel file (no `mod.zig`). Example: `src/shared/tui.zig` re‑exports from `src/shared/tui/*`. External code imports the barrel by name (build module) or path, e.g. `const tui = @import("src/shared/tui.zig");`. Never import deep subfiles across modules.

**Explicit Dependency Injection**
- **Allocators:** Prefer unmanaged containers in 0.15.1: pass an `Allocator` to operations and to `deinit`. Example:
  ```zig
  const std = @import("std");
  var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
  const alloc = gpa.allocator();

  var list = try std.ArrayList(u32).initCapacity(alloc, 0);
  defer list.deinit(alloc);
  try list.append(alloc, 42);
  ```
- **Other Services:** Inject loggers, RNGs, file handles, and network clients as parameters or stored fields; do not rely on globals. Our service surfaces (`network/`, `tools/`, `term/`) are function-pointer + context (`*anyopaque`) so they’re swappable and testable.

**Compile-Time Configuration**
- **Root Overrides:** Support root/package overrides with `@hasDecl` patterns. Example:
  ```zig
  const root = @import("root");
  pub const options: Options = if (@hasDecl(root, "std_options")) root.std_options else .{};
  ```
- **Build Options Package:** When flags matter across the app, use a `build_options` package (added in `build.zig`) and gate code with comptime checks (e.g. `if (build_options.enable_tui) { ... }`).
- **Feature Gating:** Turn whole subsystems on/off at comptime so dead code is eliminated (no runtime flags for structural choices).

**Polymorphism Patterns**
- **Duck Typing at Comptime:** Accept `comptime T: type` or `anytype` and assert capabilities using `@hasDecl`/`@hasField`. Example:
  ```zig
  pub fn requireId(comptime T: type, v: T) void {
      comptime if (!@hasField(T, "id")) @compileError("Type must have field 'id'");
      _ = v.id; // safe
  }
  ```
- **Runtime Dispatch:** Use explicit vtables (struct of fns + context pointer). Our shared interfaces follow: a context pointer (`*anyopaque`) plus `pub const VTable = struct { fns... }` and thin wrappers.

**Error Architecture (Expanded Rules)**
- **Narrow Public Error Sets:** Public APIs enumerate meaningful errors (no `anyerror`). Compose sets with `||` when combining behaviors.
- **Propagate with `try`:** Use `try` for linear happy-path code; add `defer`/`errdefer` to guarantee cleanup on failure.
- **Handle or Translate with `catch`:** Use `catch |err| switch (err) { ... }` to recover, provide defaults, or translate foreign errors to local sets.
- **Unexpected/Invariant Cases:** For truly impossible states, use `catch unreachable` (debug-only assert). Prefer including `Unexpected` in wrapper sets to surface unknown OS/library errors.
- **Options vs Errors:** Use errors for conditions callers must actively handle (e.g. `FileNotFound`, `EndOfStream`). Use `?T` when absence is an expected query result.
- **Document & Test:** Error names are PascalCase and self-explanatory. Write tests with failing allocators to exercise OOM paths and with timeouts for network tools.

**Namespacing & Re-Exports**
- **No `usingnamespace`:** Removed in modern Zig. Re-export explicitly with `pub const`. Example conditional export without flattening:
  ```zig
  const impl = if (cfg.has_board) @import("board.zig") else @import("mcu.zig");
  pub const mcu = impl.mcu; // explicit source
  ```
- **Import Aliases:** Local convenience aliases are fine (e.g. `const fs = std.fs;`) but avoid collisions with `builtin`/`std.builtin`.

**Migration: mod.zig → module-named barrel**
- Before: `../api/mod.zig`
- After:  `../api.zig` (re-exports `../api/*`)
- Update imports accordingly: `@import("src/shared/api.zig")` or a named build module `@import("api")`.

**Build System Patterns**
- **Named Modules:** In `build.zig`, create named modules and wire them into the root:
  ```zig
  const lib = b.addModule("library", .{ .root_source_file = b.path("src/library.zig") });
  exe.root_module.addImport("library", lib);
  // usage: const library = @import("library");
  ```
- **Separate Artifacts Where Useful:** For reuse, build static libs and link them; otherwise import as a module for single-compilation-unit simplicity.

**Do / Don’t Quick Reference**
- **Do:** encapsulate per-module state in one struct; inject allocators/services; guard features at comptime; return precise error sets; re-export via barrels.
- **Don’t:** leak deep imports; rely on global singletons; expose inferred/private error sets publicly; flatten namespaces; mix 0.14/0.15 APIs.

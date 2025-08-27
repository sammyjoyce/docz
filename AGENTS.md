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
	•	src/shared/: cli/, tui/, render/, components/, network/, tools/, auth/, json_reflection/, term/ (each with mod.zig barrel).
	•	examples/, tests/.
	•	Build commands:
	◦	zig build -Dagent=<name> [run|run-agent|install-agent|test]
	◦	zig build list-agents | validate-agents | scaffold-agent -- <name>
	◦	Multi: zig build -Dagents=a,b ; Release: -Drelease-safe ; Size: -Doptimize-binary.

## Architecture Principles (enforced)
	•	Independence: only selected agent compiles.
	•	Shared infra via src/core + src/shared/*.
	•	Barrel exports: every shared dir exposes clean API via mod.zig.
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
	•	Dirs/files: snake_case; mod.zig for barrels; single‑type files use PascalCase.zig.
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
	•	json_reflection/ (schema validation, typed JSON)
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
- Modules: barrel exports via `mod.zig`; no deep imports; only the selected agent compiles.
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


# Markdown Agent Refactor Plan — Foundation Integration

Status: Proposed • Owner: TBD • Last Updated: 2025-09-01

This document defines a complete, staged plan to refactor the Markdown agent to cleanly use the shared foundation module and the single, canonical engine loop. Phase 3 (Interactive UI) is optional and gated.

## Objectives

- Unify agent execution via `foundation.agent_main` + `core_engine` (no custom loops).
- Register all Markdown tools through `foundation.tools.Registry` so tool_use works.
- Align configuration with `foundation.config.AgentConfig` and 0.15.1 idioms.
- Enforce barrel imports, feature-gating, and narrow error sets.
- Keep interactive UI optional, behind build options, with no dead imports by default.

## Non‑Goals

- Rewriting the shared engine or foundation surface.
- Shipping an interactive TUI in this refactor (optional Phase 3 only).
- Changing network/auth flows beyond using existing foundation auth.

## Constraints & Assumptions

- Zig 0.15.1; new `std.Io` Writer/Reader; no `usingnamespace`; avoid `anyerror` exports.
- Build commands from repo guidelines must pass: `list-agents`, `validate-agents`, agent tests.
- The agent must compile when TUI is disabled (manifest sets `.terminal_ui = false`).

## Architectural Alignment (Target)

- Entrypoint: `agents/markdown/main.zig` → `foundation.agent_main.runAgent(core_engine, alloc, spec.SPEC)`.
- Spec: `agents/markdown/spec.zig` exposes `SPEC: core_engine.AgentSpec`:
  - `buildSystemPrompt(alloc, opts)` → load `system_prompt.txt` with minimal variable injection.
  - `registerTools(registry)` → register markdown tools via `foundation.tools` helpers.
- Engine: the only run loop → `src/engine.zig`.
- Tools: JSON tools under `agents/markdown/tools/*.zig`, registered with metadata.
- Config: `agents/markdown/config.zon` matches `foundation.config.AgentConfig` field names.
- Feature gating: interactive/TUI code under `comptime if (build_options.enable_tui)`.
- Barrels: only import via `@import("foundation")` and named modules; no deep imports.

## Current State Summary (findings)

- `main.zig` bypasses `agent_main`; reimplements CLI/auth.
- `spec.zig` registers only builtins; markdown tools not registered.
- `config.zon` uses keys that don’t match `foundation.config.AgentConfig`.
- UI code references non-existent `../../examples/diff_viewer.zig`.
- Duplicate loops in `InteractiveSession.zig` / `ProgressiveSession.zig`.
- Some public surfaces use `anyerror`; feature gating missing around UI.

## Scope & Deliverables

### Phase 1 — Wiring & Correctness (required)

Goals:
- Switch to shared CLI/engine/auth; expose markdown tools; fix config alignment.

Tasks:
- `agents/markdown/main.zig`
  - Replace custom `main()` with `foundation.agent_main.runAgent(core_engine, allocator, spec.SPEC)`.
  - Remove bespoke `auth`/OAuth flags; rely on `foundation.cli auth ...` subcommands.
- `agents/markdown/spec.zig`
  - Keep `registerBuiltins`.
  - Register JSON tools using `foundation.tools.registerJsonTool`:
    - `io.execute`, `content_editor.execute`, `validate.execute`, `document.execute`, `workflow.execute`, `file.execute`.
  - Set `agentName = "markdown"` in metadata.
- `agents/markdown/config.zon`
  - Align field names to `foundation.config.AgentConfig`:
    - `.defaults.concurrentOperationsMax` (was `maxConcurrentOperations`)
    - `.defaults.timeoutMsDefault` (was `defaultTimeoutMs`)
    - `.limits.inputSizeMax` / `.outputSizeMax` / `.processingTimeMsMax` (was `max*`)
    - `.model.modelDefault` (was `defaultModel`)
  - Keep agent-specific fields as-is.
- Remove broken deep import(s): delete or stub references to `../../examples/diff_viewer.zig`.

Acceptance Criteria:
- `zig build list-agents` and `zig build validate-agents` succeed.
- `zig build -Dagent=markdown run` prints engine banner; unauthenticated prompt shows standard auth hint.
- Tool registry lists markdown tools; a local smoke call to each tool function returns JSON.
- `config.zon` loads with no warnings; default values apply only when expected.

Risks & Mitigations:
- Tool name mismatches → standardize to stable names (`io`, `content_editor`, `validate`, `document`, `workflow`, `file`).
- JSON shape drift → add minimal tool tests (Phase 4) and keep error messages precise.

### Phase 2 — Cleanups & Idioms (required)

Goals:
- Remove drift and align with idiomatic patterns.

Tasks:
- Rename `agents/markdown/Agent.zig` → `agent.zig`; single entry struct with `const Self = @This();`.
- Update imports accordingly (spec only if needed).
- Remove duplicate run loops (`InteractiveSession.zig`, `ProgressiveSession.zig`) or move them to an examples/demo directory and exclude from build via flags.
- Narrow error surfaces: replace exported `anyerror` with composed error sets or local `Error` types.
- Feature gating: guard UI/editor modules under `comptime if (build_options.enable_tui)`.
- Barrel discipline: ensure all imports use `foundation` barrels; eliminate any remaining deep imports.

Acceptance Criteria:
- Grep shows no agent-owned run loops in markdown agent path.
- No exported `anyerror` across the agent’s public surfaces.
- Building markdown agent with default flags excludes UI code and compiles clean.

### Phase 3 — Interactive UI (optional, gated)

Goals:
- Provide opt-in TUI pathway using `foundation.tui.agent_ui` patterns.

Tasks (optional):
- Introduce a separate subcommand or demo target (e.g., `zig build -Dagent=markdown run -- --ui` or a foundation CLI workflow) that launches UI components without owning a loop.
- Use widgets from `foundation.tui.widgets` and avoid deep imports.
- Keep `.terminal_ui = false` by default in manifest; flip only when ready.

Acceptance Criteria:
- Enabling TUI flag compiles and runs UI demo without changing the default binary footprint.

### Phase 4 — Tests & Docs (required)

Goals:
- Validate tools, config, and spec prompt; prevent regressions.

Tasks:
- Add tests (suggested files):
  - `tests/markdown_tools.zig`: unit tests for each JSON tool (success/failure), minimal failing-allocator path.
  - `tests/markdown_spec.zig`: verify `buildSystemPrompt` loads template; simple variable injection.
  - `tests/markdown_config.zig`: parse `config.zon` and assert mapped values.
- Docs:
  - Update `agents/markdown/README.md` with run instructions, required auth, examples.
  - Update `AGENTS.md` entry to reflect foundation integration.

Acceptance Criteria:
- `zig test tests/all_tests.zig` (or `zig build -Dagent=markdown test`) passes locally (network off).
- Import boundary scripts show no violations.

## Work Breakdown & Dependencies

| ID | Task | Files | Depends On | Est. |
|---|---|---|---|---|
| P1-1 | Switch to `agent_main` | agents/markdown/main.zig | — | S |
| P1-2 | Register tools in spec | agents/markdown/spec.zig, agents/markdown/tools/* | P1-1 | S |
| P1-3 | Align config schema | agents/markdown/config.zon, agents/markdown/Agent.zig | — | S |
| P1-4 | Remove deep imports | agents/markdown/markdown_ui.zig, ui.zig | — | XS |
| P2-1 | Rename `Agent.zig` → `agent.zig` | agents/markdown/* | P1-3 | S |
| P2-2 | Remove/park loops | agents/markdown/Interactive*.zig, *Session*.zig | P1-1 | M |
| P2-3 | Narrow error sets | agents/markdown/* | P2-1 | M |
| P2-4 | Gate UI code | agents/markdown/* | P1-4 | S |
| P4-1 | Tool tests | tests/markdown_tools.zig | P1-2 | S |
| P4-2 | Spec/config tests | tests/markdown_spec.zig, tests/markdown_config.zig | P1-3 | S |
| P4-3 | Docs update | agents/markdown/README.md, AGENTS.md | P1 | S |

Legend: XS=<1h, S≈1–2h, M≈2–4h.

## Detailed Guidance & Examples

### Entrypoint change (Phase 1)

```zig
// agents/markdown/main.zig (after)
const std = @import("std");
const foundation = @import("foundation");
const engine = @import("core_engine");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    try foundation.agent_main.runAgent(engine, gpa.allocator(), spec.SPEC);
}
```

### Tool registration (Phase 1)

```zig
fn registerToolsImpl(registry: *tools.Registry) !void {
    try tools.registerBuiltins(registry);
    // Agent tools (JSON wrappers)
    try tools.registerJsonTool(registry, "io", "Document I/O", @import("tools/io.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "content_editor", "Content editing", @import("tools/content_editor.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "validate", "Validation", @import("tools/validate.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "document", "Document ops", @import("tools/document.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "workflow", "Workflow engine", @import("tools/workflow.zig").execute, "markdown");
    try tools.registerJsonTool(registry, "file", "FS ops", @import("tools/file.zig").execute, "markdown");
}
```

### Config key mapping (Phase 1)

| Old key | New key |
|---|---|
| `.defaults.maxConcurrentOperations` | `.defaults.concurrentOperationsMax` |
| `.defaults.defaultTimeoutMs` | `.defaults.timeoutMsDefault` |
| `.limits.maxInputSize` | `.limits.inputSizeMax` |
| `.limits.maxOutputSize` | `.limits.outputSizeMax` |
| `.limits.maxProcessingTimeMs` | `.limits.processingTimeMsMax` |
| `.model.defaultModel` | `.model.modelDefault` |

### Feature gating example (Phase 2)

```zig
const build_options = @import("build_options");
comptime if (build_options.enable_tui) {
    // TUI-only code here
}
```

## Verification & QA Checklist

- Build/validate
  - [ ] `zig build list-agents` prints all agents; no warnings.
  - [ ] `zig build validate-agents` shows markdown valid.
  - [ ] `zig build -Dagent=markdown run` shows banner; unauthenticated path hints correctly.
- Tools
  - [ ] Registry lists markdown tools (log/printf or test assertion).
  - [ ] Each JSON tool returns valid JSON and handles missing/invalid parameters.
- Config
  - [ ] Loading `agents/markdown/config.zon` logs success (not defaults fallback) where applicable.
- Imports
  - [ ] No deep imports or references to non-existent `examples/*`.
- Error surfaces
  - [ ] No exported `anyerror` from agent modules.
- Tests
  - [ ] New tests pass locally without network.

## Rollout & Backout

Rollout:
- Land Phase 1 as a minimal PR; verify end-to-end build.
- Follow with Phase 2 cleanups PR.

Backout:
- Phase 1 changes are isolated to agent files; reverting the PR restores previous behavior.
- Keep UI code parked but gated, so no backout needed there.

## Risks & Mitigations

- Config mismatches → Provide mapping; add tests to assert parsed values.
- Tool name drift → Centralize names in `spec.zig` registration; document in manifest.
- Hidden UI dependencies → Gate all UI code via `build_options.enable_tui` to avoid accidental imports.

## Open Questions

- Do we want environment overrides for the agent’s default model at runtime?
- Should Phase 2 move old interactive files to `agents/markdown/legacy/` for clarity?

## Commands Reference

```sh
# List & validate agents
zig build list-agents
zig build validate-agents

# Build/run markdown agent (auth required for inference)
zig build -Dagent=markdown run

# Run tests
zig build -Dagent=markdown test
zig test tests/all_tests.zig

# Formatting & import checks
zig fmt src/**/*.zig build.zig build.zig.zon
scripts/check_imports.sh
```

---
This plan is designed to minimize risk by separating wiring from larger cleanups, and by keeping the interactive UI strictly optional and gated.


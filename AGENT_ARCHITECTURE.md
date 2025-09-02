# Agent Architecture

## Overview

Docz uses an engine‑centric design: one shared run loop powers all agents. Each agent supplies only its system prompt and tools. This keeps agent code small and focused, while networking, auth, streaming, and tool execution are standardized and reused.

As of September 1, 2025, the legacy experimental loop is deprecated. The canonical loop lives in `src/engine.zig` and is invoked via `src/foundation/agent_main.zig`. The previous export `foundation.agent` (which pointed to `src/agent_loop.zig`) has been removed to prevent accidental use.

## Directory Structure

- `src/engine.zig` — Single shared run loop
  - Messages API (non‑streaming and SSE streaming)
  - Tool JSON delta assembly (`input_json_delta`), execution, and result hand‑back
  - Emits Anthropic `tools` payload; when tools register required fields, the engine includes a minimal `input_schema` with `required` for better guidance
  - Usage/cost reporting and output (stdout / optional file)
  - Auth wiring through foundation/auth

- `src/foundation/` — Shared subsystems (barrels, no `mod.zig`)
  - `agent_main.zig` — Standardized CLI/auth entry; calls engine
  - `network/` — `Anthropic` client and `Auth` (API key + OAuth)
  - `tools/` — Registry and helpers (`registerJsonTool`, module registration)
  - `cli/`, `tui/`, `render/`, `ui/`, `term/` — Optional UX layers (feature‑gated)

- `agents/<name>/`
  - `main.zig` — Thin entry calling `agent_main.runAgent(alloc, spec.SPEC)`
  - `spec.zig` — Exports `pub const SPEC: engine.AgentSpec` with system prompt builder + tool registration
  - `agent.zig` — Agent types/helpers only (no loop/CLI)
  - Optional: `config.zon`, `tools.zon`, `system_prompt.txt`, `tools/`

## Responsibilities

- Engine (`src/engine.zig`)
  - Owns the run loop (SSE, tool JSON, history trimming, output)
  - Builds and submits requests; integrates auth; reports usage/cost

- Standard Entry (`src/foundation/agent_main.zig`)
  - Parses CLI, handles built‑in subcommands (auth, help), invokes engine

- Agent Spec (`agents/<name>/spec.zig`)
  - `buildSystemPrompt(alloc, options) ![]const u8`
  - `registerTools(registry: *tools.Registry) !void`

- Agent Implementation (`agents/<name>/agent.zig`)
  - Single‑entry struct with state and helpers; no loop or CLI code

## Engine Flow (Messages API)

1. Resolve credentials via foundation/auth (API key or OAuth). For OAuth first‑run, `agent_main` can route to CLI auth.
2. Build message array and optional top‑level `system` using AgentSpec and CLI flags.
   - System prompt policy is defined in `specs/anthropic-messages.md` (including rules for `prompt/anthropic_spoof.txt`).
3. Non‑streaming: POST `/v1/messages`, print content, report usage/cost.
4. Streaming: consume SSE, emit `text_delta`, accumulate tool parameters via `input_json_delta`, finalize on `content_block_stop`.
5. On tool request: execute via registry, append a `tool_result` block in a new user turn, loop until no pending tool use remains.
6. Flush outputs and exit.

## AgentSpec Contract

```zig
const std    = @import("std");
const engine = @import("core_engine");
const tools  = @import("foundation").tools;

fn buildSystemPromptImpl(alloc: std.mem.Allocator, opts: engine.CliOptions) ![]const u8 {
    _ = opts; // may drive prompt selection in the future
    // Example: load/compose agents/<name>/system_prompt.txt
    return try alloc.dupe(u8, "You are a helpful coding agent.");
}

fn registerToolsImpl(reg: *tools.Registry) !void {
    const t = @import("tools.zig");
    try tools.registerJsonTool(reg, "example", "Demo tool", t.example, "my_agent");
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools     = registerToolsImpl,
};
```

## Coding Standards (Zig 0.15.1)

- Barrels named for the namespace (e.g., `src/foundation/tui.zig`); no `mod.zig`
- Single‑entry struct per module; inject allocators/services explicitly
- Narrow public error sets; avoid exposing `anyerror`
- Feature‑gate optional subsystems at comptime; avoid deep cross‑module imports

## Build & Selection

- List/validate agents: `zig build list-agents`, `zig build validate-agents`
- Run an agent: `zig build -Dagent=<name> run`
- Test an agent: `zig build -Dagent=<name> test`
- Formatting/import checks per repository guidelines

## Authentication

- API key and OAuth (Claude Pro/Max) supported via foundation/auth
- CLI subcommands (e.g., `auth login/status/refresh`) handled by `agent_main`

## Migration Notes

- Removed `src/agent.zig` to eliminate duplication with the shared engine and standardized entry
- Agents must not implement bespoke loops or CLI; rely on `engine.zig` and `agent_main.zig`

## Testing Guidance

- Unit test tool functions and prompt builders (include failing allocators)
- End‑to‑end tests use the selected agent via `zig build -Dagent=<name> test`
- Exercise OAuth and API‑key paths; validate SSE tool JSON assembly and termination

# Engine-Centric Agent Loop (Zig 0.15.1)

This document specifies the single, shared run loop used by all agents and clarifies responsibilities across modules so agent implementations remain small. The loop lives in `src/engine.zig` and is invoked by a standardized entry (`src/foundation/agent_main.zig`). Agents in `agents/<name>/` should not re‑implement a bespoke 300‑line loop.

---

## 1. Guiding Principles

1. **One engine, many agents** – the run loop is centralized in `src/engine.zig`. Agents contribute prompts and tools; they don’t copy the loop.
2. **Small agent surface** – agent implementations focus on business logic: system prompt, tool registration, and optional config. No custom CLI or REPL plumbing.
3. **Clear context hygiene** – the engine aggressively trims history and handles SSE tool JSON correctly.
4. **Tools are first‑class** – tools are registered via the shared registry; the engine streams tool parameters and executes results.
5. **Fail‑open, observable** – the engine logs clearly and recovers from tool failures with actionable messages.

---

## 2. High‑Level Flow (Engine)

```
┌────────────────────┐      ┌────────────────────┐
│ 1. initialize      │◀────▶│  Tool Registry     │
└────────┬───────────┘      └────────┬───────────┘
         │                            │
         ▼                            ▼
┌──────────────────────────────────────────────────┐
│            2. engine.runWithOptions             │
│   ┌──────────────────────────────────────────┐   │
│   │ while (streaming) {                     │   │
│   │   stream SSE; collect text + tool JSON; │   │
│   │   if (tool requested) {                 │   │
│   │     exec tool; append tool_result;      │   │
│   │     continue;                           │   │
│   │   } else break;                         │   │
│   │ }                                       │   │
│   └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

---

## 3. Module Responsibilities (Layered)

| Module (file)                 | Public API                                         | Role |
|------------------------------|----------------------------------------------------|------|
| `src/engine.zig`             | `pub fn runWithOptions(alloc, opts, spec, dir)`    | The one shared run loop (streaming + tools + auth wiring). |
| `src/foundation/agent_main.zig` | `pub fn runAgent(alloc, spec)`                   | Standardized entry: parse CLI, handle auth subcommands, call engine. |
| `src/foundation/tools/*.zig` | registry fns (`registerJsonTool`, etc.)            | Shared tools surface and dispatch. |
| `src/foundation/network/*`   | `Anthropic.Client`, Auth (API key + OAuth)         | HTTP/SSE client, credential management. |
| `agents/<name>/spec.zig`     | `pub const SPEC: engine.AgentSpec`                 | Agent’s system prompt builder + tool registration. |
| `agents/<name>/agent.zig`    | Agent’s types/helpers (single‑entry struct)        | Agent‑specific logic (no loop/CLI). |
| `agents/<name>/main.zig`     | `agent_main.runAgent(alloc, SPEC)`                 | Thin entry point per agent. |

All agents compile with their own `agents/<name>/main.zig` and reuse the same engine and foundation.

---

## 4. Engine Loop Stages

### 4.1 initialize()

1. Load env vars (`ANTHROPIC_API_KEY`, etc.).
2. Instantiate a `std.heap.ArenaAllocator` for the entire session.
3. Register core tools (filesystem, git, oracle, etc.).
4. Boot REPL UI and print banner.

### 4.2 input collection

The engine accepts input from CLI flags (`--input`, stdin when `-`), or interactive modes enabled by foundation components. Agents do not implement REPLs.

### 4.3 runInference()

1. Serialises conversation to JSON, trimming oldest messages when `tokens(conv) > 160k`.
2. Makes streaming POST to `/v1/messages`.
3. Collects streamed deltas into `AssistantResponse` (text + optional tool calls payload).

### 4.4 execTools()

1. For each tool-call block, look up by `name` in registry.
2. Spawn `std.Thread.spawn` when the tool is `isConcurrent` && model suggested parallelism.
3. Capture `stdout`, `stderr`, and `return` JSON; on error, wrap into `ToolError{ name, message }`.
4. Return aggregated `[]ToolResult` to caller.

### 4.5 output

Engine streams assistant text to stdout and optionally to a file (`--output`). UI/TUI embellishments live under `foundation/` and are feature‑gated.

### 4.6 context hygiene strategy

* Keep **system prompt** + **last N user/assistant/tool exchanges** + **scratch-pad**.
* When tool results exceed `12k` tokens, summarise them using the **oracle** tool before reinsertion.

---

## 5. Concurrency & Zig 0.15.1 Considerations

* Use `async` functions & the default event-loop rather than manual threads when latency hiding is needed (API + tool exec concurrently).
* Prefer **slice-based** APIs; avoid hidden heap unless via the session arena.
* All JSON handling via `std.json` DOM + `std.json.Stringify.valueAlloc`; wrap in helper `JsonValue` struct.
* HTTP via `std.http.Client` (added in 0.15.0).

---

## 6. Extensibility Hooks

1. **Middleware** – a `[]ToolInvoker` chain can intercept tool calls (e.g., for tracing).
2. **Plugins** – .so files loaded with `std.DynamicLibrary.open()` exporting `registerTools`.
3. **Persistence** – optional `--history my.jsonl` flag serialises conv on exit and reloads on start.

---

## 7. Safety & Observability

* Every external call is wrapped in a `timeout` combinator.
* Structured logs (`std.log.scoped(.agent)`) include `conversation_id`, `tool_name`, `latency_ms`.
* `--verbose` flag dumps raw Claude payloads for debugging.

---

## 8. Non‑Goals for v0

* Multi-user server mode.
* Advanced scheduling / planning agents (can be layered later).
* SIMD / GPU token counting – an estimated heuristic is fine.

---

## 9. Usage Patterns (Agent‑centric)

Minimal agent entry:

```zig
// agents/<name>/main.zig
const std = @import("std");
const agentMain = @import("foundation").agent_main;
const spec = @import("spec.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    try agentMain.runAgent(gpa.allocator(), spec.SPEC);
}
```

Agent spec:

```zig
// agents/<name>/spec.zig
const engine = @import("core_engine");
const tools = @import("foundation").tools;
const impl = @import("agent.zig");

fn buildSystemPromptImpl(a: anytype, opts: engine.CliOptions) ![]const u8 {
    _ = opts; var agent = try impl.Agent.initFromConfig(a); defer agent.deinit();
    return agent.loadSystemPrompt();
}

fn registerToolsImpl(reg: *tools.Registry) !void {
    const t = @import("tools.zig");
    try tools.registerJsonTool(reg, "example", "desc", t.example, "<name>");
}

pub const SPEC: engine.AgentSpec = .{ .buildSystemPrompt = buildSystemPromptImpl, .registerTools = registerToolsImpl };
```

---

## 10. Migration Notes

- The canonical loop is `src/engine.zig` invoked by `foundation/agent_main.runAgent()`.
- Agents must not duplicate CLI parsing or stream handling. Keep agent code minimal and rely on the shared engine.

# Core Agent Loop Specification (Zig 0.15.1)

This document captures the **minimal viable loop** that turns the Docz binary into a fully-featured coding agent.  It is adapted from the reference Golang starter loop and from the principles outlined in “How to build a coding agent: free workshop”.  All design decisions below are aligned with Zig 0.15.1 language features and the existing project layout.

---

## 1. Guiding Principles

1. **300 LoC target** – keep the loop small, readable, and easily hackable.
2. **Single-responsibility loop** – the loop does only three things:
   1. get user / system input,
   2. pass it (plus tool results) to the LLM,
   3. execute any tool calls returned by the model.
3. **Clear context hygiene** – allocate *one* activity per inference window; purge irrelevant history aggressively.
4. **Tooling as first-class citizens** – expose tools through the MCP registry; treat *other LLMs* as tools (oracle pattern).
5. **Fail-open, observe, correct** – the loop never panics; it logs and asks the LLM to self-heal when a tool call fails.

---

## 2. High-level Flow Diagram

```
┌────────────────────┐      ┌────────────────────┐
│ 1. initialise()    │◀────▶│  Tool Registry     │
└────────┬───────────┘      └────────┬───────────┘
         │                            │
         ▼                            ▼
┌──────────────────────────────────────────────────┐
│              2. eventLoop()                     │
│   ┌──────────────────────────────────────────┐   │
│   │ while (true) {                          │   │
│   │     input = getNextUserMessage();       │   │
│   │     if (input == null) continue;        │   │
│   │                                          │   │
│   │     conv.addUser(input);                 │   │
│   │     let resp = runInference(conv);       │   │
│   │                                          │   │
│   │     if (resp.containsToolCalls()) {      │   │
│   │         let results = execTools(resp);   │   │
│   │         conv.addAssistant(resp.textOnly);│   │
│   │         conv.addToolResults(results);    │   │
│   │         continue; // iterate again       │   │
│   │     }                                    │   │
│   │                                          │   │
│   │     display(resp.textOnly);              │   │
│   │   }                                      │   │
│   └──────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

---

## 3. Module Responsibilities

| Module (file)     | Public API                               | Notes |
|-------------------|------------------------------------------|-------|
| `agent.zig`       | `pub fn run(alloc: *Allocator) !void`    | Orchestrates `initialise` + `eventLoop`. |
| `anthropic.zig`   | `fn complete(messages: []Message) !Resp` | Thin HTTP client for Claude Sonnet; keeps zero global state. |
| `tools.zig`       | `pub fn register(name: []const u8, fn execute(JSON) !JSON)` | Simple in-process registry. |
| `conversation.zig`| append / slice / purge helper fns        | Stores history in an `ArrayList(Message)` backed by an arena allocator. |
| `io.zig`          | TTY / REPL helpers                       | Fully async; uses `std.io.getStdIn().reader()`. |
| `errors.zig`      | `logFailure`, retry helpers              | Unifies transient vs fatal errors. |

All modules compile into the existing `src/main.zig` executable.

---

## 4. Detailed Loop Stages

### 4.1 initialise()

1. Load env vars (`ANTHROPIC_API_KEY`, etc.).
2. Instantiate a `std.heap.ArenaAllocator` for the entire session.
3. Register core tools (filesystem, git, oracle, etc.).
4. Boot REPL UI and print banner.

### 4.2 getNextUserMessage()

Non-blocking read from STDIN; returns `null` when only a newline was entered (keeps loop hot like in the Go sample).

### 4.3 runInference()

1. Serialises conversation to JSON, trimming oldest messages when `tokens(conv) > 160k`.
2. Makes streaming POST to `/v1/messages`.
3. Collects streamed deltas into `AssistantResponse` (text + optional tool calls payload).

### 4.4 execTools()

1. For each tool-call block, look up by `name` in registry.
2. Spawn `std.Thread.spawn` when the tool is `isConcurrent` && model suggested parallelism.
3. Capture `stdout`, `stderr`, and `return` JSON; on error, wrap into `ToolError{ name, message }`.
4. Return aggregated `[]ToolResult` to caller.

### 4.5 display()

Streams assistant text to terminal with colours; if the assistant proposes code, pipe through `zig fmt` before display.

### 4.6 context hygiene strategy

* Keep **system prompt** + **last N user/assistant/tool exchanges** + **scratch-pad**.
* When tool results exceed `12k` tokens, summarise them using the **oracle** tool before reinsertion.

---

## 5. Concurrency Model & Zig 0.15.1 Considerations

* Use `async` functions & the default event-loop rather than manual threads when latency hiding is needed (API + tool exec concurrently).
* Prefer **slice-based** APIs; avoid hidden heap unless via the session arena.
* All JSON handling via `std.json` DOM + `std.json.stringifyAlloc`; wrap in helper `JsonValue` struct.
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

## 8. Non-Goals for v0

* Multi-user server mode.
* Advanced scheduling / planning agents (can be layered later).
* SIMD / GPU token counting – an estimated heuristic is fine.

---

## 9. Pseudocode Implementation (abridged)

```zig
pub fn run(alloc: *Allocator) !void {
    try initialise(alloc);
    while (true) {
        if (try io.getNextUserMessage(alloc)) |msg| {
            try conv.addUser(msg);
            var resp = try anthropic.complete(conv.messages());
            if (resp.toolCalls.len > 0) {
                var results = try execTools(alloc, resp.toolCalls);
                try conv.addAssistant(resp.text);
                try conv.addToolResults(results);
                continue; // start next cycle immediately
            }
            io.display(resp.text);
            try conv.addAssistant(resp.text);
        }
    }
}
```

> **≈270 LoC** across `src/` without tests; comfortably inside the 300-line target.

---

## 10. Next Steps

* Flesh out the HTTP client (streaming decode).
* Implement `tool_git.zig` and `tool_filesystem.zig`.
* Hook the loop into existing `main.zig` CLI flags.

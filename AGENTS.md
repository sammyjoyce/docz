Multi‑Agent Terminal AI System — Code Review Cheat Sheet
Purpose
	•	Build independent terminal agents on shared infra with minimal duplication.
	•	Enforce consistent structure, names, errors, config, and build rules.
Assumptions & Risks
	•	Targeting Zig 0.15.1 semantics (IO, formatting, containers). If compiling with 0.14.x, expect breakage.
	•	Agents compile independently; unused modules must not leak in.
	•	ZON at comptime, JSON at runtime; avoid mixing concerns.

Directory & Build Layout (must match)
	•	agents/<name>/: main.zig (CLI entry), spec.zig (prompt+tools), agent.zig (impl); optional: config.zon, system_prompt.txt, tools.zon, tools/, common/, examples/, README.md.
	•	src/core/: engine.zig, config.zig, agent_base.zig, agent_main.zig.
	•	src/shared/: cli/, tui/, render/, components/, network/, tools/, auth/, json_reflection/, term/ (each with mod.zig barrel).
	•	examples/, tests/.
	•	Build commands:
	◦	zig build -Dagent=<name> [run|run-agent|install-agent|test]
	◦	zig build list-agents | validate-agents | scaffold-agent -- <name>
	◦	Multi: zig build -Dagents=a,b ; Release: -Drelease-safe ; Size: -Doptimize-binary.

Architecture Principles (enforced)
	•	Independence: only selected agent compiles.
	•	Shared infra via src/core + src/shared/*.
	•	Barrel exports: every shared dir exposes clean API via mod.zig.
	•	Compile‑time agent interface: static verification + dead‑code elimination.
	•	Build‑generated registry: scan agents/, validate required files, fail loud.
	•	Selective inclusion: feature flags gate shared modules.
	•	Clean error sets: no anyerror; use AgentError, ConfigError, ToolError.
	•	Service interfaces: network/terminal/config/tools are swappable/testable.

Input System Layering (don’t break)
shared/term/input (primitives) → shared/components/input.zig (abstraction) → shared/tui/core/input (TUI features). No cross‑layer shortcuts.

Config & Prompts
	•	ZON for static config & tool schemas (agents/<name>/config.zon, tools.zon).
	•	Load with @embedFile + std.zig.parseFromSlice.
	•	Template vars in prompts auto‑filled from config: {agent_name}, {agent_version}, {current_date}, feature flags, limits, model settings.
	•	Pattern: ZON templates → JSON at runtime for API payloads.

Tools Registration (pick one, be consistent)
	•	ZON‑defined tools: define schema/metadata in ZON; validate runtime params.

Naming & Style (reviewers will reject violations)
	•	Dirs/files: snake_case; mod.zig for barrels; single‑type files use PascalCase.zig.
	•	Types: PascalCase; func/vars: camelCase; consts: ALL_CAPS; errors: PascalCase.
	•	Modules: no redundant suffixes (“Module/Lib/Utils”).
	•	Follow Zig Style Guide; run zig fmt.

Core Modules (know where things live)
	•	core/engine.zig: run loop, tool calls, API comms.
	•	core/config.zig: AgentConfig + validation/defaults.
	•	core/agent_base.zig: lifecycle, template vars, config helpers.
	•	core/agent_main.zig: standardized CLI parsing + engine delegation.

Shared Modules (feature‑gated)
	•	cli/ (args, routing, color/output, multi‑step flows)
	•	tui/ (canvas, renderer, widgets, layouts)
	•	render/ (charts/tables/progress, quality levels)
	•	components/ (shared UI incl. unified input)
	•	network/ (HTTP clients, Anthropic/Claude, SSE)
	•	tools/ (registry, metadata, agent attribution)
	•	auth/ (OAuth + API keys; TUI flows; CLI commands)
	•	json_reflection/ (schema validation, typed JSON)
	•	term/ (terminal caps, low‑level input/mouse)

Error Handling (hard rules)
	•	Define specific error sets; do not export anyerror.
	•	Public APIs return typed errors; handle locally when appropriate.
	•	Use try; catch |e| to attach context; prefer error chaining for debugging.
	•	No panics except unrecoverable invariants (documented).

Resource & Memory
	•	Use defer for cleanup; clarify ownership.
	•	Prefer stack; use arena allocators for short‑lived bursts.
	•	Avoid leaks in long‑running TUI loops; free after tool invocations.
	•	Keep stdout buffering global if reused; don’t forget flush.

Zig 0.15.1 Key Changes You Must Observe
	•	usingnamespace, async/await, @frameSize: removed.
	•	IO: new std.Io.Reader/Writer concrete types; caller‑owned buffers; ring buffers.
	•	Formatting: {} no longer auto‑calls format; use {f} or {any}; new {t}, {b64}, {d} behavior.
	•	Containers: std.ArrayList is unmanaged; use std.array_list.Managed if needed.
	•	FS: fs.File.reader()/writer() now .deprecatedReader/.deprecatedWriter; prefer new Reader/Writer.
	•	Build: use root_module; UBSan enum (.full|.trap|.off).
	•	Deleted: LinearFifo, RingBuffer, BoundedArray (use ArrayListUnmanaged.initBuffer or fixed slices).

Build & Validation Expectations
	•	CI must run:
	◦	zig build list-agents (registry OK)
	◦	zig build validate-agents (required files present)
	◦	zig build -Dagent=<each> test
	◦	zig build fmt (lint) + zig fmt src/**/*.zig build.zig build.zig.zon
	•	Examples moved to examples/cli_demo/ (don’t assume old path).

Testing Strategy (min bar)
	•	Unit test core services & tools.
	•	Integration test agent E2E (engine ↔ tools ↔ network).
	•	Test error cases (config invalid, tool failure, network timeouts).
	•	Consider fuzzing parsers and terminal input.

Agent Implementation Skeleton (reviewer‑approved)
	•	main.zig: delegate to agent_main.runAgent(); no bespoke CLI parsing.
	•	spec.zig: define system prompt (with template vars) + register tools.
	•	agent.zig: pub const <Name>Agent = struct { config: Config, allocator: Allocator, ... }; implement lifecycle and service usage.
	•	config.zon: extend AgentConfig; set limits, features, model, defaults.

Performance & Binary Size
	•	Feature‑gate shared modules; avoid accidental imports.
	•	Use compile‑time interfaces to prune code paths.
	•	Prefer streaming IO; avoid large heap JSON when not required.
	•	Rendering: use quality levels; avoid overdraw in TUI.

Code Review Pass Checklist
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

Common Pitfalls (preempt them)
	•	Mixing 0.14 and 0.15 IO/formatting APIs.
	•	Leaking agent‑specific code into shared modules.
	•	Circular deps across term/ ↔ components/ ↔ tui/.
	•	Tool names with redundant prefixes/snake_case fns.
	•	Prompt templates missing required vars (unreplaced {...}).
	•	Pulling in tui/ or render/ without feature‑gating.

# Zig Idioms and Patterns — updated for Zig 0.15.1

> Notes for 0.15.1:
> - `usingnamespace` is removed. Prefer explicit re-exports (as shown below). :contentReference[oaicite:0]{index=0}
> - I/O APIs changed (Writergate). These examples avoid the old `std.io.*` surface. :contentReference[oaicite:1]{index=1}
> - Build system fields like `root_source_file` are gone; use the newer `root_module`‑based APIs in `build.zig`. (Not shown here.) :contentReference[oaicite:2]{index=2}

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
```

## Resource Management

### RAII (init/deinit with `defer` / `errdefer`)

```zig
const Resource = struct {
    handle: Handle,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Resource {
        // acquireHandle/releaseHandle are placeholders for your real resource ops
        const handle = try acquireHandle();
        return .{
            .handle = handle,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Resource) void {
        releaseHandle(self.handle);
    }
};

// Usage
var resource = try Resource.init(allocator);
defer resource.deinit();

// --- placeholders to make the snippet self-contained
const Handle = usize;
fn acquireHandle() !Handle { return 1; }
fn releaseHandle(handle: Handle) void { _ = handle; }
```

**Pitfalls / 0.15.1 notes**

* Keep `deinit` infallible; pair fallible acquires with `errdefer` to clean up partially acquired state.
* If you expose this across module boundaries, document ownership and allocator used (callers may switch allocators per 0.15.1 std guidance on “unmanaged by default” containers). ([Zig Programming Language][1])

---

### Builder Pattern (value‑chaining that compiles)

> Chaining on a temporary with `self: *Builder` fails because rvalues aren’t addressable. Use value‑semantics: each call returns a new `Builder`.

```zig
const ServerConfig = struct {
    port: u16 = 8080,
    host: []const u8 = "localhost",
    max_connections: usize = 100,
    timeout_ms: u64 = 30_000,

    pub fn builder() Builder {
        return .{};
    }

    const Builder = struct {
        config: ServerConfig = .{},

        pub fn port(self: Builder, p: u16) Builder {
            var next = self;
            next.config.port = p;
            return next;
        }

        pub fn host(self: Builder, h: []const u8) Builder {
            var next = self;
            next.config.host = h;
            return next;
        }

        pub fn maxConnections(self: Builder, n: usize) Builder {
            var next = self;
            next.config.max_connections = n;
            return next;
        }

        pub fn timeoutMs(self: Builder, ms: u64) Builder {
            var next = self;
            next.config.timeout_ms = ms;
            return next;
        }

        pub fn build(self: Builder) ServerConfig {
            return self.config;
        }
    };
};

// Usage (chains cleanly)
const config = ServerConfig.builder()
    .port(3000)
    .host("0.0.0.0")
    .maxConnections(500)
    .timeoutMs(45_000)
    .build();
```

**Trade‑offs**

* Value‑builders copy; for fat configs, prefer a `var b = ServerConfig.builder();` + pointer receiver mutators, then `b.build()`. Keep mutators returning `*Builder` in that variant.

---

## Error Handling Patterns

### Result Type (when you *really* want a Rust‑like result)

```zig
fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        ok: T,
        err: E,

        pub fn isOk(self: @This()) bool {
            return self == .ok;
        }

        pub fn unwrap(self: @This()) T {
            return switch (self) {
                .ok => |value| value,
                .err => @panic("unwrap on error"), // fine in 0.15.1
            };
        }
    };
}
```

> Zig’s idiom remains `!T` and `try`; use a bespoke `Result` only for non‑error‑union cases (e.g., domain errors that you don’t want in the error set). The builtin `@panic` remains available. ([Zig Programming Language][2])

---

### Error Context

```zig
const ErrorContext = struct {
    message: []const u8,
    file: [:0]const u8,
    line: u32,
    column: u32,

    pub fn init(message: []const u8) ErrorContext {
        const src = @src(); // builtin present in 0.15.1
        return .{
            .message = message,
            .file = src.file,
            .line = src.line,
            .column = src.column,
        };
    }
};
```

---

## State Management

### State Machine

```zig
const Event = enum { start, stop, pause };

const State = enum {
    idle,
    running,
    stopped,

    pub fn transition(self: State, event: Event) State {
        return switch (self) {
            .idle => switch (event) {
                .start => .running,
                else => self,
            },
            .running => switch (event) {
                .stop => .stopped,
                .pause => .idle,
                else => self,
            },
            .stopped => self,
        };
    }
};
```

### Tagged Union Pattern

```zig
const Message = union(enum) {
    text: []const u8,
    number: i32,
    data: []const u8, // use a slice; len is already part of it

    pub fn process(self: Message) void {
        switch (self) {
            .text => |t| processText(t),
            .number => |n| processNumber(n),
            .data => |bytes| processData(bytes),
        }
    }
};

// placeholders
fn processText(_: []const u8) void {}
fn processNumber(_: i32) void {}
fn processData(_: []const u8) void {}
```

---

## Iterator Pattern (function‑pointer + anyopaque ctx)

```zig
fn Iterator(comptime T: type) type {
    return struct {
        nextFn: *const fn (*anyopaque) ?T,
        context: *anyopaque,

        pub fn next(self: @This()) ?T {
            return self.nextFn(self.context);
        }
    };
}

const RangeIterator = struct {
    current: i32,
    end: i32,

    pub fn init(start: i32, end: i32) RangeIterator {
        return .{ .current = start, .end = end };
    }

    pub fn iterator(self: *RangeIterator) Iterator(i32) {
        return .{
            .nextFn = nextFn,
            .context = self,
        };
    }

    fn nextFn(ctx: *anyopaque) ?i32 {
        // Correct casting pattern in modern Zig: alignCast + ptrCast
        const self: *RangeIterator = @ptrCast(@alignCast(ctx));
        if (self.current >= self.end) return null;
        defer self.current += 1;
        return self.current;
    }
};
```

> `@alignCast` infers alignment from the result type; pairing it with `@ptrCast` is the standard “interface” trick around `anyopaque` in current Zig. See builtins in the 0.15.1 reference. ([Zig Programming Language][2])

---

## Visitor Pattern (with context so handlers can carry state)

```zig
const Visitor = struct {
    ctx: *anyopaque,
    visitIntFn:   *const fn (*anyopaque, i32) void,
    visitFloatFn: *const fn (*anyopaque, f64) void,
    visitStrFn:   *const fn (*anyopaque, []const u8) void,

    pub fn visitInt(self: Visitor, v: i32) void    { self.visitIntFn(self.ctx, v); }
    pub fn visitFloat(self: Visitor, v: f64) void  { self.visitFloatFn(self.ctx, v); }
    pub fn visitString(self: Visitor, v: []const u8) void { self.visitStrFn(self.ctx, v); }
};
```

> Pattern mirrors `std.mem.Allocator`’s interface style (`*anyopaque` + vtable) and is future‑proof. (Allocator remains a `*anyopaque` + vtable design.) ([Reddit][3])

---

## Option Type

```zig
fn Option(comptime T: type) type {
    return union(enum) {
        some: T,
        none,

        pub fn isSome(self: @This()) bool {
            return self == .some;
        }

        pub fn unwrapOr(self: @This(), default: T) T {
            return switch (self) {
                .some => |value| value,
                .none => default,
            };
        }

        pub fn map(self: @This(), comptime f: fn (T) T) @This() {
            return switch (self) {
                .some => |value| .{ .some = f(value) },
                .none => .none,
            };
        }
    };
}
```

---

## Defer Pattern Extensions

### Multiple Resource Cleanup with `errdefer`

```zig
var resources_acquired: usize = 0;
errdefer {
    var i: usize = 0;
    while (i < resources_acquired) : (i += 1) {
        releaseResource(i);
    }
}

const r1 = try acquireResource();
resources_acquired = 1;

const r2 = try acquireResource();
resources_acquired = 2;

// placeholders
fn acquireResource() !usize { return 0; }
fn releaseResource(_: usize) void {}
```

---

## Compile‑Time Interface (duck‑typed “trait”)

```zig
fn Drawable(comptime T: type) type {
    return struct {
        ptr: *T,

        pub fn draw(self: @This()) void {
            // If T doesn't implement `pub fn draw(self: *T)`, this fails at comptime.
            self.ptr.draw();
        }
    };
}

// Any type with a draw() method can be used
const Circle = struct {
    radius: f32,
    pub fn draw(self: *Circle) void {
        _ = self; // Draw circle...
    }
};
```

---

## Module Organization Patterns (post‑`usingnamespace`)

These nine patterns still hold. The big change in 0.15.1 is: do *not* use `usingnamespace`; re‑export explicitly. The examples already do that.

### 1. Re‑export Pattern for Main Module Files

```zig
// main.zig
pub const Config = @import("config.zig").Config;
pub const Server = @import("server.zig").Server;
pub const Client = @import("client.zig");

// Re-export commonly used types
pub const Error = @import("errors.zig").Error;
pub const Result = @import("types.zig").Result;
```

### 2. Single File Modules with Self‑Reference

```zig
const Parser = struct {
    input: []const u8,
    pos: usize = 0,

    pub fn init(input: []const u8) @This() {
        return .{ .input = input };
    }

    pub fn parse(self: *@This()) !Result {
        // Implementation uses @This() for self-reference
        return @This().Result.success;
    }

    const Result = enum { success, failure };
};
```

### 3. Directory‑based Module Organization

```
src/
├── network/
│   ├── main.zig        # Re-exports http.zig, tcp.zig, websocket.zig
│   ├── http.zig        # HTTP implementation
│   ├── tcp.zig         # TCP implementation
│   └── websocket.zig   # WebSocket implementation
└── storage/
    ├── main.zig        # Re-exports database.zig, cache.zig
    ├── database.zig
    └── cache.zig
```

### 4. Self‑contained Modules in Subdirectories

```zig
// network/http.zig
const std = @import("std");
const net = @import("../network.zig");

const HttpClient = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
};
```

### 5. Hierarchical Namespacing with Nested Structs

```zig
pub const crypto = struct {
    pub const hash = struct {
        pub const sha256 = @import("crypto/hash/sha256.zig");
        pub const blake3 = @import("crypto/hash/blake3.zig");
    };

    pub const cipher = struct {
        pub const aes = @import("crypto/cipher/aes.zig");
        pub const chacha = @import("crypto/cipher/chacha.zig");
    };
};
```

### 6. Simple Re‑export Modules

```zig
// types.zig
pub const User = @import("models/user.zig").User;
pub const Session = @import("models/session.zig").Session;
pub const Token = @import("models/token.zig").Token;

// Common type aliases
pub const UserId = u64;
pub const SessionId = [32]u8;
```

### 7. Generic Type Modules

```zig
/// Generic container that holds a value of type T
pub fn Container(comptime T: type) type {
    return struct {
        value: T,

        pub fn init(value: T) @This() {
            return .{ .value = value };
        }

        pub fn get(self: @This()) T {
            return self.value;
        }
    };
}

// Usage
const IntContainer = Container(i32);
```

### 8. Built‑in Test Integration

```zig
const std = @import("std");
const testing = std.testing;

const Calculator = struct {
    pub fn add(a: i32, b: i32) i32 {
        return a + b;
    }

    test "add function" {
        try testing.expect(add(2, 3) == 5);
    }
};

test "refAllDecls (top-level only)" {
    testing.refAllDecls(@This());
    // If you want nested containers too (and your stdlib provides it),
    // prefer: testing.refAllDeclsRecursive(@This());
    // See community notes on recursive variant. 
}
```

*(Community context: `refAllDecls` is a testing convenience and might change; some use a recursive variant to pull in nested symbols.)* ([Ziggit][4])

### 9. Configuration and Options Pattern

```zig
pub const Config = struct {
    max_connections: u32 = 1000,
    timeout_ms: u64 = 5000,
    buffer_size: usize = 4096,

    // Allow compile-time override from root.zig:
    pub const default = if (@hasDecl(@import("root"), "AppConfig"))
        @import("root").AppConfig
    else
        @This(){};
};
```

> With `usingnamespace` gone, some `@hasDecl`‑based feature detection idioms were rethought. If you need robust feature detection, the release notes suggest using a sentinel value (e.g., `void {}`) rather than relying on `@hasDecl`. For a root‑config override like this, `@hasDecl` is still an ergonomic choice. ([GitHub][5])

---

## Best Practices (still good in 0.15.1)

1. Use tagged unions for polymorphic data
2. Implement `init`/`deinit` pairs for resources and make `deinit` infallible
3. Use a value‑chaining builder for clean call sites (or pointer‑builder with a `var`)
4. Prefer error unions (`!T`) + `try` for fallible ops; use custom `Result` only when needed
5. Lean on `comptime` for generics and interface‑like adapters
6. Provide iterators with `{nextFn, context}`; cast via `@alignCast` + `@ptrCast`
7. Use `defer`/`errdefer` for cleanup, especially across multiple acquisitions
8. Prefer composition over inheritance; make invalid states unrepresentable
9. Use optionals (`?T`) when nullable makes sense; custom `Option(T)` when ergonomics demand it
10. Explicit, explicit, explicit—no `usingnamespace`. Re‑export via `pub const` facades. ([Zig Programming Language][1])
11. Organize modules by directories + explicit re‑exports; keep submodules self‑contained
12. Integrate tests in every module; pull in decls (`refAllDecls`/recursive) as needed
13. Provide compile‑time configuration overrides with clear defaults
14. For I/O in 0.15.1+, learn the new `std.Io` Writer/Reader surface before extending these patterns to streams. ([Zig Programming Language][1])

---

### Quick 0.15.1 migration pointers (what might bite you)

* **`usingnamespace` removed** → replace mixins with zero‑bit fields + `@fieldParentPtr`, and do explicit re‑exports. Examples in the release notes show how. ([Zig Programming Language][1])
* **Std I/O redesign (“Writergate”)** → `std.io.BufferedWriter`, `CountingWriter`, etc., have been removed or replaced; prefer the new `std.Io.Writer` surface and concrete file/memory adapters. ([Zig Programming Language][1])
* **Build system** → use `root_module` instead of deprecated fields like `root_source_file`. ([Zig Programming Language][1])


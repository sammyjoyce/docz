# Repository Guidelines

## Project Structure & Module Organization
- Source lives in `src/`. Shared subsystems are under `src/foundation/` (`cli/`, `tui/`, `render/`, `ui/`, `network/`, `tools/`, `term/`). Each namespace exposes a barrel file (e.g., `src/foundation/tui.zig`); avoid deep imports.
- Engine lives in `src/engine.zig` (single shared run loop). Standardized entry lives in `src/foundation/agent_main.zig`.
- Agents in `agents/<name>/` (`main.zig`, `spec.zig`, `agent.zig` (preferred) or legacy `Agent.zig`, optional `config.zon`, `tools.zon`, `system_prompt.txt`, `tools/`). Only the selected agent should compile.
- Tests in `tests/`; docs in `docs/`; helper scripts in `scripts/`.

## Build, Test, and Development Commands
- List/validate agents: `zig build list-agents`, `zig build validate-agents`.
- Run an agent: `zig build -Dagent=<name> run`.
- Test an agent: `zig build -Dagent=<name> test` or `zig test tests/all_tests.zig`.
- Format/import checks: `zig fmt src/**/*.zig build.zig build.zig.zon`; `scripts/check_imports.sh`.
- Scaffold: `zig build scaffold-agent -- <name>`.
- Release/size: add `-Drelease-safe` or `-Doptimize-binary`.

## Coding Style & Naming Conventions
- Zig 0.15.1 required: use new `std.Io` Reader/Writer; no `usingnamespace`; never export `anyerror`.
- Files/dirs: snake_case; barrels named for the namespace (e.g., `tui.zig`), never `mod.zig`.
- Types: PascalCase; funcs/vars: camelCase; constants: ALL_CAPS; error names: PascalCase.
- Run `zig fmt`; keep imports alphabetical (std first).

## Testing Guidelines
- Unit test core services/tools and end-to-end agent flows.
- Cover failure modes (invalid config, tool/network errors, timeouts, OOM via failing allocators).
- CI should run: `list-agents`, `validate-agents`, `-Dagent=<each> test`, and formatting.

## Commit & Pull Request Guidelines
- Messages: imperative mood, concise subject (<72 chars). Prefer Conventional Commits when helpful (`feat:`, `fix:`, `refactor:`, `test:`) as seen in recent history; include scope when clear and link issues.
- PRs: describe intent and impact, include screenshots/gifs for TUI changes, note flags/features touched, and list tests added/updated. Ensure `zig fmt` + validations pass.

## Security & Configuration Tips
- Do not commit secrets. Use ZON for static config (`agents/<name>/config.zon`, `tools.zon`) and render JSON at runtime. Feature‑gate subsystems via build options to keep binaries minimal and avoid accidental imports.

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

## Agent Entrypoints & Responsibilities
- `agents/<name>/main.zig`: Thin entry that calls `@import("foundation").agent_main.runAgent(alloc, spec.SPEC)`.
- `agents/<name>/spec.zig`: Exposes `pub const SPEC: @import("core_engine").AgentSpec` with:
  - `buildSystemPrompt(alloc, options) ![]const u8`
  - `registerTools(registry: *tools.Registry) !void`
- `agents/<name>/agent.zig`: Agent implementation (types/helpers); no run loop, no CLI parsing.

Canonical loop and SSE/tool handling live in `src/engine.zig`. Do not duplicate the loop in agent code or in `src/`—use the shared engine.

## Available Agents

### markdown
- **Version:** 2.0.0
- **Description:** Enterprise-grade markdown systems architect & quality guardian
- **Integration:** Fully integrated with foundation framework
- **Tools:** 6 JSON tools (io, content_editor, validate, document, workflow, file)
- **Features:** Document processing, validation, workflow management
- **Config:** Uses foundation.config.AgentConfig with proper field mapping
- **TUI:** Disabled by default (terminal_ui = false in manifest)

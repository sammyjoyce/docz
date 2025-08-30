

## High‑level goals (non‑negotiables)

- **One‑way deps:** `term → render → ui → widgets` is **forbidden**. The correct direction is `widgets → ui → render → term`. `ui` is pure domain types + traits (no I/O). `render` owns the render loop and diffing. `term` is side‑effects + platform glue.
- **Type‑erasure at the edges, generics within leaves:** `ui.component.Component` is an erased interface (vtable). Inside a widget package you can use generics for speed. This keeps the public API stable and call sites small.
- **Allocator + clock + RNG passed top‑down:** No global allocators or ambient singletons. Surfaces are explicit.
- **No cycles, no hidden IO:** Import graph is enforced in code review: `ui` cannot import `render` or `term`. `widgets` cannot import `term` directly; only through the `render.Context`.

---

## Directory layout (refined)

```
docz/src/shared/
├── term/
│   ├── ansi/
│   ├── color/
│   ├── control/
│   ├── graphics_protocols/
│   ├── input/          # raw key/mouse/resize; platform adapters
│   ├── io/             # filedesc, buffering, write batching
│   ├── pty/
│   ├── query/
│   ├── shell/
│   └── unicode/        # grapheme, wcwidth, East Asian width, bidi (if any)
├── ui/
│   ├── component/      # Component trait & node composition
│   ├── event/
│   ├── layout/
│   └── theme/
├── widgets/
│   ├── progress/
│   ├── notification/
│   ├── input/
│   ├── chart/
│   └── table/
└── render/
    ├── Renderer.zig    # main loop, scheduling, diff, damage tracking
    ├── context.zig     # Render.Context: surface, clip, theme, caches
    ├── surface.zig     # abstraction over terminal/canvas; double buffer
    ├── markdown.zig
    ├── diff.zig
    └── braille.zig
```

**Two small adds:**  
- `render/surface.zig` isolates terminal vs “memory surface” targets, enabling headless tests and future non‑TTY targets.  
- `term/unicode/` is explicit so wcwidth/grapheme logic doesn’t leak into `render`.

---

## Public module exports

Create **one** aggregator `shared/mod.zig` to re‑export stable APIs:

```zig
pub const ui = @import("ui/mod.zig");
pub const widgets = @import("widgets/mod.zig");
pub const render = @import("render/mod.zig");
pub const term = @import("term/mod.zig");

---

## Workflow Steps consolidation (Aug 30, 2025)

- Unified step API under `src/shared/cli/workflows/workflow_step.zig`.
- New types:
  - `WorkflowStep`: the single struct representing a step: `name`, `description`, `executeFn`, `context`, `required`, `timeoutMs`, `retryCount`.
  - `StepContext`: execution context with `parameters`, `previousOutput`, `stepIndex` and `init/deinit` helpers.
  - `WorkflowStepResult`: `{ success, errorMessage, outputData }`.
- Builder methods are defined on `WorkflowStep` (`withDescription`, `withTimeout`, `withRetry`, `asOptional`, `withContext`).
- `CommonSteps` now constructs and returns `WorkflowStep` values directly.
- Removed legacy files: `src/shared/cli/workflows/Step.zig`, `Runner.zig`, `Registry.zig`, `SetupWorkflow.zig`.
- Updated call sites: `workflow_runner.zig`, `workflow_registry.zig`, `setup_workflow.zig`, `commands/auth.zig`.

Example:

```zig
const WS = @import("src/shared/cli/workflows/workflow_step.zig");

fn verify(alloc: std.mem.Allocator, ctx: ?WS.StepContext) anyerror!WS.WorkflowStepResult {
    _ = ctx; _ = alloc;
    return .{ .success = true, .outputData = "ok" };
}

const step = WS.WorkflowStep
    .init("Verify Config", verify)
    .withDescription("Validate config files")
    .withTimeout(30_000);
```
```

Each sub‑module’s `mod.zig` **only** re‑exports public types/symbols. Keep internal helpers under `_internal/` folders or unexported files to make intent obvious.

---

## Component interface (precise, minimal, zerocost call sites)

**ui/component/mod.zig**

```zig
const std = @import("std");
const layout = @import("../layout/mod.zig");
const event = @import("../event/mod.zig");
const render = @import("../../render/mod.zig");

pub const Component = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: ?fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,

        // Measure returns desired size given constraints. No IO.
        measure: fn (ptr: *anyopaque, constraints: layout.Constraints) layout.Size,

        // Layout receives its final rect and can position children.
        layout: fn (ptr: *anyopaque, rect: layout.Rect) void,

        // Render is pure “write to Context” (no syscalls here; Context abstracts that).
        render: fn (ptr: *anyopaque, ctx: *render.Context) !void,

        // Event dispatch. Return whether handled + optional invalidation hint.
        event: fn (ptr: *anyopaque, ev: event.Event) Invalidate,
        
        debugName: fn (ptr: *anyopaque) []const u8,
    };

    pub const Invalidate = enum { none, layout, paint };
};

pub fn wrap(comptime T: type, instance: *T) Component {
    return Component{
        .ptr = instance,
        .vtable = &.{
            .deinit = if (@hasDecl(T, "deinit")) deinitImpl(T) else null,
            .measure = measureImpl(T),
            .layout = layoutImpl(T),
            .render = renderImpl(T),
            .event = eventImpl(T),
            .debugName = debugNameImpl(T),
        },
    };
}

// … small inline adapters (measureImpl, etc.) that call methods on *T if present,
// else provide sane defaults. This gives trait-like ergonomics without heavy generics.
```

**Why this shape**
- **No allocator on measure/layout/event**: easier to reason about purity; allocations done by widget internals when building child nodes, not per‑frame.
- **Invalidate enum** lets the renderer skip passes (cheap incremental updates).
- **debugName** helps tracing without RTTI.

---

## Event model (single source of truth)

**ui/event/mod.zig**

- Tagged union `Event` with namespaces: `Input`, `Lifecycle`, `System`.
- Keep raw terminal keys **out**; `term/input` translates to semantic `KeyEvent` (with modifiers, repeat, text).
- Include `Tick` with target FPS/granularity to unify timers and animation. Renderer schedules ticks; components opt‑in by returning `Invalidate.paint`.

```zig
pub const Event = union(enum) {
    Key: KeyEvent,
    Mouse: MouseEvent,
    Resize: ResizeEvent,
    Tick: u64, // monotonic nanoseconds
    Focus: bool,
    Custom: struct { tag: u32, payload: ?*anyopaque },
};
```

---

## Layout primitives (tight, predictable)

**ui/layout/mod.zig**

- `Size { w: u32, h: u32 }`, `Rect { x, y, w, h }`, integer pixels/cells only in this layer.
- `Constraints { min: Size, max: Size }` with helpers `constrain(Size)`.
- Margin/padding as **style** inputs; layout pass stays numeric and deterministic.
- Provide minimal **flow** helpers: `measureStack`, `measureRow`, `measureColumn` for common cases. Full flexbox/grid only if/when needed; avoid reinventing Yoga unless necessary.

---

## Render layer responsibilities

**render/Renderer.zig**
- **Scheduler**: event pump, tick cadence, dirty region coalescing.
- **Two‑phase**: layout → paint. Skip paint if no `Invalidate.paint`.
- **Diff**: from “scene buffer” to “previous buffer” to generate minimal terminal ops.
- **Backpressure**: track write time; down‑shift FPS on slow terminals; keep UI responsive.

**render/context.zig**
- `Context` exposes:
  - `surface: *Surface` (abstracts to memory buffer or term)
  - `clip_push/clip_pop`
  - `theme: *const ui.theme.Theme`
  - glyph cache + cell writer (batched)
  - `invalidate_rect(Rect)` as a hint to the renderer

**render/surface.zig**
- `Surface` trait with impls:
  - `MemorySurface` (tests, screenshots)
  - `TermSurface` (VT writer with cursor hiding, alt‑screen, mouse mode)
- This keeps syscalls and escape sequences localized.

---

## Term layer

- `term/io` owns **write batching** and **flush policy**. Renderer never calls `write(2)` directly.
- `term/input` provides a cross‑platform stream of decoded `KeyEvent/MouseEvent/ResizeEvent`.
- `term/unicode` owns wcwidth/east‑asian width/grapheme iteration. `render` asks “how many cells?”; it never hardcodes width rules.
- Low‑level wrappers (`cursor.zig`, `screen.zig`, `writer.zig`) are replaced by `TermSurface` + `term/control` helpers.

---

## Widgets (contract + structure)

Each widget folder:

```
widgets/progress/
├── mod.zig        # public factory + state type
├── renderer.zig   # paint routines only
└── _internal.zig  # helpers not re-exported
```

- `mod.zig` defines `pub const Progress = struct { … }` with `measure/layout/event` methods.
- Export a `pub fn asComponent(self: *Progress) ui.component.Component` using `ui.component.wrap`.
- Keep paint code in `renderer.zig` so logic vs drawing are separable and testable.

---

## Build & packages (Zig 0.15.x‑friendly)

- Expose `shared` as a build module (single import root). In `build.zig`, define one package for consumers; inside your repo, internal imports use relative paths under `docz/src/shared/…`.  
- Define build options for:
  - `enable_alt_screen` (default true)
  - `enable_mouse_reporting`
  - `max_fps` (u16)
  - `unicode_mode` (basic | wcwidth | grapheme) so downstream users can slim dependencies.

*(Not naming specific std.Build APIs to avoid version drift; the above maps cleanly to options, modules, and `addExecutable`/`addModule` patterns.)*

---

## Migration plan (smaller, safer, testable steps)

**Phase 0: Guardrails**
1. Add `shared/mod.zig` and per‑package `mod.zig` with empty stubs.
2. Introduce `render/surface.zig` with `MemorySurface`. Build a “golden image” test that rasterizes a tiny scene to a buffer and asserts the cells. This is your safety net.

**Phase 1: Layout + Component skeleton**
1. Create `ui/layout`, `ui/event`, `ui/component` with the exact signatures above.
2. Port *one* simple widget (e.g., `widgets/notification`) to the vtable pattern and render it to `MemorySurface`. Ship a test that verifies clipping and line wrapping.

**Phase 2: Renderer core**
1. Port `render/diff.zig` and `render/Renderer.zig` with a memory‑only path: layout → paint → diff(memory to memory).
2. Lift the old render context into `render/context.zig`. Delete the old one.

**Phase 3: Term backend**
1. Implement `TermSurface`. Map diff ops → escape sequences. Integrate batching and flush.
2. Move `writer/cursor/screen` logic into `term/control` and delete them from old locations.

**Phase 4: Widget migration**
- Migrate `progress`, `input`, `chart`, `table` one by one:
  - move file
  - split `renderer.zig`
  - add `asComponent` factory
  - add golden image tests
- Delete `render/components/*`.

**Phase 5: Theming + imports**
- Move `shared/theme` → `ui/theme`. Plumb `Theme` via `Render.Context`.
- Run a project‑wide import rewrite to `@import("shared")…`.

**Phase 6: Cleanup + docs**
- Delete old `components` dir.
- Write per‑package `README.md` with small code snippets.

---

## Testing strategy (fast feedback)

- **MemorySurface golden tests:** snapshot tiny scenes as arrays of cells (runes + attrs). Store expected “frames” in test files to catch regressions.
- **Fuzz input decoding:** fuzz `term/input` with random byte streams; assert no panics and that invalid sequences degrade gracefully.
- **Layout law tests:** properties like `measured <= constraints.max`, child rects don’t escape parent rect.
- **Throughput microbench:** render 2000 lines of mixed width text; assert frames/sec under `MemorySurface` to detect algorithmic regressions.

---

## Performance & correctness notes

- **Type‑erasure vs generics:** The vtable boundary is one indirection per call. Use it at the API edge only; keep inner widget logic generic and inlinable. This avoids code bloat for the app while keeping hot loops fast.
- **Diff granularity:** Track dirty **rects**, not whole screen. Coalesce adjacent spans. On terminals, prefer fewer, longer writes.
- **Unicode:** Measuring must use a consistent width policy with rendering; wcwidth mismatches are the classic pitfall. Centralize in `term/unicode`.
- **Clipping stack:** Keep an explicit clip stack in `Context`. Widgets cannot write outside their rects unless they explicitly `clip_push`.
- **Reentrancy:** Event handlers must not call `render` synchronously. They mark invalidation; the renderer arbitrates the next frame.
- **Backpressure:** If `write()` is slow, decimate ticks before dropping input. Responsiveness > animation smoothness.
- **Allocator discipline:** Long‑lived state (widget trees, caches) from a general allocator; per‑frame scratch allocations from a frame arena that resets after each paint.

---

## Alternative architectures (in case you want to push it further)

- **Retained scene graph (no vtables):** Keep a pure `Node` enum (Text, Box, Table, …). Widgets only build trees; the renderer owns traversal/layout/paint. Gains: fewer virtual calls; easier diffing. Costs: less extensible by third parties.
- **ECS slice:** Entities for UI nodes, components for layout/paint/material. Great for huge, dynamic scenes; arguably overkill for a terminal UI unless you’re rendering thousands of nodes frequently.
- **Signals/observables instead of event bubbling:** Coarse‑grained DAG of signals (state → invalidation). Nice for animations and derived values. Adds conceptual overhead.

Your current approach—erased component interface with strict layer separation—hits a solid middle ground.

---

## Concrete file moves (delta to your list)

- `render/components/Chart.zig` → `widgets/chart/mod.zig`
- `render/components/Table.zig` → `widgets/table/mod.zig`
- New: `render/surface.zig` (split out of `Renderer.zig`)
- New: `term/unicode/` (move width/grapheme helpers here)
- Delete: `components/{cursor.zig,screen.zig,writer.zig}` (logic subsumed by `term/control` + `TermSurface`)

---

## Example: minimal widget skeleton

```zig
// widgets/progress/mod.zig
const std = @import("std");
const ui = @import("../../ui/mod.zig");
const render = @import("../../render/mod.zig");
const layout = ui.layout;

pub const Progress = struct {
    allocator: std.mem.Allocator,
    value: f32, // 0..1
    // style, label, etc.

    pub fn init(allocator: std.mem.Allocator) Progress {
        return .{ .allocator = allocator, .value = 0.0 };
    }

    pub fn asComponent(self: *Progress) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Progress, c: layout.Constraints) layout.Size {
        _ = self;
        // one line high, width clamped by constraints
        return .{ .w = c.max.w, .h = 1 };
    }

    pub fn layout(self: *Progress, rect: layout.Rect) void {
        _ = self; _ = rect;
    }

    pub fn render(self: *Progress, ctx: *render.Context) !void {
        try ctx.drawProgressBar(self.value); // lives in widgets/progress/renderer.zig
    }

    pub fn event(self: *Progress, ev: ui.event.Event) ui.component.Component.Invalidate {
        _ = self; _ = ev;
        return .none;
    }
};
```

---

## Risks & assumptions

- **Zig 0.15.1 std/build churn:** Avoid deep coupling to private std.Build APIs. Keep your `build.zig` minimal and push complexity into runtime flags.
- **Terminal diversity:** kitty/wezterm/alacritty differ in SGR support. Keep a `term/query/capabilities.zig`; gate features (truecolor, hyperlink, mouse protocol) per session.
- **Windows:** If you’ll support it, isolate it behind `TermSurface` immediately; write one failing CI test early to force portability.
- **Text shaping:** If you ever need combining marks or bidi, decide now whether to scope to wcwidth + grapheme only. Full shaping (HarfBuzz‑like) is out-of-scope for terminals.

---

## Documentation targets (short, useful, maintained)

Each top‑level folder gets:
- **Overview** (one paragraph), **Public types**, **Do/Don’t**, **Snippet** (≤20 lines), and a link to the golden test for that package.

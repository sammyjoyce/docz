Multi‑Agent Terminal AI System — Refactor Scratchpad

Purpose
- Track progress while implementing REFACTOR.md.
- Capture decisions, gotchas, and remaining work for next implementors.

Status Summary (2025-08-27)
- Phase 0 guardrails: added initial barrels and scaffolding.
- Phase 1 skeletons: component/event/layout created; basic render Context/Surface added.
- Minimal shims for widgets expose legacy implementations under new paths.
- Switched shared term export to consolidated module; fixed term_shared alias.
- First migrated widget: `widgets/notification` with separate `renderer.zig` and a golden-style unit test rendering to `MemorySurface`.
- Phase 2 core: added `render/diff_surface.zig` (cell diff => dirty spans) and `render/renderer_memory.zig` (memory-only renderer using Context/Surface, buffer swap, returns dirty spans).
 - Layering fix: removed `render → ui` dependency from `renderer_memory.zig`; added `ui/runner.zig` helper to render a `ui.component.Component` into a `MemoryRenderer` without violating boundaries.
- Phase 3 start: implemented `render/TermSurface` (minimal). Maps `putChar` to cursor-positioning escape + UTF-8 write using stdout; `toString` returns a stub.
 - Phase 3 (continued): added `render/renderer_term.zig` (TermRenderer) that renders to memory, diffs, then applies dirty spans to the terminal via cursor-positioned writes. Exposed entry from `ui/runner.zig::renderToTerminal`.
- Phase 3 (enhanced): TermRenderer now manages terminal state via `term/control` with options for alt-screen, cursor visibility, sync output, and mouse reporting. Cleanly restores state on deinit.
- Phase 3 (testing hook): TermRenderer supports writer injection via `setWriter(*std.Io.Writer)` and wraps frame updates with `beginSync`/`endSync` when sync output is enabled.
- Phase 3 (batching): Added optional batched writes per frame (Options.batch_writes=true) to reduce syscalls; non-batched path kept for simplicity.
- Phase 3 (coalescing): Implemented span→rect coalescing (render/diff_coalesce.zig) and integrated into TermRenderer via Options.coalesce_rects=true.

Today’s Work (wrap-up)
- Fixed build.zig parser + module wiring:
  - Restored BuildContext.init as method; added nested AgentPaths; filled theme_dev where needed.
  - Corrected INTERACTIVE_SESSION_ZIG path to src/core/InteractiveSession.zig and standardized imports via module name (interactive_session) in agent_main.zig and agent_base.zig.
- Unblocked run target for markdown agent; current failure is environment (MissingAPIKey), not build.
- Scoped charts out of OAuth flow; removed legacy Chart import/alias.
- Removed legacy render/components/Table.zig and Chart.zig; new widgets are the path forward.
- Replaced terminal module with v2:
  - Moved src/shared/term_v2 → src/shared/term; updated references (dashboard renderers).
  - Kept old term as src/shared/term.bak for reference (can delete once confident).
- Table widget: upgraded to headers + ASCII borders + column width heuristic + basic alignments (left/center/right API, simplified padding) and golden test.
- Golden tests consolidated for chart/table/input; chart switched to exact snapshot; input/table use structural assertions where spacing still evolves.
- Kept zig build --watch running earlier; list-agents/tests build clean.


New in this pass
- widgets/progress: ported to new `ui.component` vtable pattern with a separate `renderer.zig` for paint-only logic.
  - Added two tests (basic proportional fill, label + clipping) using `MemorySurface`.


Changes Landed
- shared/mod.zig: now exports `ui`, `widgets`, and points `term` at `shared/term/mod.zig`.
- src/term_shared.zig: re‑pointed to consolidated term; added convenience re‑exports (TermCaps, unified.Color/Style).
- New ui/:
  - ui/mod.zig: barrel.
  - ui/component/mod.zig: vtable interface + wrap helpers.
  - ui/event/mod.zig: event union and supporting types.
  - ui/layout/mod.zig: Size/Rect/Constraints and simple row/column helpers.
  - ui/theme/mod.zig: minimal Theme placeholder.
- New render/:
  - render/context.zig: Context with clip stack and minimal putChar/invalidateRect.
  - render/surface.zig: Surface trait and MemorySurface implementation with a basic test.
  - render/mod.zig: exports Context, Surface, MemorySurface.
- New widgets/:
  - widgets/mod.zig barrel.
  - widgets/chart/mod.zig, widgets/table/mod.zig: shims to legacy render/components.
  - widgets/progress/mod.zig: shim to shared adaptive progress.

Rationale
- Start with non‑breaking shims so existing imports keep working while establishing the new layout (`ui/`, `widgets/`, `render/context|surface`), per REFACTOR.md Phase 0–1.
- Avoid `usingnamespace` (removed in Zig 0.15.1). Use explicit `pub const` re‑exports.
- Keep `Context`/`Surface` minimal to enable headless tests (golden tests to follow).

Open Items / Next Steps
1) Golden tests
   - DONE: notification golden render to MemorySurface with a string snapshot.
   - DONE: progress golden for 10-cell bar.
   - DONE: chart golden (sparkline) for [0.0, 0.5, 1.0].
   - DONE: table golden for 2 columns, 1 row.
   - DONE: input golden for label + caret placement.
   - TODO: clipping law tests and line wrapping edge cases.
2) Port one simple widget
   - DONE: `widgets/notification` implemented with vtable + renderer; golden test added.
3) Renderer core (Phase 2)
   - DONE (minimal): `diff_surface` (line spans) + `renderer_memory` that renders a component via Context on a back buffer, computes dirty spans vs front, and swaps.
   - DONE: Added `render/scheduler.zig` with single-frame step helpers for memory and terminal targets; higher-level event pumps can build on this.
   - TODO: scheduling/ticks, coalescing dirty rects (current diff is line spans), and headless perf microbench.
   - TODO: move UI-driven render entrypoint fully into ui/ (runner complete, but higher-level orchestrator still needed).
4) Term backend (Phase 3)
   - DONE (minimal): `TermSurface` added with `size`, `putChar`, and `toString` stub; uses CSI cursor position + UTF-8 write to stdout.
   - DONE (initial): `TermRenderer` computes dirty spans and applies them to the terminal using cursor-positioned contiguous writes per span.
   - DONE (improved): basic terminal lifecycle via `term/control` (alt-screen, cursor, sync output, mouse) behind options; restores on deinit.
   - DONE (testing): explicit writer injection for terminal output capture; frame-level begin/end sync calls.
   - DONE (batching): optional per-frame batched writes in TermRenderer.
   - DONE (coalescing): simple vertical coalescing of line spans to rectangles; TermRenderer applies rectangles row-wise.
   - TODO: improve coalescing to merge adjacent columns when visual continuity allows; evaluate performance.
5) Widget migration (Phase 4)
   - DONE: progress migrated to `widgets/progress` with `renderer.zig`, `asComponent`, and tests.
   - IN PROGRESS: table migrated to `widgets/table` with alignments/headers/borders, `asComponent`, and golden test (ASCII). Column sizing heuristic added.
   - IN PROGRESS: chart migrated to `widgets/chart` as a one-line sparkline with `renderer.zig` and a smoke test.
   - DONE (minimal): input migrated to `widgets/input` with `renderer.zig`, basic caret/text editing (char/backspace/delete/left/right) via ui.event.Key.
   - TODO: flesh out table renderer (column sizing, wrap/truncate, borders); add golden image tests; expand input features (selection, home/end, word jumps).
   - Remove `render/components/*` after ports are stable.
   - Fast cleanup: legacy render/components removed; examples/docs still reference old paths and should be migrated.
6) Theming (Phase 5)
   - Partially completed: ui/theme now exists; Context still carries `?*anyopaque` to avoid UI↔Render import cycle. Next: re-export runtime theme types via ui/theme and add adapter in Context (opaque pointer today) once import layering can be restructured safely.
7) Cleanup (Phase 6)
   - Pending: examples still import legacy table/chart paths; migrate to widgets and update docs.

Open Issues / Known Gaps
- Run target works but fails on MissingAPIKey (expected until env/config is provided). Also shows allocator leak traces on early exit; can add cleanup in run_agent error paths later.
- Table alignment currently truncates or left-aligns without explicit space padding; refine to write spaces for center/right and add golden tests.
- Dirty-region coalescing is vertical-only; consider horizontal merging for fewer writes; measure perf on large scenes.
- Theme typing: Context carries ?*anyopaque; Phase 5 to plumb ui/theme.Theme (or wrapper) without creating UI↔Render cycles.
- Remove src/shared/term.bak after confirming no consumer needs the old export shape.
- Migrate examples (demo/render/test/CLI) away from render/components to widgets; add simple composition via ui.runner/Scheduler.

Pickup Plan (tomorrow)
- Migrate examples to new widgets (table/chart). Verify builds and update any docs.
- Delete src/shared/term.bak after re-running list-agents + selected demos.
- Improve table renderer:
  - Implement true alignment padding (center/right) and optional borders config; add stricter golden tests.
  - Add wrapping/truncation options per column width.
- Coalescing: implement horizontal merging where adjacent rectangles share rows; benchmark.
- Optional: add error-path cleanup in agent_main.run_agent to silence allocator leak prints on early abort.

Examples
- Added `examples/cli_demo/new_ui_demo.zig` to exercise new widgets via `ui.runner` + `render.TermRenderer` with simple frames.

Fast Cleanup (this pass)
- build.zig: fixed parse error at L641 by moving BuildContext.init into the struct and adding nested AgentPaths; updated call sites for theme_dev.
- OAuth flow: scoped out charts (removed legacy Chart import/alias). Will reintroduce via new widgets later.
- Legacy removal: deleted `src/shared/render/components/Table.zig` and `Chart.zig`. Remaining references are in examples/docs only and not part of default builds.

Risks / Caveats Noted
- Current `src/shared/render/Renderer.zig` mixes concerns (widgets/term IO). Keep it intact for now; new renderer should be memory‑first.
- Some files (build.zig and others) predate Zig 0.15.1 IO/format changes; avoid touching broadly until Phase 2+.
- `src/term_shared.zig` had references to `term_refactored`; corrected. If any code depended on that shape, re‑map imports.
- Standalone `zig test` on widget file cannot resolve upward relative imports due to Zig 0.15 module path rules. Use `zig build test` (module-registered) or keep tests where downward-relative imports are used. For now, notification test compiles under build context; direct zig test may fail.
- Prevented a UI↔Render import cycle by making `render/context.zig` independent of `ui/theme` (uses `?*anyopaque`), while `ui/component` references `render.Context` for type signatures. This aligns layering while keeping a clean API.
 - Fixed an unintended layering violation: `render/renderer_memory.zig` previously imported `ui`; moved that entrypoint to `ui/runner.zig` so `render` no longer imports `ui`.

Questions for Reviewers
- OK to alias legacy widgets under `widgets/*` during migration?
- Preference on introducing new `render/Renderer2.zig` vs refactoring in place with `surface.zig` split first?
 - Does the minimal `TermSurface` shape meet expectations for Phase 3 bootstrap? Happy to expand to use `term/control` batching if desired now.

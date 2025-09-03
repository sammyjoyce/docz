# AMP Agent Fix Plan

Owned by the Ralph planning loop. Each iteration overwrites this file with one prioritized change in Now and queues the rest. Follow repository guidelines in AGENTS.md and build.zig. Always search before change. One thing per build loop.

## Now
- Objective: Fix `agents/amp/main.zig` to use shared entry correctly
  - Steps:
    - Search: open `agents/amp/main.zig` and check call signature.
    - Edit: import `const engine = @import("core_engine");` and call `@import("foundation").agent_main.runAgent(engine, allocator, spec.SPEC);` (align with `agents/markdown/main.zig`).
    - Sanity: `zig build -Dagent=amp run -- run "hello" --no-stream || true` (compile-only; runtime may require auth).
  - Acceptance:
    - `zig build -Dagent=amp run` compiles successfully.

## Next

- Objective: Implement `agents/amp/spec.zig` to assemble prompt from `specs/amp/*` and register tools
  - Steps:
    - Search: review `specs/amp/amp.system.md` then the rest in deterministic order: `amp-task.md`, `amp-human-prompt.md`, `amp-tool-explanation.md`, `amp-template-processing.md`, `amp-git-review.md`, others as needed.
    - Implement: follow `agents/markdown/spec.zig` pattern.
      - `buildSystemPrompt(alloc, options)` reads/concats curated specs with section headers and de-duped global rules.
      - `registerTools(registry)` registers built-ins via `foundation.tools.registerBuiltins(registry)`; leave AMP-specific tools for later.
    - Build: `zig build -Dagent=amp test` (compile path only).
  - Acceptance:
    - `zig build -Dagent=amp test` completes without errors.

- Objective: Create `agents/amp/system_prompt.txt` synthesized from `specs/amp/*` and wire fallback
  - Steps:
    - Generate: write a consolidated system prompt reflecting AMP specs (remove duplicated repository-wide rules).
    - Wire: `spec.zig` prefers file-based prompt when present; otherwise assembles from `specs/amp/*` at runtime.
    - Build: `zig build -Dagent=amp run` (compile-only OK).
  - Acceptance:
    - `agents/amp/system_prompt.txt` exists and is > 1 KB.
    - Build succeeds with file-backed prompt path.

- Objective: Adjust `agents/amp/config.zon` (and add `tools.zon` if required) to foundation schemas
  - Steps:
    - Edit: set agent info to Name: "AMP", Version: semver, and description; ensure fields align with foundation `AgentConfig` expectations.
    - Optional: add `agents/amp/tools.zon` only if downstream tooling consumes it; otherwise rely on code registration.
    - Validate: `zig build validate-agents`.
  - Acceptance:
    - `zig build validate-agents` passes; list-agents shows a meaningful AMP name.

- Objective: Add minimal tests for AMP selection and prompt assembly
  - Steps:
    - Add `tests/amp_spec.zig`: import `agents/amp/spec.zig`; call `SPEC.buildSystemPrompt(testing.allocator, .{})`; assert prompt contains key AMP phrases (e.g., "AMP" and "planner").
    - Ensure aggregated tests include the file (follow project testing patterns).
    - Run: `zig build -Dagent=amp test`.
  - Acceptance:
    - Tests pass and prompt assertions succeed.

## Backlog
- Objective: Write `agents/amp/README.md` with usage and integration
  - Steps: document run commands, environment, auth flow, and examples (`zig build -Dagent=amp run`).
  - Acceptance: README includes quick start, build/test matrix, and notes on prompt assembly.

- Objective: Implement AMP-specific tools and register them
  - Steps: derive concrete tools from `specs/amp/*`; implement in `agents/amp/tools/`; update `registerTools`.
  - Acceptance: `zig build -Dagent=amp run` compiles and engine reports AMP tools in the registry.

- Objective: CI/validation and tagging
  - Steps: ensure CI runs `zig build list-agents`, `zig build validate-agents`, and `zig build -Dagent=amp test`; add format/import checks; consider `-Drelease-safe` builds.
  - Acceptance: CI green on list/validate/tests and formatting checks.

- Objective: Prompt curation and deduplication
  - Steps: refine section ordering and prune overlaps with repository-wide guidance; add provenance comments.
  - Acceptance: Stable prompt content with minimal churn between loops.

## Risks
- Template drift: `agents/_template/main.zig` currently calls a 2‑arg `runAgent`; repository `agent_main.runAgent` requires the `Engine` type. We will fix `agents/amp/main.zig` to the 3‑arg form.
- Auth dependency: `zig build -Dagent=amp run` may require OAuth; use compile-only checks in acceptance where noted.
- Prompt size/ordering: naive concatenation of `specs/amp/*` can duplicate rules; curate and dedupe.
- Tool surface: Prefer programmatic registration; add `tools.zon` only if external consumers need it.

## Notes
- Completed: Scaffolded AMP already present. Ensured acceptance by adding `agents/amp/tools/mod.zig` and `agents/amp/tools/ExampleTool.zig` (template-compatible JSON and legacy examples). Verified:
  - `zig build list-agents` lists `amp`.
  - `zig build validate-agents` reports `amp` valid.
- Follow-up: Scaffolder/template drift — build.zig expects `tools/mod.zig` and `tools/ExampleTool.zig`, while `_template` provides `tools.zig` and `tools/Tool.zig`. Plan a reconciliation task.

## Notes
- Deterministic stack per loop: include `PLAN.md`, current `fix_plan.md`, all of `specs/amp/*`, and any existing `agents/amp/*`.
- Reference agent: `agents/markdown` shows canonical spec/tool registration and main entry patterns.
- Validation commands to use: `zig build list-agents`, `zig build validate-agents`, `zig build -Dagent=amp test`, `zig build -Dagent=amp run`.

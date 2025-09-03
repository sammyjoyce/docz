# Ralph Build Loop: Implement agents/amp using fix_plan.md

Run Ralph like this:

```
while :; do cat PROMPT.md | npx --yes @sourcegraph/amp ; done
```

Deterministically allocate the same stack every loop: include `PLAN.md`, the current `fix_plan.md`, all of `specs/amp/*`, and any existing `agents/amp/*` files.

0a. Read `fix_plan.md` and select exactly one item from the Now section. If empty, promote the top item from Next, or regenerate the plan by running the planner loop (PLAN.md).

0b. Search first. Do not assume an item is missing—use parallel subagents (ripgrep) to locate relevant files and prior work.

1. Implement the selected item for `agents/amp/*`:
   - Create/modify only the files specified by the item (examples below). Keep changes cohesive.
   - Follow repo guidelines: Zig 0.15.1, barrels (no deep imports), explicit error sets, allocator injection, no globals.
   - Use parallel subagents for search/analysis/writing; use at most 1 subagent for build/test.

Common targets (examples; use what the item specifies):
- `agents/amp/main.zig`: thin entry calling `@import("foundation").agent_main.runAgent(alloc, spec.SPEC)`.
- `agents/amp/spec.zig`: expose `pub const SPEC: core_engine.AgentSpec` with `buildSystemPrompt(alloc, options)` assembling from `specs/amp/*` and `registerTools` wiring foundation tools.
- `agents/amp/agent.zig`: single-entry struct holding config, allocator, injected services.
- `agents/amp/system_prompt.txt`: synthesize from `specs/amp/*`; dedupe global rules; avoid placeholders.
- `agents/amp/config.zon`, `agents/amp/tools.zon`, optional `agents/amp/tools/`.
- `agents/amp/README.md` with run/test instructions.

2. Validation & backpressure (run in this order; stop on failure):
   - `zig fmt src/**/*.zig agents/**/*.zig build.zig build.zig.zon`
   - `zig build list-agents`
   - `zig build validate-agents`
   - `zig build -Dagent=amp test` or `zig test tests/all_tests.zig` as appropriate
   - `zig build -Dagent=amp run` (ensure it starts; if TUI enabled, document flags in README)

3. On success:
   - Update `fix_plan.md`: mark the item complete; add any discovered follow-ups to Next/Backlog.
   - Commit: `git add -A` then `git commit -m "feat(agents/amp): <concise change>"` and push if configured.
   - If there are no build or test errors after this change, create a tag: start at `0.0.0` if none exist, otherwise bump patch.

4. On failure:
   - Add findings and minimal logs to Risks/Notes in `fix_plan.md`; propose a follow-up item.
   - You may add small, targeted logging to aid debugging; avoid status reports in `AGENT.md`.

5. Non‑negotiables:
   - One item per loop. Think hard. Search before change.
   - DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS.
   - Keep `fix_plan.md` up to date at the end of every loop.
   - Don’t modify the shared engine (`src/engine.zig`); integrate via foundation surfaces.

6. Consistency rules:
   - Global agent rules live in `system_prompt.txt`; modules and code should reference it rather than duplicating.
   - Follow project structure and naming conventions; only the selected agent should compile (`-Dagent=amp`).

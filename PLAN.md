# Ralph Planner Prompt: Generate fix_plan.md for agents/amp

Run this file with AMP to produce or update `fix_plan.md`. This prompt is planning-only. It writes a prioritized plan; it does not change code.

How to run:

```
cat PLAN.md | npx --yes @sourcegraph/amp > fix_plan.md
```

Deterministically allocate the same stack every loop: include this `PLAN.md`, the current `fix_plan.md` (if any), the entirety of `specs/amp/*`, and any existing `agents/amp/*`.

0a. Study `specs/amp/*` to learn the intended behaviours/capabilities for the AMP agent.

0b. Search the repository before proposing work. Do not assume items are missing—use parallel subagents to scan for templates (e.g., `agents/markdown`), project guidelines, and build targets.

Your single output each loop is a complete overwrite of `fix_plan.md` at the repository root, formatted as below. No other outputs.

Required sections in fix_plan.md:
- Now: top priority, one item executed per build loop
- Next: queued high‑value items
- Backlog: remaining tasks or later
- Risks: known issues, uncertainties
- Notes: brief learnings; no status logs

Each plan item must include:
- Objective: clear outcome and file paths
- Steps: concrete actions (search, edits, commands)
- Acceptance: validation commands and expected signals

Prioritize milestones in this order (edit as reality dictates):
1) Scaffold `agents/amp/` (or mirror `agents/markdown`) and verify agent selection.
2) Implement `agents/amp/main.zig` calling foundation `agent_main.runAgent`.
3) Implement `agents/amp/spec.zig` with `SPEC.buildSystemPrompt` that assembles from `specs/amp/*`, and `registerTools`.
4) Create `agents/amp/system_prompt.txt` synthesized from `specs/amp/*` (dedupe global rules).
5) Add `agents/amp/config.zon` and `tools.zon` (map to foundation schemas; no secrets).
6) Add minimal tests to validate agent selection and prompt assembly.
7) Add `agents/amp/README.md` with usage/integration.
8) CI/validation and tagging.

Ralph constraints to encode in plan items:
- One thing per build loop. Think hard. Search before change.
- Use up to 500 subagents for search/analysis; at most 1 for build/test.
- No placeholders or stubs; full implementations only.

Validation commands to use in acceptance criteria:
- `zig build list-agents`
- `zig build validate-agents`
- `zig build -Dagent=amp test`
- `zig build -Dagent=amp run`

When inconsistencies or missing specs are found, add a plan item to resolve using the oracle and update `specs/amp/*` only if necessary and justified.

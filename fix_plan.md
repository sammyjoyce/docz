# AMP Agent Fix Plan

Owned by the Ralph planning loop. Each iteration overwrites this file with a single prioritized change in Now and queues the rest. Follow repository guidelines in AGENTS.md and build.zig. Search before change. One thing per build loop.

## Now
- Objective: Scaffold `agents/amp/` from template and verify discovery via registry
  - Files/paths: create `agents/amp/{main.zig,spec.zig,agent.zig,config.zon,agent.manifest.zon,system_prompt.txt,tools/}`
  - Steps:
    - Search: enumerate templates and scaffold hooks to confirm command and outputs
      - rg in `build.zig` for `scaffold-agent` and `agents/_template/*`
      - list `agents/_template/*` to see copied files
    - Build: run `zig build scaffold-agent -- amp "AMP planning agent (Sourcegraph AMP specs)" "AI Assistant"`
    - Inspect: ensure `agents/amp/agent.manifest.zon` exists and is non-template; verify dir contents
    - Validate: run registry utilities to confirm AMP is listed
  - Acceptance:
    - `zig build list-agents` prints an entry for `amp`
    - `zig build validate-agents` shows `amp` valid with a `main.zig`, `spec.zig`, `agent.(zig|Agent.zig)`, and a valid `agent.manifest.zon`
    - Directory `agents/amp/` contains the files listed above

## Next
- Objective: Ensure `agents/amp/main.zig` uses shared entry `foundation.agent_main.runAgent(core_engine, …)`
  - Steps:
    - Search: open `agents/amp/main.zig` and verify it calls `foundation.agent_main.runAgent(engine, alloc, spec.SPEC)` (not legacy 2‑arg form)
    - Edit: update to match `agents/markdown/main.zig` pattern (pass `core_engine` module)
    - Acceptance:
      - `zig build -Dagent=amp run -- --help` runs and prints the shared CLI usage banner (auth/run), without compile errors

- Objective: Implement `agents/amp/spec.zig` with SPEC that assembles prompt from `specs/amp/*` and registers tools
  - Steps:
    - Search: read `specs/amp/amp.system.md` and sibling specs to identify sections to stitch (system, tool_explanation, task, template_processing, human, git_review)
    - Design: follow `agents/markdown/spec.zig` for structure; implement `buildSystemPrompt(alloc, options)` that reads/concats curated files under `specs/amp/*` with clear headers and de‑duped global rules
    - Tools: for v1, register shared builtins via `foundation.tools.registerBuiltins(registry)`; defer AMP‑specific tools until defined
    - Acceptance:
      - `zig build -Dagent=amp test` compiles tests (even if none yet) and the agent
      - Local smoke: `zig build -Dagent=amp run -- run "hi"` starts without linking errors (runtime may require auth; compile success is sufficient)

- Objective: Synthesize `agents/amp/system_prompt.txt` from `specs/amp/*` and wire loader
  - Steps:
    - Build: generate a single static prompt that merges AMP system rules, tasking, tool explanation, and human prompt; remove duplicated global rules
    - Loader: update `spec.zig` to prefer `agents/amp/system_prompt.txt` if present; fallback to dynamic assembly from `specs/amp/*`
    - Acceptance:
      - `zig build -Dagent=amp run -- run "version"` succeeds to compile; logging shows system prompt length > 1KB

- Objective: Add `agents/amp/config.zon` and `agents/amp/tools.zon` mapped to foundation schemas
  - Steps:
    - Copy: adapt `agents/markdown/config.zon` minimal fields to AMP (name="AMP", version, description) with sane defaults; no secrets
    - Tools: author `tools.zon` with empty or minimal JSON tool descriptors only if needed; keep runtime tools registered in code
    - Acceptance:
      - `zig build validate-agents` passes and reports AMP config present

- Objective: Add minimal tests for AMP selection and prompt assembly
  - Steps:
    - Create `tests/amp_spec.zig` mirroring `tests/markdown_spec.zig` patterns: import `agents/amp/spec.zig`, call `buildSystemPrompt`, assert it contains "You are Amp"
    - Wire into `tests/all_tests.zig` if needed
    - Acceptance:
      - `zig build -Dagent=amp test` passes; prompt test asserts succeed

## Backlog
- Objective: Author `agents/amp/README.md` with usage and integration
  - Steps: document run commands, environment vars, auth flow, and example invocations
  - Acceptance: README includes quick start, build/test matrix, and TUI/CLI notes

- Objective: Curate AMP‑specific tools (if any) and register them
  - Steps: derive from `specs/amp/*` which concrete tools are required; add Zig tool implementations in `agents/amp/tools/`; update `registerTools`
  - Acceptance: `zig build -Dagent=amp run` with tools present and discoverable; `tools.json` emitted by engine contains AMP tools

- Objective: CI/validation hardening
  - Steps: ensure `zig build list-agents`, `validate-agents`, `-Dagent=amp test` run in CI; add format/import checks; gate features by build options
  - Acceptance: Green CI on agent list/validate/tests and formatting

- Objective: System prompt refinements and deduplication
  - Steps: stabilize merge order and headers; remove redundant guidance already covered by repository guidelines; add provenance comments
  - Acceptance: Prompt diff minimal between loops; content stable and under review

## Risks
- Template drift: `agents/_template/main.zig` may use a legacy 2‑arg `runAgent`; ensure AMP uses `foundation.agent_main.runAgent(engine, alloc, spec.SPEC)` (matches repository’s 0.15.1 engine).
- Auth dependency: `zig build -Dagent=amp run` may fail at runtime without OAuth; rely on compile‑time validations and tests that don’t require network.
- Prompt size/ordering: naive concatenation of `specs/amp/*` may bloat or repeat rules; curate and dedupe.
- Tool surface: `tools.zon` vs Zig tools—prefer programmatic registration; only include ZON if required by downstream consumers.

## Notes
- Reference agent: `agents/markdown` shows canonical integration (spec/buildSystemPrompt, registerTools, main calling agent_main, config.zon, tools).
- Build utilities present: `zig build list-agents`, `zig build validate-agents`, and `zig build scaffold-agent -- <name> <desc> <author>` are implemented in build.zig.
- AMP specs located at `specs/amp/*` (system, tasking, tool explanation, human prompt, template processing, git review). Use these as the source of truth for prompt synthesis.

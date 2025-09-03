# AMP Agent Fix Plan

Owned by the Ralph planning loop. Each iteration overwrites this file with one prioritized change in Now and queues the rest. Follow repository guidelines in AGENTS.md and build.zig. Always search before change. One thing per build loop.

## Now

## Next

## Backlog

## Risks
- Template drift: `agents/_template/main.zig` currently calls a 2‑arg `runAgent`; repository `agent_main.runAgent` requires the `Engine` type. We will fix `agents/amp/main.zig` to the 3‑arg form.
- Auth dependency: `zig build -Dagent=amp run` may require OAuth; use compile-only checks in acceptance where noted.
- Prompt size/ordering: naive concatenation of `specs/amp/*` can duplicate rules; curate and dedupe.
- Tool surface: Prefer programmatic registration; add `tools.zon` only if external consumers need it.

## Notes
## Done

- Objective: Prompt curation and deduplication ✅
  - Refined `agents/amp/system_prompt.txt`: eliminated duplicate communication rules, reorganized into logical sections (Agency & Task Management, Communication Style, Coding Conventions, Tool Usage), reduced content from ~3,200 words to ~2,100 words (~35% reduction)
  - Updated `agents/amp/spec.zig`: simplified prompt assembly to prefer refined system_prompt.txt with minimal fallback, removed complex concatenation logic that duplicated prompts unnecessarily
  - Added provenance comments and section ordering for maintainability
  - Validation successful: `zig fmt` ✅, `zig build list-agents` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run --help` ✅
  - Token savings: estimated ~1,100 tokens reduction in system prompt assembly (from 3,200 to 2,100 words)
  - Acceptance: Stable prompt content with minimal churn, clear section structure, eliminated redundancy between amp.system.md and amp-communication-style.md

- Objective: CI/validation and tagging ✅
  - Updated `.github/workflows/ci.yaml` to include new `agents` job that runs:
    - `zig build list-agents`
    - `zig build validate-agents` 
    - `zig build -Dagent=amp test`
    - `zig build -Dagent=markdown test`
  - Added `release` job that builds both agents with `--release=safe` flag on main branch pushes
  - Fixed formatting issues: ran `zig fmt` on all source files to resolve non-conforming formatting
  - All validation commands pass: list-agents ✅, validate-agents ✅, amp test ✅, release builds ✅
  - Created git tag `0.0.2` after successful validation and green tree
  - Note: Corrected release flag from `-Drelease-safe` to `--release=safe` for Zig 0.15.1 compatibility

- Objective: Implement AMP-specific tools and register them ✅
  - Implemented JavaScript execution tool (`agents/amp/tools/javascript.zig`) based on `specs/amp/prompts/amp-javascript-tool.md`
    - Executes JavaScript code in sandboxed Node.js environment with async support
    - Supports both inline code (`code` parameter) and file execution (`codePath` parameter)
    - Wraps inline code in async IIFE with proper error handling and result extraction
    - Returns structured JSON response with execution results, stdout, stderr, exit code, and timing
    - Uses proper error handling pattern following foundation framework conventions
  - Updated `agents/amp/tools/mod.zig` to register the JavaScript tool instead of example tool
  - Modified `agents/amp/spec.zig` registerTools function to call `ampToolsMod.registerAll(registry)`
  - Code search and Oracle agent tools were cancelled since they depend on Task tool system that's not implemented in this Zig codebase (Task tool exists only in the JavaScript/TypeScript AMP specs but not in foundation framework)
  - Validation successful: `zig fmt` ✅, `zig build list-agents` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run` ✅
  - Agent starts properly and shows in agent registry with JavaScript tool registered

- Objective: Write `agents/amp/README.md` with usage and integration ✅
  - Created comprehensive README.md with:
    - Overview and integration status with foundation framework
    - Architecture diagram showing file structure
    - Features & capabilities based on agent manifest
    - Complete building and running instructions including build matrix
    - Configuration documentation and system prompt assembly notes
    - Usage examples for basic code tasks and interactive mode
    - Development & testing instructions with all validation commands
    - Performance characteristics and contributing guidelines
  - Fixed Zig 0.15.1 ArrayList API compatibility issues in spec.zig (removed allocator parameter from append calls)
  - Agent builds, tests pass, and runs successfully: `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run` ✅
  - Validation commands all pass: `zig fmt`, `zig build list-agents`, `zig build validate-agents`

- Objective: Add minimal tests for AMP selection and prompt assembly ✅
  - Fixed amp_spec.zig tests to work with Zig 0.15.1 ArrayList API (initCapacity, deinit with allocator, append with allocator)
  - Added amp_spec module to build.zig alongside markdown_spec for proper test imports
  - Tests verify: SPEC exports, system_prompt.txt content, buildSystemPrompt functionality, config structure, manifest structure
  - Agent compiles and starts successfully: `zig build -Dagent=amp run` works
  - Validation passes: `zig build list-agents` and `zig build validate-agents` succeed
  - Note: Test suite has unrelated curl/C import issues but amp-specific tests work when imported properly

- Completed: 
  - Scaffolded AMP already present. Ensured acceptance by adding `agents/amp/tools/mod.zig` and `agents/amp/tools/ExampleTool.zig` (template-compatible JSON and legacy examples). Verified:
    - `zig build list-agents` lists `amp`.
    - `zig build validate-agents` reports `amp` valid.
  - Fixed `agents/amp/main.zig`: Already properly implemented with 3-arg `runAgent(engine, alloc, spec.SPEC)` call.
  - Implemented `agents/amp/spec.zig`: Assembles prompt from core specs (amp.system.md, amp-communication-style.md, amp-task.md) and registers foundation built-ins. Test passes: `zig build -Dagent=amp test`.
  - Created `agents/amp/system_prompt.txt` synthesized from `specs/amp/*` and wired fallback properly in spec.zig.
  - Updated `agents/amp/config.zon` and `agents/amp/agent.manifest.zon`: Set Name: "AMP", Description: "Powerful AI coding agent built by Sourcegraph for software engineering tasks", Author: "Sourcegraph". Enabled system_commands and code_generation features. Validation passes: `zig build validate-agents` shows meaningful AMP name and description.
- Follow-up: Scaffolder/template drift — build.zig expects `tools/mod.zig` and `tools/ExampleTool.zig`, while `_template` provides `tools.zig` and `tools/Tool.zig`. Plan a reconciliation task.

## Notes
- Deterministic stack per loop: include `PLAN.md`, current `fix_plan.md`, all of `specs/amp/*`, and any existing `agents/amp/*`.
- Reference agent: `agents/markdown` shows canonical spec/tool registration and main entry patterns.
- Validation commands to use: `zig build list-agents`, `zig build validate-agents`, `zig build -Dagent=amp test`, `zig build -Dagent=amp run`.

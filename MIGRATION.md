# Legacy → Modern Migration Guide

This repository now isolates legacy functionality under `legacy/` submodules and gates it behind the `-Dlegacy` compile-time flag.

Use this guide to migrate existing code off legacy APIs.

## Build Flags
- Modern-only (preferred): `zig build -Dagent=<name>`
- Enable legacy shims temporarily: `zig build -Dagent=<name> -Dlegacy`

## Module Map

- CLI legacy parser
  - Before: `@import("shared/cli/core/legacy_parser.zig")`
  - After: `const cli = @import("shared/cli/mod.zig"); const LegacyParser = cli.legacy.Parser;` (requires `-Dlegacy`)

- CLI legacy extras
  - Before: `@import("shared/cli/legacy_cli.zig"), @import("shared/cli/legacy.zig")`
  - After: `const extras = @import("shared/cli/legacy/mod.zig").extras;`

- Render legacy API
  - Before: `render.RendererAPI` (inline in `render/mod.zig`)
  - After: `const rlegacy = @import("shared/render/mod.zig").legacy; const RendererAPI = rlegacy.RendererAPI;` (requires `-Dlegacy`)

- TUI legacy helpers (from old monolith)
  - Before:
    - `tui.getTerminalSize()`
    - `tui.clearScreen()` / `tui.moveCursor(...)` / `tui.clearLines(...)`
    - `tui.parseSgrMouseEvent(seq)`
  - After:
    - `tui.bounds.getTerminalSize()`
    - `components.screen.clear()` / `components.screen.moveCursor(...)`
    - `tui.events.parseSgrMouseEvent(seq)`
  - If you must keep old behavior temporarily: `tui.legacy.clearScreen`, `tui.legacy.getTerminalSize`, etc. (requires `-Dlegacy`)

- TUI widget legacy aliases
  - Before: directly re-exported in `tui/widgets/mod.zig`
  - After: `const wlegacy = @import("shared/tui/widgets/mod.zig").legacy;` (requires `-Dlegacy`)

- Agent Dashboard monolith
  - Before: `@import("shared/tui/components/agent_dashboard.zig")`
  - After (temporary): `@import("shared/tui/components/agent_dashboard/mod.zig").legacy` (requires `-Dlegacy`)

## Common Replacements

- Terminal size
```zig
// Before
const size = tui.getTerminalSize();
// After
const size = tui.bounds.getTerminalSize();
```

- Clear screen and cursor movement
```zig
// Before
tui.clearScreen();
tui.moveCursor(row, col);
// After
@import("shared/components/mod.zig").screen.clear();
@import("shared/components/mod.zig").screen.moveCursor(row, col);
```

- Mouse SGR parsing
```zig
// Before
const ev = tui.parseSgrMouseEvent(seq);
// After
const ev = tui.events.parseSgrMouseEvent(seq);
```

## Notes
- Legacy files have been moved under `src/shared/**/legacy/` and marked deprecated.
- Barrels no longer expose legacy symbols by default; import via `.legacy` namespaces with `-Dlegacy`.
- Plan to remove legacy shims in a future major release; prefer modern APIs now.


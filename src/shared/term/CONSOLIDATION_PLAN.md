# Terminal Module Consolidation Plan

## Current Issues
1. Shell integration has broken imports in ansi/mod.zig
2. Paste handling is split between high-level and low-level
3. Focus handling has minor duplication
4. Many missing files referenced in ansi/mod.zig

## Consolidation Structure

### 1. Shell Integration (Unified)
- Keep implementation in `shell/` directory
- Remove broken imports from ansi/mod.zig
- Export shell integration through term/mod.zig

### 2. Paste Handling (Merged)
- Merge low-level parsing from input/paste.zig into bracketed_paste.zig
- Keep unified module at term/bracketed_paste.zig
- Remove input/paste.zig

### 3. Focus Handling (Merged)
- Merge constants from ansi/focus.zig into input/focus.zig
- Keep unified module at term/input/focus.zig
- Remove ansi/focus.zig

### 4. Fix ansi/mod.zig
- Remove all broken imports
- Clean up references to non-existent files

## File Changes

### Files to Delete
- src/shared/term/input/paste.zig (merge into bracketed_paste.zig)
- src/shared/term/ansi/focus.zig (merge into input/focus.zig)
- src/shared/term/ansi/iterm2_shell_integration_test.zig (broken imports)

### Files to Update
- src/shared/term/ansi/mod.zig (remove broken imports)
- src/shared/term/bracketed_paste.zig (merge paste.zig functionality)
- src/shared/term/input/focus.zig (merge focus constants)
- src/shared/term/mod.zig (ensure proper exports)